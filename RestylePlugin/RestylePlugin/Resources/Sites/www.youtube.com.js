// # www.youtube.com
//
// What this script must do, written so it can be rebuilt when YouTube
// changes its page: this comment is the what, the code below the how. When
// they disagree after a YouTube update, this comment wins: measure YouTube's
// page again (see the plugin's AGENTS.md, Trying one) and fix the code to
// meet it.
//
// ## Why
//
// YouTube has its own responsive design, so it keeps it. In Voyager's panel
// its grids still squeeze two or three small thumbnails into a row, and
// Shorts crowd the feed with clips nobody asked for.
//
// ## Styles
//
// | Style | Its purpose |
// |---|---|
// | Default | Browsing videos: one video per row, big enough to judge, no Shorts. |
// | None | Voyager's, on every site: YouTube as it ships. |
//
// 1. **Default.** YouTube's own design, with:
//    - One video per row in every grid (home, subscriptions, a channel's
//      videos), each video the full width of the column.
//    - No Shorts: no Shorts shelves, no Shorts in grids, search results or
//      beside a video, no Shorts entry in the side menu.
//    Covers the main page (the home grid) and the details page (a video:
//    no Shorts shelves among the related videos).
//
// ## Must hold
//
// - Every ordinary video, control and menu item of YouTube's is still
//   there; only Shorts go.
// - YouTube's light and dark themes keep working.
//
// ## YouTube's page, as measured (2026-10-22)
//
// - Grids are `ytd-rich-grid-renderer`, sized by its inline custom
//   properties `--ytd-rich-grid-items-per-row` (videos) and
//   `--ytd-rich-grid-posts-per-row` (community posts), which YouTube sets
//   from the width; an `!important` rule outranks them, and YouTube's own
//   item width then fills the row (no width rule needed; none overflows at
//   900px). Items are `ytd-rich-item-renderer`.
// - Shorts: shelves are `ytd-rich-section-renderer` around a
//   `ytd-rich-shelf-renderer[is-shorts]`, or `ytd-reel-shelf-renderer`
//   (related), or, in search, a `grid-shelf-view-model` of
//   `ytm-shorts-lockup-view-model` items (inside a
//   `ytm-shorts-lockup-view-model-v2`); single Shorts are items whose
//   link goes to `/shorts/…`; the side menu's entries are
//   `ytd-guide-entry-renderer` and `ytd-mini-guide-entry-renderer`; Shorts'
//   links to `/shorts/` (matched by link, not by its title, which is
//   translated).
// - Scope: this file covers www.youtube.com only. m.youtube.com (the phone
//   site Voyager's "Request Mobile Site" opens) is a different page built
//   from `ytm-` elements; music.youtube.com is a different site. Neither is
//   restyled.
//
// ## Source
//
// Inspired by two Tampermonkey userscripts, not taken from them: "YouTube
// Smaller Thumbnails" 0.0.9 (MIT; set the per-row count, but needs
// Tampermonkey's own APIs and a library it downloads) and "Remove YouTube
// Shorts + Best Video Quality" 0.1 (GPL-3; removes Shorts with a script,
// and forces quality through YouTube's player, which Voyager's separate
// script world can't reach). This is CSS of our own.
//
// ## Requests
//
// 2026-10-22
// - One video per row, from YouTube Smaller Thumbnails. → Default: the
//   grid's per-row count pinned to 1.
// - Remove YouTube Shorts. → Default: Shorts hidden everywhere.
// - (Review) a section with one Short in it was hidden whole; the item
//   width rule was redundant; the menu entry was matched by its English
//   title. → Only Shorts shelves and Shorts themselves hidden; YouTube's own
//   width kept; matched by link.

(() => {
  const oneRow = `
    ytd-rich-grid-renderer {
      --ytd-rich-grid-items-per-row: 1 !important;
      --ytd-rich-grid-posts-per-row: 1 !important;
    }
  `;
  const noShorts = `
    ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts]),
    ytd-reel-shelf-renderer,
    grid-shelf-view-model:has(ytm-shorts-lockup-view-model),
    ytm-shorts-lockup-view-model-v2, ytm-shorts-lockup-view-model,
    ytd-rich-item-renderer:has(a[href^="/shorts/"]),
    ytd-video-renderer:has(a[href^="/shorts/"]),
    ytd-compact-video-renderer:has(a[href^="/shorts/"]),
    ytd-guide-entry-renderer:has(a[href^="/shorts"]),
    ytd-mini-guide-entry-renderer:has(a[href^="/shorts"]) { display: none !important; }
  `;

  return {
    variants: {
      default: { label: "Default", style: oneRow + noShorts },
    },
  };
})()
