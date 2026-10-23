// Weibo: which video is under the pointer, and its post for yt-dlp.
//
// Its player's controls sit over the <video>, in a box named for it. The
// video is looked up by its post when there's a link to one; otherwise its
// file plays as it is.
({
  find(stack, x, y) {
    // The pointer has to be on the video itself, not just in a box near it.
    const covers = (v) => {
      const r = v.getBoundingClientRect();
      return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
    };
    let video = null;
    for (const el of stack) {
      const candidates = el instanceof HTMLVideoElement ? [el]
        : [...(el.closest?.('[class*="video" i]')?.querySelectorAll('video') || [])];
      video = candidates.find(covers) || null;
      if (video) break;
    }
    return video ? this.videoOf(video) : null;
  },

  videoOf(video) {
    // A link to a post on Weibo itself: one in the post's text can go
    // anywhere.
    const own = (href) => { try { return /(^|\.)weibo\.(cn|com)$/.test(new URL(href).hostname) ? href : null; } catch { return null; } };
    const post = (/\/(status|detail)\/\w+/.test(location.pathname) && location.href)
      || [...(video.closest('.card, article, [class*="card" i]')?.querySelectorAll('a[href*="/status/"], a[href*="/detail/"]') || [])]
        .map((a) => own(a.href)).find(Boolean);
    if (post) return { element: video, page: post };
    const file = web(video.currentSrc) || web(video.querySelector('source')?.src);
    return file ? { element: video, file } : null;
  },
})
