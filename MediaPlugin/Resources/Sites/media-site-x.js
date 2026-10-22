// X: which video is under the pointer, and its tweet for yt-dlp.
//
// X covers a video with layers of its own, so the video isn't among the
// elements under the pointer: the tweet is, and the video in it whose box
// holds the pointer is the one — a <video>, or, before X has loaded one,
// its poster (an image from X's `…_video_thumb/` paths). Only the tweet on
// top counts — not one under a menu, a dialog or the sidebar. A GIF is a
// plain MP4 file and plays as it is; a video is streamed, so yt-dlp looks
// it up by its tweet — the video at its place in the tweet, when there are
// several. A quoted tweet is drawn inside the one quoting it, and its
// timestamp isn't a link: its video is looked up by the quoting tweet,
// whose videos to yt-dlp are its own and then its quoted tweet's.
({
  find(stack, x, y) {
    const media = this.mediaIn(this.tweetOf(stack[0])).find((el) => {
      const r = el.getBoundingClientRect();
      return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
    });
    return media ? this.videoOf(media) : null;
  },

  // A tweet's videos, in order: each <video>, and each poster of one not
  // loaded yet.
  mediaIn(article) {
    if (!article) return [];
    return [...article.querySelectorAll('video, img[src*="_video_thumb/"]')]
      .filter((el) => el.tagName === 'VIDEO' || !el.closest('[data-testid="videoComponent"], [data-testid="videoPlayer"]')?.querySelector('video'));
  },

  // The tweet on the timeline: the outermost article, as a quoted tweet
  // can be one of its own inside it.
  tweetOf(el) {
    let tweet = el?.closest?.('article');
    while (tweet?.parentElement?.closest('article')) tweet = tweet.parentElement.closest('article');
    return tweet;
  },

  // A video is looked up by its tweet's status, from the tweet's own
  // timestamp link — or, on a tweet's own page, the page's — and by its
  // place among all the tweet's videos, quoted ones last, when there are
  // several: yt-dlp's `#item=N`.
  videoOf(el) {
    if (el instanceof HTMLVideoElement && web(el.currentSrc)) return { element: el, file: el.currentSrc };
    const tweet = this.tweetOf(el);
    if (!tweet) return null;
    const link = [...tweet.querySelectorAll('a[href*="/status/"] time')]
      .find((t) => t.closest('article') === tweet)?.closest('a').href
      || (/\/status\/\d+/.test(location.pathname) ? location.href : null);
    const id = link?.match(/\/status\/(\d+)/)?.[1];
    if (!id) return null;
    const all = this.mediaIn(tweet);
    const page = `https://x.com/i/status/${id}` + (all.length > 1 ? `#item=${all.indexOf(el) + 1}` : '');
    return { element: el, page, video: el instanceof HTMLVideoElement ? el : null };
  },
})
