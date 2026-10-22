import AVFoundation

/// A picture file and a sound file put into one MP4, as they are — nothing
/// re-encoded — for a video saved as its two halves (YouTube's).
///
/// The samples are copied across one by one rather than exported: in
/// YouTube's split files AVFoundation finds an empty marker sample stamped
/// at twice the video's length, so an export of 212 s of video comes out
/// 424 s long, black for the second half. Copying leaves the markers out.
enum VideoJoin {
    enum Failure: Error {
        case missingTrack
        case writeFailed(Error?)
    }

    static func join(picture: URL, sound: URL, into destination: URL) async throws {
        let pictureAsset = AVURLAsset(url: picture), soundAsset = AVURLAsset(url: sound)
        guard let pictureTrack = try await pictureAsset.loadTracks(withMediaType: .video).first,
              let soundTrack = try await soundAsset.loadTracks(withMediaType: .audio).first
        else { throw Failure.missingTrack }

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let pictureIn = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: try await pictureTrack.load(.formatDescriptions).first
        )
        pictureIn.transform = try await pictureTrack.load(.preferredTransform)
        let soundIn = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil,
            sourceFormatHint: try await soundTrack.load(.formatDescriptions).first
        )
        for input in [pictureIn, soundIn] {
            input.expectsMediaDataInRealTime = false
            writer.add(input)
        }

        let pictureReader = try AVAssetReader(asset: pictureAsset)
        let pictureOut = AVAssetReaderTrackOutput(track: pictureTrack, outputSettings: nil)
        pictureReader.add(pictureOut)
        let soundReader = try AVAssetReader(asset: soundAsset)
        let soundOut = AVAssetReaderTrackOutput(track: soundTrack, outputSettings: nil)
        soundReader.add(soundOut)
        guard pictureReader.startReading(), soundReader.startReading(), writer.startWriting() else {
            throw Failure.writeFailed(writer.error ?? pictureReader.error ?? soundReader.error)
        }
        writer.startSession(atSourceTime: .zero)
        await copy([(pictureOut, pictureIn), (soundOut, soundIn)])
        // A reader that stopped early — a cut-off or damaged download — ends
        // the copy as if it were done, and a writer that failed — a full
        // disk — ends it there: nothing half-made is kept.
        if pictureReader.status == .failed || soundReader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw Failure.writeFailed(writer.error ?? pictureReader.error ?? soundReader.error)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.writeFailed(writer.error)
        }
    }

    /// Every sample from each output into its input — both at once, each as
    /// the writer is ready for it, so it can interleave them — leaving out
    /// samples with nothing in them. A sample the writer won't take means
    /// it has failed, and won't ask for more: the copy ends there.
    private static func copy(_ tracks: [(AVAssetReaderTrackOutput, AVAssetWriterInput)]) async {
        let queue = DispatchQueue(label: "Voyager.VideoJoin")
        let box = UncheckedBox(tracks)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var remaining = box.value.count
            var failed = false
            for (output, input) in box.value {
                input.requestMediaDataWhenReady(on: queue) {
                    guard !failed else { return }
                    while input.isReadyForMoreMediaData {
                        guard let sample = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            remaining -= 1
                            if remaining == 0 { done.resume() }
                            return
                        }
                        if CMSampleBufferGetNumSamples(sample) > 0, !input.append(sample) {
                            failed = true
                            done.resume()
                            return
                        }
                    }
                }
            }
        }
    }
}

/// Reader outputs and writer inputs, handed to the writer's queue; they're
/// only touched there.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
