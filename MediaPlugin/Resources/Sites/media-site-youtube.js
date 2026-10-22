// YouTube: which video is under the pointer, and its watch page for yt-dlp.
//
// A video's card — its thumbnail link — and only what's on top, so a card
// under the side menu, a dropdown or a dialog isn't one. The player on a
// watch page isn't one either: it's already playing there, and its controls
// stay the page's. The preview YouTube plays over a card on hover is looked
// through — its boxes measure nothing, its player drawn outside them, and
// the card's link is under it — but its <video> is the card's video while
// it plays, so time is kept with it.
({
  find(stack) {
    const top = stack.find((el) => !el.closest?.('ytd-video-preview, #video-preview'));
    if (!top || top.closest?.('#movie_player')) return null;
    const link = top.closest?.('a[href*="/watch?v="], a[href*="/shorts/"]');
    return link ? this.cardOf(link) : null;
  },

  // A thumbnail link as a card: its video, and YouTube's preview of it while
  // that plays — none until then, so the window starts from the beginning.
  cardOf(link) {
    if (link.closest('#movie_player')) return null;
    const id = link.querySelector('img, video') && big(link) && this.idOf(link.href);
    if (!id) return null;
    const preview = document.querySelector('ytd-video-preview');
    const previewLink = preview?.querySelector('a[href*="/watch?v="], a[href*="/shorts/"]');
    const video = previewLink && this.idOf(previewLink.href) === id ? preview.querySelector('video') : null;
    return { element: link, page: `https://www.youtube.com/watch?v=${id}`, video };
  },

  // A watch or Shorts link's video ID.
  idOf(href) {
    try {
      const u = new URL(href, location.href);
      return u.searchParams.get('v') || u.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]{6,})/)?.[1] || null;
    } catch { return null; }
  },

  // Run in the page's own world, when the window of `page` closes:
  // YouTube's preview player keeps its own time and ignores its video's
  // being set, so it's moved with its own seek — if it's still previewing
  // that video.
  seek(time, page) {
    const preview = document.querySelector('ytd-video-preview');
    const link = preview?.querySelector('a[href*="/watch?v="], a[href*="/shorts/"]');
    if (!link || this.idOf(link.href) !== this.idOf(page)) return;
    preview.querySelector('.html5-video-player')?.seekTo?.(time, true);
  },
})
