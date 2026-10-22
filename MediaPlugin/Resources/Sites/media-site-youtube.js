// YouTube: which video is under the pointer, and its watch page for yt-dlp.
//
// A video's card — its thumbnail link — and only what's on top, so a card
// under the side menu, a dropdown or a dialog isn't one. The player on a
// watch page isn't one either: it's already playing there, and its controls
// stay the page's. The preview YouTube plays over a card on hover is looked
// through — its boxes measure nothing, its player drawn outside them, and
// the card's link is under it — but its <video> is the card's video while
// it plays, so time is kept with it. A video watched before carries on
// where it was left, as on YouTube.
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
    return { element: link, page: `https://www.youtube.com/watch?v=${id}`, video, time: this.resumeOf(link) };
  },

  // Where YouTube would carry on a video watched before: the red bar on its
  // card, as a share of the length on its badge — from the start again once
  // it's nearly all watched, as YouTube does.
  resumeOf(link) {
    const bars = [...link.querySelectorAll('[style*="width"]')]
      .filter((el) => /progress/i.test(`${el.id} ${el.getAttribute('class')}`));
    const bar = bars.find((el) => el.id === 'progress' || /watched/i.test(el.getAttribute('class'))) || bars[0];
    const width = bar?.style.width || '';
    const share = width.endsWith('%') ? parseFloat(width) / 100 : 0;
    const badge = [...link.querySelectorAll('*')]
      .map((el) => el.childElementCount ? '' : el.textContent.trim())
      .find((text) => /^\d+(:\d{2}){1,2}$/.test(text));
    if (!(share > 0 && share < 0.95) || !badge) return 0;
    return Math.floor(badge.split(':').reduce((sum, n) => sum * 60 + Number(n), 0) * share);
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
  // that video. And the watch goes into the history.
  seek(time, page) {
    this.watched(time, page).catch(() => {});
    const preview = document.querySelector('ytd-video-preview');
    const link = preview?.querySelector('a[href*="/watch?v="], a[href*="/shorts/"]');
    if (!link || this.idOf(link.href) !== this.idOf(page)) return;
    preview.querySelector('.html5-video-player')?.seekTo?.(time, true);
  },

  // YouTube keeps a watch in the history — and where it stopped, to resume
  // from — from its player's reports, which a video played elsewhere never
  // makes. Made here instead, as yt-dlp's `--mark-watched` makes them: the
  // watch page's playback and watch-time pings, sent with the page's
  // cookies, so they count for whoever's signed in.
  async watched(time, page) {
    const id = this.idOf(page);
    if (!id || !(time > 0)) return;
    const html = await (await fetch(`/watch?v=${id}`, { credentials: 'include' })).text();
    const ping = (key) => {
      const raw = html.match(new RegExp(`"${key}":\\{"baseUrl":"((?:[^"\\\\]|\\\\.)+)"`))?.[1];
      return raw ? new URL(JSON.parse(`"${raw}"`), location.href) : null;
    };
    const playback = ping('videostatsPlaybackUrl'), watchtime = ping('videostatsWatchtimeUrl');
    if (!playback || !watchtime) return;
    // One playback, named as YouTube's player names one: 16 of its
    // alphabet's characters.
    const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    const cpn = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => alphabet[b & 63]).join('');
    const at = String(Math.min(time, Number(watchtime.searchParams.get('len')) || time));
    for (const url of [playback, watchtime]) {
      url.searchParams.set('ver', '2');
      url.searchParams.set('cpn', cpn);
      url.searchParams.set('cmt', at);
      url.searchParams.set('el', 'detailpage');
    }
    watchtime.searchParams.set('st', '0');
    watchtime.searchParams.set('et', at);
    await fetch(playback, { mode: 'no-cors', credentials: 'include' });
    await fetch(watchtime, { mode: 'no-cors', credentials: 'include' });
  },
})
