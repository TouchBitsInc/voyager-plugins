import Foundation

/// What the plugin's settings window sets: where saved videos go.
@MainActor
@Observable
final class PluginSettings {
    static let shared = PluginSettings()

    /// The Downloads folder, unless another's chosen.
    var downloadFolder: URL {
        didSet { UserDefaults.standard.set(downloadFolder.path, forKey: Self.downloadFolderKey) }
    }

    static let defaultDownloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private static let downloadFolderKey = "download_folder"

    private init() {
        // A folder since moved or deleted: back to Downloads.
        if let path = UserDefaults.standard.string(forKey: Self.downloadFolderKey), FileManager.default.fileExists(atPath: path) {
            downloadFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            downloadFolder = Self.defaultDownloadFolder
        }
    }
}
