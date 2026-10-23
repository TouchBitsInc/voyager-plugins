// # m.weibo.cn
//
// What this script must do, written so it can be rebuilt when Weibo changes
// its page: this comment is the what, the code below the how. When they
// disagree after a Weibo update, this comment wins.
//
// ## Why
//
// Weibo's mobile site is what Voyager opens for 微博. Its own chrome is
// cluttered and dated beside Voyager's: grey placeholders, orange VIP
// names, a top toolbar of tiny icons.
//
// ## Styles
//
// | Style | Its purpose |
// |---|---|
// | Default | Everyday use: a clean, Mac-like Weibo — one centred column, tidy post cells, round toolbar buttons, outline icons, light and dark. |
// | None | Voyager's, on every site: Weibo as it ships. |
//
// 1. **Default.** The "Weibo Clean Skin" userscript, as published,
//    unchanged below (its own comments describe it). Among other things:
//    - Weibo's top toolbar becomes an iOS-style tab bar at the bottom:
//      ☰ menu | Following | Hot | More | Post — five items, within the
//      bottom-bar limit (AGENTS.md).
//    - ☰ opens a menu of Weibo's sections; Post opens Weibo's composer in a
//      sheet.
//    - Light and dark follow the system.
//    It can't be undone in place (its own `<style>` and listeners), so it's
//    `reload: true`: switching to or from it reloads the page.
//
// ## Must hold
//
// - Updating it means taking the newer published version whole, then
//   re-checking it: same-origin requests only (it reads /api/config and
//   /api/container/getIndex, nothing else), no eval, no cookies or storage.
// - Known gap in Voyager: its composer closes itself when Weibo's composer
//   navigates back by patching the page's own `history`, which Voyager's
//   separate script world can't reach. Close it with the scrim or Escape.
//
// ## Source
//
// https://greasyfork.org/en/scripts/601339-weibo-clean-skin, version 3.7.1,
// by gdragon, MIT licence. Its header, as published:
//
// // ==UserScript==
// // @name         Weibo Clean Skin
// // @namespace    https://greasyfork.org/users/gdragon
// // @version      3.7.1
// // @description  A clean, Mac-like skin for m.weibo.cn: one centred column, tidy post cells, round toolbar buttons, outline icons, light and dark mode.
// // @author       gdragon
// // @license      MIT
// // @match        https://m.weibo.cn/*
// // @run-at       document-start
// // @grant        none
// // @downloadURL https://update.greasyfork.org/scripts/601339/Weibo%20Clean%20Skin.user.js
// // @updateURL https://update.greasyfork.org/scripts/601339/Weibo%20Clean%20Skin.meta.js
// // ==/UserScript==
//
// ## Requests
//
// 2026-10-22
// - Apply the Weibo Clean Skin userscript to Weibo. → One style, the
//   default; reloads on switch.
// - Just one style, called Default. → Labelled Default in Styles.

(() => ({
  variants: {
    clean: {
      label: "Default",
      reload: true,
      start() {
// Icons are drawn for this script. Not affiliated with Weibo.

(function () {
  'use strict';

  // A Chinese browser gets Chinese labels and keeps Weibo's own wording; any other gets English.
  // The bar and the ☰ menu always read in Chinese, like the channels beside them.
  const ZH = /^zh/i.test(navigator.language || '');
  const L = (en, zh) => (ZH ? zh : en);
  const NAV = (en, zh) => zh;

  // Outline icons drawn for this script (24pt grid, rounded strokes). They are used as
  // CSS masks, so only their shape matters.
  const svg = (body, width = 1.8) => 'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`);
  const BUBBLE = '<path d="M9 4.5h6a6 6 0 0 1 0 12h-2.2L8.5 20v-3.6A6 6 0 0 1 9 4.5z"/>';
  const HEART = '<path d="M12 20s-7.6-4.6-8.9-9.4C2.3 7.6 4.4 5 7.4 5c1.9 0 3.5 1 4.6 2.6C13.1 6 14.7 5 16.6 5c3 0 5.1 2.6 4.3 5.6C19.6 15.4 12 20 12 20z"/>';
  const ICONS = {
    // ☰ menu sections
    timeline: svg('<path d="M3.5 10.2L12 3.5l8.5 6.7V20a1 1 0 0 1-1 1H15v-6.5H9V21H4.5a1 1 0 0 1-1-1z"/>'),
    mentions: svg('<circle cx="12" cy="12" r="3.6"/><path d="M15.6 12v1.4a2.4 2.4 0 0 0 4.8 0V12A8.4 8.4 0 1 0 17 18.8"/>'),
    comments: svg(BUBBLE),
    likes: svg(HEART),
    star: svg('<path d="M6.5 3.5h11a1 1 0 0 1 1 1V21L12 16.8 5.5 21V4.5a1 1 0 0 1 1-1z"/>'),
    profile: svg('<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5c.7-3.8 3.7-6.2 7.5-6.2s6.8 2.4 7.5 6.2"/>'),
    search: svg('<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.4 15.4L20.5 20.5"/>', 2),
    // Action row
    act_reposts: svg('<path d="M4.5 9.5V8A2.5 2.5 0 0 1 7 5.5h11M15 2.5l3 3-3 3M19.5 14.5V16a2.5 2.5 0 0 1-2.5 2.5H6M9 21.5l-3-3 3-3"/>'),
    act_comments: svg(BUBBLE),
    act_likes: svg(HEART),
    // Verified badge: a scalloped rosette with the check cut out
    badge_check: svg('<defs><mask id="c"><rect width="24" height="24" fill="#fff"/><path d="M8 12.3l2.8 2.7L16.2 9.6" stroke="#000" stroke-width="2.3"/></mask></defs><path mask="url(#c)" fill="#000" stroke="#000" stroke-width="2" d="M12 2.4L15.06 4.61 18.79 5.21 19.39 8.94 21.6 12 19.39 15.06 18.79 18.79 15.06 19.39 12 21.6 8.94 19.39 5.21 18.79 4.61 15.06 2.4 12 4.61 8.94 5.21 5.21 8.94 4.61z"/>'),
    // Toolbar and comment glyphs
    back: svg('<path d="M20 12H4.5M10.5 5.5L4 12l6.5 6.5"/>', 2),
    // Tab bar glyphs: a lighter stroke than the rest
    list: svg('<path d="M4 6.5h16M4 12h16M4 17.5h16"/>', 1.4),
    post: svg('<path d="M10.8 4.2H6.6a2.4 2.4 0 0 0-2.4 2.4v10.8a2.4 2.4 0 0 0 2.4 2.4h10.8a2.4 2.4 0 0 0 2.4-2.4v-4.2"/><path d="M18.2 3.4a1.9 1.9 0 0 1 2.8 2.8L12 15.1l-3.6.8.8-3.6z"/>', 1.4),
    following: svg('<circle cx="9.5" cy="8" r="3.6"/><path d="M3 20c.6-3.5 3.2-5.7 6.5-5.7s5.9 2.2 6.5 5.7"/><path d="M15.5 4.7a3.6 3.6 0 0 1 0 6.6M17.6 14.6c1.9.8 3.1 2.7 3.4 5.4"/>', 1.4),
    hot: svg('<path d="M12 21c-3.9 0-6.5-2.7-6.5-6.3 0-3.4 2.3-5.3 3.6-8.2.5 1.9 1.4 3.1 2.6 3.7C12 7.1 13 4.8 15 3c.3 3.4 3.5 5.8 3.5 10.4 0 4.7-2.6 7.6-6.5 7.6z"/>', 1.4),
    channels: svg('<rect x="4" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.6"/>', 1.4),
    reply: svg(BUBBLE),
  };

  const COMPOSE = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M9 3.5H5.5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V11"/>' +
    '<path d="M15.2 2.8a1.6 1.6 0 0 1 2.3 2.3L10 12.6l-3 .7.7-3z"/></svg>');
  const CHEVRON = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 6" fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M1 1l4 4 4-4"/></svg>');
  const MORE = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="#000">' +
    '<circle cx="4.5" cy="10" r="1.6"/><circle cx="10" cy="10" r="1.6"/><circle cx="15.5" cy="10" r="1.6"/></svg>');

  const CSS = String.raw`
:root {
  --mp-col: 600px;
  --mp-colx: max(0px, calc((100vw - var(--mp-col)) / 2));

  /* Palette: light, then dark below */
  --mp-page: #f2f2f2;
  --mp-cell: #ffffff;
  --mp-detail: #f8f5f5;
  --mp-text: #2e2e2e;
  --mp-quote-text: #383838;
  --mp-link: #576c79;
  --mp-tag: #828282;
  --mp-name: #000000;
  --mp-meta: #a6a6a6;
  --mp-quote-bg: rgba(0, 0, 0, 0.03);
  --mp-line: rgba(0, 0, 0, 0.06);
  --mp-action: rgba(0, 0, 0, 0.4);
  --mp-accent: #008ffc;
  --mp-side-sel: #3f7efc;
  --mp-bar: rgba(255, 255, 255, 0.7);
  --mp-title: rgba(0, 0, 0, 0.88);
  --mp-button: rgba(255, 255, 255, 0.75);
  --mp-button-line: rgba(0, 0, 0, 0.1);
  --mp-button-icon: rgba(0, 0, 0, 0.6);
  --mp-seg: rgba(0, 0, 0, 0.04);
  --mp-seg-sel: rgba(0, 0, 0, 0.08);
  --mp-badge-blue: #22abff;
  --mp-badge-orange: #ffa523;
}
@media (prefers-color-scheme: dark) {
  :root {
    --mp-page: #232323;
    --mp-cell: #191919;
    --mp-detail: #202323;
    --mp-text: #d7d7d7;
    --mp-quote-text: #bebebe;
    --mp-link: #98b6ca;
    --mp-tag: #828282;
    --mp-name: #f5f5f5;
    --mp-meta: #8c8c8c;
    --mp-quote-bg: rgba(0, 0, 0, 0.4);
    --mp-line: rgba(255, 255, 255, 0.06);
    --mp-side-sel: #5bccff;
    --mp-action: rgba(255, 255, 255, 0.65);
    --mp-bar: rgba(25, 25, 25, 0.7);
    --mp-title: rgba(255, 255, 255, 0.88);
    --mp-button: rgba(255, 255, 255, 0.08);
    --mp-button-line: rgba(255, 255, 255, 0.1);
    --mp-button-icon: rgba(255, 255, 255, 0.6);
    --mp-seg: rgba(255, 255, 255, 0.05);
    --mp-seg-sel: rgba(255, 255, 255, 0.12);
    --mp-badge-blue: #0099ff;
    --mp-badge-orange: #ffb800;
  }
}
@media (max-width: 640px) {
  :root { --mp-col: 100vw; }
}

/* ---------- Window: one centred column ---------- */
html, body { background: var(--mp-page) !important; -webkit-font-smoothing: antialiased; }
body, #app, button, input, textarea {
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif !important;
}
#app.m-container-max { max-width: none !important; margin: 0 !important; }
#app > div:first-child, #app .main-wrap, #app .lite-page-wrap {
  width: var(--mp-col) !important;
  max-width: none !important;
  margin-left: var(--mp-colx) !important;
  margin-right: 0 !important;
  min-height: 100vh;
  background: var(--mp-cell) !important;
}
#app .main-wrap { margin-top: 50px !important; }
/* The timeline's toolbar sits at the bottom, so its column starts at the top */
#app .main-wrap:has(> .main-top) { margin-top: 0 !important; padding-bottom: calc(44px + env(safe-area-inset-bottom)); }
#app > div:first-child { overflow-x: hidden; }
#app .pannelwrap, #app .wb-item-wrap, #app .wb-item, #app .comment-content { background: transparent !important; }
#app .ad-wrap, #app .vipicon { display: none !important; }
/* Weibo's skeleton cards (grey avatar + text bars) are hidden; a small spinner shows instead */
#app .wb-item-wrap:has(.anim-load), #app .card:has(.anim-load) { display: none !important; }
#app:has(.anim-load)::after {
  content: "";
  position: fixed;
  z-index: 999;
  top: 74px;
  left: calc(var(--mp-colx) + var(--mp-col) / 2 - 10px);
  width: 20px;
  height: 20px;
  box-sizing: border-box;
  border-radius: 50%;
  border: 2px solid var(--mp-line);
  border-top-color: var(--mp-meta);
  animation: mp-spin 0.8s linear infinite;
}
#app:has(.main-top):has(.anim-load)::after { top: 24px; }
@keyframes mp-spin { to { transform: rotate(360deg); } }
/* No grey placeholder boxes while images load */
#app .m-img-box:has(> img) { background-color: transparent !important; }
/* Every Weibo list card takes the cell colour (light and dark) */
#app .card, #app .lite-msg-list { background-color: var(--mp-cell) !important; }
/* Weibo's list pages hard-code #333 / #636363 text and #e6e6e6 lines; map them to the theme
   (kept early so the post and comment rules below still win) */
#app .card .m-text-box h3, #app .card h3, #app .main-text, #app .main-link { color: var(--mp-text) !important; }
#app .card .m-text-box h4, #app .nav-ctrl { color: var(--mp-meta) !important; }
#app .card, #app .lite-line, #app .box-right { border-color: var(--mp-line) !important; }
#app .text-box h4, #app .m-item-box h4 { color: var(--mp-text) !important; }
#app .m-item-box::after { background-color: var(--mp-line) !important; }
#app .cmt-sub-txt p span:not(.url-icon) { color: inherit !important; }
#app .cmt-sub-txt a, #app .cmt-sub-txt .surl-text { color: var(--mp-link) !important; }
#app .lite-page-list h3 .surl-text { color: var(--mp-link) !important; }
/* Weibo's white edge fades on scrolling tab strips */
#app .slide-container::before, #app .slide-container::after { display: none !important; }
/* Every name looks alike: no VIP orange */
#app h3.vip, #app h3.vip span { color: var(--mp-name) !important; }
#app .color-orange { color: var(--mp-link) !important; }
#app .card .m-font-arrow-right { background: transparent !important; color: var(--mp-meta) !important; }
#app [class*="m-icon-vipl"] { display: none !important; }
#app .card42::before { background: var(--mp-line) !important; }

/* ---------- Toolbars: 50pt, title Bold 14, 32pt round buttons 9pt in ---------- */
#app .lite-topbar {
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  max-width: none !important;
  margin: 0 !important;
  height: 50px !important;
  z-index: 1000 !important;
  background: var(--mp-bar) !important;
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px);
  border: 0 !important;
  box-shadow: none !important;
}
#app .lite-topbar *, #app .lite-topbar .nav-main .m-box { background-color: transparent !important; }
#app .main-top .nav-plus, #app .main-top .lite-iconf-releas,
#app .lite-page-top .nav-left, #app .lite-page-top .nav-right,
#app .prf-topbar .nav-left, #app .prf-topbar .nav-right {
  position: absolute !important;
  top: 9px !important;
  width: 32px !important;
  height: 32px !important;
  padding: 0 !important;
  margin: 0 !important;
  border-radius: 50% !important;
  box-sizing: border-box;
  background: var(--mp-button) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 1px 2px rgba(0, 0, 0, 0.04);
  display: flex !important;
  align-items: center;
  justify-content: center;
  font-size: 0 !important;
  cursor: pointer;
}
#app .main-top .nav-plus::after, #app .main-top .lite-iconf-releas::after,
#app .lite-page-top .nav-left::after, #app .lite-page-top .nav-right::after,
#app .prf-topbar .nav-left::after, #app .prf-topbar .nav-right::after {
  content: "";
  background: var(--mp-button-icon);
  -webkit-mask: var(--mp-glyph) center / contain no-repeat;
  mask: var(--mp-glyph) center / contain no-repeat;
}
#app .main-top .nav-plus > *, #app .main-top .lite-iconf-releas::before,
#app .lite-page-top .nav-left > *, #app .lite-page-top .nav-right > *,
#app .prf-topbar .nav-left > *, #app .prf-topbar .nav-right > *,
#app .main-top .nav-plus::before { display: none !important; }

/* Timeline toolbar, along the bottom as an iOS tab bar: Menu | Following | Hot | More | Post,
   five equal columns, each a glyph over a small label */
#app .lite-topbar.main-top {
  top: auto !important;
  bottom: 0 !important;
  height: calc(44px + env(safe-area-inset-bottom)) !important;
  padding-bottom: env(safe-area-inset-bottom) !important;
  box-sizing: border-box !important;
  box-shadow: inset 0 0.5px 0 var(--mp-line) !important;
}
#app .main-top .nav-search, #app .main-top .nav-left, #app .main-top .lite-iconf-msg { display: none !important; }
#app .main-top .nav-top { height: 44px !important; position: relative; }
#app .main-top .nav-right {
  position: absolute !important;
  top: 0 !important;
  right: 0 !important;
  left: auto !important;
  width: 20% !important;
  height: 44px !important;
}
#app .main-top .nav-main { top: 0 !important; height: 44px !important; line-height: 44px !important; left: 0 !important; right: 0 !important; }
#app .main-top .nav-main .m-box, #app .main-top .inner-box { height: 44px !important; }
#app .main-top .inner-box { display: flex !important; justify-content: center; }
#app .main-top .inner-box::before { display: none !important; }
/* Weibo's tab strip is hidden; the centre holds our channel switcher */
#app .main-top .slide-container, #app .main-top .inner-box::after { display: none !important; }

/* Tab items: no round button, glyph on top, label under it */
#app .main-top .nav-plus, #app .main-top .lite-iconf-releas, #mp-feeds > button {
  top: 0 !important;
  height: 44px !important;
  padding: 4px 0 0 !important;
  border-radius: 0 !important;
  background: transparent !important;
  box-shadow: none !important;
  justify-content: flex-start !important;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  color: var(--mp-button-icon);
}
#app .main-top .nav-plus { left: 0 !important; width: 20% !important; --mp-glyph: url("${ICONS.list}"); }
#app .main-top .lite-iconf-releas { right: 0 !important; left: auto !important; width: 100% !important; --mp-glyph: url("${ICONS.post}"); }
#app .main-top .nav-plus::after, #app .main-top .lite-iconf-releas::after {
  order: 0;
  width: 22px;
  height: 22px;
  -webkit-mask-size: 18px;
  mask-size: 18px;
}
#app .main-top .lite-iconf-releas::after { -webkit-mask-size: 18px; mask-size: 18px; }
#app .main-top .nav-plus::before, #app .main-top .lite-iconf-releas::before {
  order: 1;
  display: block !important;
  position: static !important;
  width: auto !important;
  height: auto !important;
  margin: 0 !important;
  transform: none !important;
  background: none !important;
  font: 500 10px/12px -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif !important;
  letter-spacing: 0.1px;
  color: inherit !important;
}
#app .main-top .nav-plus::before { content: "${NAV('Menu', '菜单')}"; }
#app .main-top .lite-iconf-releas::before { content: "${NAV('Post', '发布')}"; }
/* The feeds: Following and Hot switch straight to theirs; More opens the channel sheet */
#mp-feeds {
  position: absolute;
  top: 0;
  left: 20%;
  width: 60%;
  height: 44px;
  display: flex;
}
#mp-feeds > button {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-flow: row wrap;
  align-content: flex-start;
  justify-content: center !important;
  gap: 2px;
  box-sizing: border-box;
  border: 0;
  font: 500 10px/12px -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
  cursor: pointer;
}
/* A feed tab's glyph takes a line of its own; its label sits under it */
#mp-feeds > button::before {
  content: "";
  flex: 0 0 100%;
  height: 22px;
  background: currentColor;
  -webkit-mask: var(--mp-icon) center / 18px no-repeat;
  mask: var(--mp-icon) center / 18px no-repeat;
}
#mp-feeds span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
/* The current feed, and the tab whose popup is open, take the accent */
#app .main-top .nav-plus::after, #app .main-top .lite-iconf-releas::after { background: currentColor; }
body:has(#mp-menu:not([hidden])) #app .main-top .nav-plus,
#mp-feeds > .mp-sel, #mp-channel[aria-expanded="true"] { color: var(--mp-accent) !important; }
#app .main-top .nav-plus:active, #app .main-top .lite-iconf-releas:active, #mp-feeds > button:active { opacity: 0.6; }
/* Weibo's dialogs dim the page from inside the timeline's scroller, under the bar; the bar
   takes the same dimming, and waits until the dialog closes */
body:has(.m-pop) #app .main-top::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: 1;
  background: rgba(0, 0, 0, 0.4);
}

/* Post: Weibo's composer in a sheet over the timeline, which stays put underneath */
#mp-compose .mp-scrim {
  position: fixed;
  inset: 0;
  z-index: 1004;
  background: rgba(0, 0, 0, 0.25);
  opacity: 0;
  transition: opacity 0.25s;
}
#mp-compose .mp-sheet {
  position: fixed;
  z-index: 1005;
  left: var(--mp-colx);
  bottom: 0;
  width: var(--mp-col);
  height: min(440px, 75vh);
  transition: transform 0.28s cubic-bezier(0.2, 0.9, 0.3, 1), height 0.2s;
  border-radius: 12px 12px 0 0;
  overflow: hidden;
  background: var(--mp-cell);
  box-shadow: 0 0 0 0.5px var(--mp-button-line), 0 -8px 30px rgba(0, 0, 0, 0.18);
  transform: translateY(100%);
}
#mp-compose.mp-open .mp-scrim { opacity: 1; }
#mp-compose.mp-open .mp-sheet { transform: none; }
#mp-compose iframe { display: block; width: 100%; height: 100%; border: 0; }

/* Channels sheet (Weibo's picker, opened from ☰ › Channels): chips like the segmented control,
   rising above the toolbar */
#app .main-top .lite-nav-sublist {
  top: auto !important;
  bottom: 100% !important;
  left: 0 !important;
  right: 0 !important;
  width: auto !important;
  height: auto !important;
  padding: 10px 9px 12px !important;
  box-sizing: border-box;
  background: var(--mp-cell) !important;
  border-top: 0.5px solid var(--mp-line) !important;
  box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.08) !important;
}
#app .main-top .lite-nav-sublist .m-auto-list {
  display: grid !important;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
  width: auto !important;
  margin: 0 !important;
  padding: 0 !important;
}
#app .main-top .lite-nav-sublist .m-auto-box {
  width: auto !important;
  height: 32px !important;
  margin: 0 !important;
  padding: 0 !important;
  border-radius: 16px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  display: flex !important;
  align-items: center;
  justify-content: center;
  font-size: 13px !important;
  line-height: 32px !important;
  color: var(--mp-button-icon) !important;
  cursor: pointer;
}
#app .main-top .lite-nav-sublist .m-auto-box * {
  position: static !important;
  display: block !important;
  width: auto !important;
  height: auto !important;
  margin: 0 !important;
  padding: 0 !important;
  text-align: center !important;
  transform: none !important;
  font-size: inherit !important;
  line-height: inherit !important;
  color: inherit !important;
  border: 0 !important;
  background: transparent !important;
}
#app .main-top .lite-nav-sublist .m-auto-box.cur {
  background: var(--mp-seg-sel) !important;
  color: var(--mp-name) !important;
  font-weight: 600 !important;
}

/* ☰ menu: the main sections, above the button */
#mp-menu {
  position: fixed;
  z-index: 1003;
  bottom: calc(50px + env(safe-area-inset-bottom));
  left: calc(var(--mp-colx) + 9px);
  width: 200px;
  padding: 6px;
  box-sizing: border-box;
  border-radius: 12px;
  background: var(--mp-bar);
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px);
  box-shadow: 0 0 0 0.5px var(--mp-button-line), 0 8px 24px rgba(0, 0, 0, 0.14);
  font-size: 13px;
  -webkit-user-select: none;
  user-select: none;
}
#mp-menu[hidden] { display: none; }
#mp-menu a {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 32px;
  padding: 0 8px;
  border-radius: 7px;
  color: var(--mp-name) !important;
  text-decoration: none;
}
#mp-menu a:hover { background: var(--mp-seg-sel); }
#mp-menu .mp-me { height: 44px; font-size: 14px; font-weight: 700; }
#mp-menu .mp-avatar {
  flex: none;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: var(--mp-line) center / cover;
}
#mp-menu hr { height: 0; margin: 4px 8px; border: 0; border-top: 0.5px solid var(--mp-line); }
#mp-menu i {
  flex: none;
  width: 20px;
  height: 21.5px;
  background: var(--mp-button-icon);
  -webkit-mask: var(--mp-icon) center / contain no-repeat;
  mask: var(--mp-icon) center / contain no-repeat;
}
#mp-menu .mp-sel { color: var(--mp-side-sel) !important; }
#mp-menu .mp-sel i { background: var(--mp-side-sel); }

/* Detail and inbox toolbars: round back | segmented control | round more */
#app .lite-page-top .nav-left { left: 9px !important; --mp-glyph: url("${ICONS.back}"); }
#app .lite-page-top .nav-left::after { width: 18px; height: 18px; }
#app .lite-page-top .nav-right { right: 9px !important; left: auto !important; --mp-glyph: url("${MORE}"); }
#app .lite-page-top .nav-right::after { width: 18px; height: 18px; }
#app .lite-page-top .nav-main { position: absolute !important; inset: 0 !important; display: flex !important; align-items: center; justify-content: center; }
#app .lite-page-top .nav-main h4 { font-size: 14px !important; font-weight: 700 !important; color: var(--mp-title) !important; }
#app .lite-page-wrap:has(.lite-page-tab) .lite-page-top .nav-main h4 { visibility: hidden; }

#app .lite-page-tab, #app .lite-page-top .nav_item {
  display: flex !important;
  align-items: center;
  gap: 2px;
  height: 32px !important;
  padding: 0 4px !important;
  box-sizing: border-box;
  border-radius: 16px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  border: 0 !important;
  width: auto !important;
  transform: none !important;
}
#app .lite-page-tab {
  position: fixed !important;
  z-index: 1002;
  top: 9px;
  left: calc(var(--mp-colx) + var(--mp-col) / 2);
  transform: translateX(-50%) !important;
  margin: 0 !important;
}
#app .lite-page-tab .tab-item, #app .lite-page-top .nav_item .item_li {
  flex: none !important;
  height: 24px !important;
  line-height: 24px !important;
  padding: 0 14px !important;
  margin: 0 !important;
  border-radius: 12px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  color: var(--mp-button-icon) !important;
  cursor: pointer;
}
#app .lite-page-tab .tab-item.cur, #app .lite-page-top .nav_item .item_li.cur {
  background: var(--mp-seg-sel) !important;
  color: var(--mp-name) !important;
  font-weight: 600 !important;
}
#app .lite-page-tab .tab-item i { font-style: normal; }
#app .lite-page-tab .tab-item i:nth-child(2), #app .lite-page-tab em, #app .lite-page-top .nav_item em { display: none !important; }
#app .lite-page-top .slide-container, #app .lite-page-top .slide-wrap, #app .lite-page-top .inner-box { width: auto !important; transform: none !important; }
#app .lite-page-top .inner-box::before, #app .lite-page-top .inner-box::after { display: none !important; }

/* Detail page: tinted root post, white replies */
#app .lite-page-wrap > div > .main { padding-top: 50px !important; margin-top: 0 !important; background: var(--mp-detail) !important; }
#app .lite-page-wrap .main .card9 { background: var(--mp-detail) !important; }
#app .lite-page-wrap .main .card9::after { left: 0; }

/* Bottom reply bar */
#app .lite-page-editor {
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  max-width: none !important;
  margin: 0 !important;
  background: var(--mp-bar) !important;
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px);
  border-top: 0.5px solid var(--mp-line) !important;
  box-shadow: none !important;
}
#app .lite-page-editor .m-box, #app .lite-page-editor .box-left { background: transparent !important; }
#app .lite-page-editor .main-text {
  background: var(--mp-seg) !important;
  border-radius: 16px !important;
  height: 32px !important;
  line-height: 32px !important;
  padding: 0 14px !important;
  font-size: 13px !important;
  color: var(--mp-meta) !important;
}
#app .lite-page-editor i { color: var(--mp-button-icon) !important; }

/* ---------- Status cell ---------- */
#app .card9 {
  position: relative;
  margin: 0 !important;
  border: 0 !important;
  background: var(--mp-cell) !important;
  color: var(--mp-text) !important;
}
#app .card9::after {
  content: "";
  position: absolute;
  left: 70px;
  right: 0;
  bottom: 0;
  border-bottom: 0.5px solid var(--mp-line);
}
#app .card9 .card-wrap { background: transparent !important; margin: 0 !important; padding: 0 !important; }
#app .card9 > .card-wrap { padding: 10px 10px 0 !important; }
/* Variant used by /p/index lists and search: card9 > card-wrap > card-main (padded already) */
#app .card9 > .card-wrap:has(> .card-main) { padding: 0 !important; }
#app .card9 .card-main { padding: 10px 10px 0 !important; margin: 0 !important; width: auto !important; border: 0 !important; }
#app .card9 .card-main > .weibo-main { padding: 0 0 0 60px !important; margin: 0 !important; }
#app .card9 .card-main > .m-ctrl-box { margin-left: 60px !important; }
#app .card9 .m-ctrl-box .m-line-gradient, #app .card9 .tips-box:empty { display: none !important; }

/* Header: 50pt avatar at 10,10; name Bold 14 at y10-32; meta Light 11 at y30-45; body at y46 */
#app .weibo-top { height: 36px !important; padding: 0 !important; align-items: flex-start !important; overflow: visible !important; }
#app .weibo-top .m-avatar-box { margin: 0 10px 0 0 !important; align-self: flex-start; flex: none !important; }
#app .weibo-top > .m-img-box { width: 50px !important; height: 50px !important; margin: 0 10px 0 0 !important; flex: none !important; align-self: flex-start; }
#app .weibo-top > .m-img-box > img { width: 50px !important; height: 50px !important; border-radius: 50% !important; }
#app .weibo-top .m-avatar-box .m-img-box, #app .weibo-top .m-avatar-box img,
#app .lite-page-list .card-main > .m-box > .m-img-box, #app .lite-page-list .card-main > .m-box > .m-img-box > img,
#app .lite-msg .card-main > .m-box > .m-img-box, #app .lite-msg .card-main > .m-box > .m-img-box > img {
  width: 50px !important;
  height: 50px !important;
  border-radius: 50% !important;
}
#app .m-avatar-box .m-img-box, #app .card-main > .m-box > .m-img-box { position: relative; overflow: visible !important; }
#app .weibo-top .m-box-col { min-width: 0; }
#app .weibo-top .m-text-box { padding: 0 !important; margin: 0 !important; }
#app .weibo-top .m-text-box > a { margin: 0 !important; display: block; }
#app .weibo-top h3, #app .lite-page-list .m-text-box h4, #app .lite-msg .m-text-box > h4 {
  color: var(--mp-name) !important;
  font-size: 14px !important;
  font-weight: 700 !important;
  line-height: 22px !important;
  height: 22px;
  margin: 0 !important;
}
#app .weibo-top h4, #app .weibo-top h4 span,
#app .lite-page-list .lite-bot .time, #app .lite-msg .lite-time {
  color: var(--mp-meta) !important;
  font-size: 11px !important;
  font-weight: 300 !important;
  line-height: 15px !important;
}
#app .weibo-top h4 { margin: -2px 0 0 !important; height: 15px; }
#app .weibo-top h4 .from.mp-dot::before { content: "\2022"; margin: 0 4px; }

/* "+ 关注" on posts from people you don't follow: the same pill as the profile's edit button */
#app .weibo-top .m-followBtn { flex: none !important; align-self: flex-start; margin: 0 0 0 8px !important; }
/* Weibo greys the whole wrapper while pressed; only the pill dims */
#app .weibo-top .m-followBtn, #app .weibo-top .m-followBtn.m-active { background-color: transparent !important; -webkit-tap-highlight-color: transparent; }
#app .weibo-top .m-followBtn.m-active > .m-add-box { opacity: 0.6; }
#app .weibo-top .m-followBtn > .m-add-box {
  display: inline-flex !important;
  align-items: center;
  gap: 3px;
  width: auto !important;
  height: 28px !important;
  padding: 0 14px !important;
  border: 0 !important;
  border-radius: 14px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  color: var(--mp-button-icon) !important;
  cursor: pointer;
}
#app .weibo-top .m-followBtn > .m-add-box::before, #app .weibo-top .m-followBtn > .m-add-box::after { display: none !important; }
#app .weibo-top .m-followBtn i { font-size: 12px !important; line-height: 28px !important; color: inherit !important; }
/* While following: a small ring in place of Weibo's spinner (drawn for a far larger button),
   and the pill keeps its width */
#app .weibo-top .m-followBtn > .m-add-box:has(.m-loading) { min-width: 70px; justify-content: center; box-sizing: border-box; }
#app .weibo-top .m-followBtn .m-loading {
  flex: none;
  width: 14px !important;
  height: 14px !important;
  margin: 0 !important;
  font-size: 0 !important;
  box-sizing: border-box;
  border-radius: 50%;
  border: 1.5px solid var(--mp-line);
  border-top-color: var(--mp-button-icon);
  animation: mp-spin 0.8s linear infinite;
}
#app .weibo-top .m-followBtn .m-loading span { display: none !important; }

/* Weibo's dialogs (follow › choose group and the like): a rounded card like the ☰ menu */
#app .m-pop {
  width: 300px !important;
  max-width: calc(100vw - 32px);
  padding: 0 !important;
  border: 0 !important;
  border-radius: 14px !important;
  overflow: hidden;
  background: var(--mp-cell) !important;
  box-shadow: 0 0 0 0.5px var(--mp-button-line), 0 12px 40px rgba(0, 0, 0, 0.2) !important;
  color: var(--mp-name) !important;
}
#app .m-pop > header {
  height: auto !important;
  margin: 0 !important;
  padding: 18px 16px 6px !important;
  border: 0 !important;
  font-size: 16px !important;
  font-weight: 600 !important;
  line-height: 22px !important;
  text-align: center !important;
  color: var(--mp-name) !important;
}
#app .m-pop > section { margin: 0 !important; padding: 4px 8px 8px !important; }
#app .m-pop > section ul, #app .m-pop > section li { width: auto !important; margin: 0 !important; padding: 0 !important; border: 0 !important; }
#app .m-pop > header::before, #app .m-pop > header::after,
#app .m-pop > section ul::before, #app .m-pop > section ul::after,
#app .m-pop > section li::before, #app .m-pop > section li::after,
#app .m-pop > footer::before, #app .m-pop > footer::after { display: none !important; }
#app .m-pop > section li > a, #app .m-pop > section li > label {
  display: flex !important;
  align-items: center;
  gap: 8px;
  height: 40px !important;
  margin: 0 !important;
  padding: 0 10px !important;
  border: 0 !important;
  border-radius: 8px;
  width: auto !important;
  box-sizing: border-box;
  font-size: 14px !important;
  line-height: 40px !important;
  color: var(--mp-name) !important;
  text-decoration: none;
  cursor: pointer;
}
#app .m-pop > section li > a:hover, #app .m-pop > section li > label:hover { background: var(--mp-seg) !important; }
#app .m-pop > section li > a .m-font-plus { font-size: 13px !important; color: var(--mp-button-icon) !important; }
/* The checkbox: a round check at the end of the row */
#app .m-pop .m-checkbox input { display: none !important; }
#app .m-pop .m-checkbox span {
  position: static !important;
  flex: none;
  display: flex !important;
  align-items: center;
  justify-content: center;
  width: 20px !important;
  height: 20px !important;
  margin: 0 0 0 auto !important;
  border: 0 !important;
  border-radius: 50% !important;
  background: transparent !important;
  box-shadow: inset 0 0 0 1px var(--mp-button-line);
  transform: none !important;
}
#app .m-pop .m-checkbox span i { font-size: 12px !important; line-height: 1 !important; color: transparent !important; }
#app .m-pop .m-checkbox input:checked + span { background: var(--mp-accent) !important; box-shadow: none; }
#app .m-pop .m-checkbox input:checked + span i { display: block !important; color: #fff !important; }
#app .m-pop > footer {
  display: flex !important;
  gap: 8px;
  height: auto !important;
  margin: 0 !important;
  padding: 4px 16px 16px !important;
  border: 0 !important;
  background: transparent !important;
}
#app .m-pop > footer .m-box-col { flex: 1 1 0; margin: 0 !important; padding: 0 !important; border: 0 !important; }
#app .m-pop > footer .m-btn {
  display: block !important;
  width: auto !important;
  height: 36px !important;
  margin: 0 !important;
  padding: 0 !important;
  border: 0 !important;
  border-radius: 18px !important;
  box-shadow: none !important;
  background: var(--mp-seg-sel) !important;
  color: var(--mp-name) !important;
  font-size: 14px !important;
  line-height: 36px !important;
  text-align: center !important;
}
#app .m-pop > footer .m-btn::before, #app .m-pop > footer .m-btn::after { display: none !important; }
#app .m-pop > footer .m-btn-text-orange { background: var(--mp-accent) !important; color: #fff !important; font-weight: 600 !important; }
#app .weibo-top .m-followBtn h4 {
  margin: 0 !important;
  height: auto !important;
  font-size: 13px !important;
  font-weight: 400 !important;
  line-height: 28px !important;
  color: inherit !important;
}

/* Verified badge: 20pt, 4 past the avatar's right edge and 2 below it */
#app .m-img-box > .m-icon {
  position: absolute !important;
  top: auto !important;
  left: auto !important;
  right: -4px !important;
  bottom: -2px !important;
  width: 20px !important;
  height: 20px !important;
  border-radius: 50%;
  background: var(--mp-cell) !important;
  transform: none !important;
}
#app .m-img-box > .m-icon::after {
  content: "";
  position: absolute;
  inset: 1.5px;
  background: var(--mp-badge-orange);
  -webkit-mask: url("${ICONS.badge_check}") center / contain no-repeat;
  mask: url("${ICONS.badge_check}") center / contain no-repeat;
}
#app .m-img-box > .m-icon-bluev::after { background: var(--mp-badge-blue); }

/* Body: from x70, 10 from the right */
#app .card9 > .weibo-main { padding: 0 10px 0 70px !important; margin: 0 !important; }
#app .weibo-og { padding: 0 !important; }
#app .weibo-text, #app .lite-page-list .m-text-box > h3, #app .lite-msg .m-text-box > h3 {
  color: var(--mp-text) !important;
  font-size: 16px !important;
  font-weight: 400 !important;
  line-height: 25.6px !important;
}
#app .weibo-text a, #app .weibo-text a .surl-text,
#app .lite-page-list h3 a, #app .lite-msg h3 a { color: var(--mp-link) !important; }
#app .weibo-text a.mp-tag, #app .weibo-text a.mp-tag .surl-text { color: var(--mp-tag) !important; }
#app .weibo-text .url-icon img, #app .lite-page-list .url-icon img { width: 1.15em !important; height: 1.15em !important; vertical-align: -0.2em; }

/* Quoted status: starts 10 left of the text, flush right, radius 8, inset 5 top / 10 bottom */
#app .weibo-rp {
  background: var(--mp-quote-bg) !important;
  border-radius: 8px 0 0 8px !important;
  margin: 5px -10px 0 -10px !important;
  padding: 5px 10px 10px 10px !important;
}
#app .weibo-rp .weibo-text { color: var(--mp-quote-text) !important; }

/* Pictures: up to 300 wide, 98pt tiles, 2pt gaps, radius 6 on the group */
#app .weibo-media-wraps, #app .weibo-main .f-media { margin: 10px 0 0 !important; padding: 0 !important; }
#app .weibo-media-wraps .m-auto-list {
  display: grid !important;
  grid-template-columns: repeat(3, 98px);
  gap: 2px;
  width: max-content;
  margin: 0 !important;
  padding: 0 !important;
  border-radius: 6px;
  overflow: hidden;
}
#app .weibo-media-wraps .m-auto-list:has(> li:nth-child(2):last-child),
#app .weibo-media-wraps .m-auto-list:has(> li:nth-child(4):last-child) { grid-template-columns: repeat(2, 149px); }
#app .weibo-media-wraps .m-auto-list > li {
  width: auto !important;
  height: auto !important;
  margin: 0 !important;
  padding: 0 !important;
  float: none !important;
}
#app .weibo-media-wraps .m-auto-list > li .m-img-box {
  width: 100% !important;
  height: auto !important;
  aspect-ratio: 1;
  padding: 0 !important;
  border-radius: 0 !important;
  overflow: hidden !important;
}
#app .weibo-media-wraps .m-auto-list > li .m-img-box img {
  position: absolute !important;
  inset: 0;
  width: 100% !important;
  height: 100% !important;
  object-fit: cover;
  border-radius: 0 !important;
}
#app .weibo-media-wraps .m-auto-list:has(> li:only-child) { grid-template-columns: minmax(0, 300px); }
#app .weibo-media-wraps .m-auto-list > li:only-child .m-img-box { width: 300px !important; aspect-ratio: 4 / 3; }
#app .feed-mark { border-radius: 4px; background: rgba(0, 0, 0, 0.45) !important; font-size: 10px !important; z-index: 1; }
#app .card-video, #app .weibo-main .card4, #app .weibo-main .m-panel { border-radius: 6px !important; overflow: hidden; max-width: 300px; }

/* Actions: 32pt band + 10 bottom; 17x16 icons, 7 to the label, 74pt pitch from x70 */
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) {
  display: flex !important;
  align-items: center;
  justify-content: flex-start !important;
  height: 32px !important;
  margin: 0 0 0 70px !important;
  padding: 0 0 10px !important;
  border: 0 !important;
  background: transparent !important;
}
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box)::before, #app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box)::after { display: none !important; }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn {
  flex: none !important;
  width: 74px !important;
  height: 32px !important;
  margin: 0 !important;
  justify-content: flex-start !important;
  color: var(--mp-action) !important;
  opacity: 0.6;
  cursor: pointer;
  transition: opacity 0.15s;
}
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn:hover { opacity: 1; }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn i {
  flex: none;
  width: 18px !important;
  height: 18px !important;
  font-size: 0 !important;
  background: currentColor;
  -webkit-mask: var(--mp-glyph) center / contain no-repeat;
  mask: var(--mp-glyph) center / contain no-repeat;
}
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn i::before { display: none !important; }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) :is(.lite-iconf-report, .m-font-forward) { --mp-glyph: url("${ICONS.act_reposts}"); }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) :is(.lite-iconf-comments, .m-font-comment) { --mp-glyph: url("${ICONS.act_comments}"); }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) :is(.lite-iconf-like, .lite-iconf-liked, .m-font-like, .m-font-liked, [class*="m-icon-like"]) { --mp-glyph: url("${ICONS.act_likes}"); }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn h4 {
  margin: 0 0 0 7px !important;
  font-size: 14px !important;
  font-weight: 400 !important;
  line-height: 16px !important;
  color: inherit !important;
}
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn.mp-zero h4 { font-size: 11px !important; }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn:has(.lite-iconf-liked), #app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) .m-diy-btn.mp-on { color: var(--mp-accent) !important; opacity: 1; }
#app :is(.f-footer-ctrl, .card9 footer.m-ctrl-box) aside {
  margin-left: auto !important;
  margin-right: 10px !important;
  color: var(--mp-action) !important;
  opacity: 0.6;
}

/* ---------- Comments and inbox: same layout as statuses ---------- */
#app .lite-page-list, #app .lite-msg {
  position: relative;
  margin: 0 !important;
  border: 0 !important;
  background: var(--mp-cell) !important;
}
#app .lite-page-list::after, #app .lite-msg::after {
  content: "";
  position: absolute;
  left: 70px;
  right: 0;
  bottom: 0;
  border-bottom: 0.5px solid var(--mp-line);
}
#app .lite-page-list .card-wrap, #app .lite-msg .card-wrap { margin: 0 !important; padding: 0 !important; background: transparent !important; }
#app .lite-page-list .card-main, #app .lite-msg .card-main {
  position: relative;
  padding: 10px 10px 10px 70px !important;
  margin: 0 !important;
  border: 0 !important;
}
#app .lite-page-list .card-main > .m-box > .m-img-box, #app .lite-msg .card-main > .m-box > .m-img-box {
  position: absolute !important;
  left: 10px;
  top: 10px;
  margin: 0 !important;
}
/* Likes tab: name-only rows become compact user rows (36pt avatar) */
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main { padding: 10px 10px 10px 56px !important; min-height: 36px; }
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main > .m-box > .m-img-box,
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main > .m-box > .m-img-box > img,
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main > .m-box > a:has(> .m-img-box),
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main > .m-box > a > .m-img-box,
#app .lite-page-list:not(:has(.m-text-box > h3)) .card-main > .m-box > a > .m-img-box > img { width: 36px !important; height: 36px !important; }
#app .lite-page-list:not(:has(.m-text-box > h3)) .m-text-box > .m-box-center-a,
#app .lite-page-list:not(:has(.m-text-box > h3)) .m-text-box h4 { height: 36px !important; line-height: 36px !important; }
#app .lite-page-list:not(:has(.m-text-box > h3))::after { left: 56px; }
/* Reposts tab: the avatar sits inside a link */
#app .lite-page-list .card-main > .m-box > a:has(> .m-img-box) { position: absolute !important; left: 10px; top: 10px; width: 50px !important; height: 50px !important; }
#app .lite-page-list .card-main > .m-box > a > .m-img-box, #app .lite-page-list .card-main > .m-box > a > .m-img-box > img {
  width: 50px !important;
  height: 50px !important;
  margin: 0 !important;
  border-radius: 50% !important;
}
#app .lite-page-list .lite-line, #app .lite-msg .lite-line { display: flex !important; flex-direction: column; padding: 0 !important; margin: 0 !important; border: 0 !important; }
#app .lite-page-list .lite-line > .m-box, #app .lite-page-list .lite-line > .m-box > .m-box-col, #app .lite-page-list .m-text-box,
#app .lite-msg .lite-line > .m-box, #app .lite-msg .lite-line > .m-box > .m-box-col, #app .lite-msg .m-text-box { display: contents !important; }
#app .lite-page-list .m-text-box > .m-box-center-a, #app .lite-msg .m-text-box > h4 { order: 1; height: 22px; margin: 0 !important; padding: 0 !important; }
#app .lite-page-list .lite-bot, #app .lite-msg .lite-time { order: 2; margin: -2px 0 0 !important; padding: 0 !important; height: 15px; }
#app .lite-page-list .m-text-box > h3, #app .lite-msg .m-text-box > h3 { order: 3; margin: 1px 0 0 !important; }
#app .lite-page-list .comment-con-img { order: 4; margin-top: 10px; }
#app .lite-page-list .comment-con-img img { max-width: 300px; border-radius: 6px; }
#app .lite-page-list .cmt-sub-txt, #app .lite-msg .box-right { order: 5; }
#app .lite-page-list .lite-bot .time { padding: 0 !important; }
#app .lite-page-list .lite-bot aside {
  position: absolute;
  top: 10px;
  right: 10px;
  color: var(--mp-action) !important;
  opacity: 0.6;
  font-size: 12px !important;
}
#app .lite-page-list .lite-bot aside:last-child { right: 40px; }
#app .lite-page-list .lite-bot aside i {
  display: inline-block;
  vertical-align: -2px;
  width: 17px;
  height: 16px;
  font-size: 0 !important;
  background: currentColor;
  -webkit-mask: url("${ICONS.act_likes}") center / contain no-repeat;
  mask: url("${ICONS.act_likes}") center / contain no-repeat;
}
#app .lite-page-list .lite-bot aside i.lite-iconf-comments {
  width: 17px;
  height: 17px;
  -webkit-mask-image: url("${ICONS.reply}");
  mask-image: url("${ICONS.reply}");
}
#app .lite-page-list .lite-bot aside i::before { display: none !important; }
#app .lite-page-list .lite-bot aside em { font-style: normal; font-size: 11px; margin-left: 3px; }

/* Replies box: text inset 10/6, 4 between replies, 10 below */
#app .lite-page-list .cmt-sub-txt, #app .lite-msg .box-right {
  margin: 10px 0 0 !important;
  padding: 6px 10px !important;
  border-radius: 8px !important;
  background: var(--mp-quote-bg) !important;
  width: auto !important;
  max-width: none !important;
}
#app .lite-page-list .cmt-sub-txt p {
  margin: 0 0 4px !important;
  font-size: 15px !important;
  line-height: 24px !important;
  color: var(--mp-quote-text) !important;
}
#app .lite-page-list .cmt-sub-txt p:last-child { margin-bottom: 0 !important; }
#app .lite-page-list .cmt-sub-txt p > a:first-child { color: var(--mp-link) !important; }
#app .lite-page-list .cmt-sub-txt p > a:first-child::before { content: "@"; }
#app .lite-page-list .cmt-sub-txt .lite-more, #app .lite-page-list .cmt-sub-txt > div { color: var(--mp-link) !important; font-size: 15px !important; }
#app .lite-msg .box-right h4 { color: var(--mp-quote-text) !important; font-size: 15px !important; line-height: 24px !important; height: auto !important; max-height: 72px; }
#app .lite-msg .m-text-box > h4 span { color: inherit !important; }
#app .lite-msg .box-right:has(> h4:empty:only-child) { display: none !important; }

/* ---------- Older page bar (/p/index lists: 返回 | title): same 50pt toolbar ---------- */
#app .m-top-bar {
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  max-width: none !important;
  height: 50px !important;
  margin: 0 !important;
  z-index: 1000 !important;
  background: var(--mp-bar) !important;
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px);
  border: 0 !important;
  box-shadow: none !important;
}
#app .m-top-bar::before, #app .m-top-bar::after, #app .m-top-bar *::before { border: 0 !important; }
#app .m-top-bar .nav-box, #app .m-top-bar .nav-main { height: 50px !important; top: 0 !important; }
#app .m-top-bar .nav-main { left: 0 !important; right: 0 !important; width: auto !important; display: flex !important; align-items: center; justify-content: center; }
#app .m-top-bar .nav-main h3 { font-size: 14px !important; font-weight: 700 !important; line-height: 50px !important; color: var(--mp-title) !important; }
#app .m-top-bar .nav-left {
  top: 9px !important;
  left: 9px !important;
  width: 32px !important;
  height: 32px !important;
  z-index: 1;
  border-radius: 50%;
  background: var(--mp-button) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 1px 2px rgba(0, 0, 0, 0.04);
  font-size: 0 !important;
  overflow: hidden;
  cursor: pointer;
}
#app .m-top-bar .nav-left .nav-ctrl { width: 32px !important; height: 32px !important; font-size: 0 !important; }
#app .m-top-bar .nav-left i { display: none !important; }
#app .m-top-bar .nav-left::after {
  content: "";
  position: absolute;
  inset: 0;
  margin: auto;
  width: 18px;
  height: 18px;
  background: var(--mp-button-icon);
  -webkit-mask: url("${ICONS.back}") center / contain no-repeat;
  mask: url("${ICONS.back}") center / contain no-repeat;
  pointer-events: none;
}

/* ---------- Search and topic pages ---------- */
#app .ntop-nav { height: 50px !important; background: var(--mp-bar) !important; border: 0 !important; }
#app .ntop-nav .m-box-center-a, #app .ntop-nav .nt-box-col { height: 50px !important; }
#app .ntop-nav .nt-box-col { padding: 0 9px !important; gap: 8px; }
#app .ntop-nav .nt-left {
  flex: none;
  width: 32px !important;
  height: 32px !important;
  border-radius: 50%;
  background: var(--mp-button) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 1px 2px rgba(0, 0, 0, 0.04);
  display: flex !important;
  align-items: center;
  justify-content: center;
  font-size: 0 !important;
  cursor: pointer;
}
#app .ntop-nav .nt-left > * { display: none !important; }
#app .ntop-nav .nt-left::after {
  content: "";
  width: 18px;
  height: 18px;
  background: var(--mp-button-icon);
  -webkit-mask: url("${ICONS.back}") center / contain no-repeat;
  mask: url("${ICONS.back}") center / contain no-repeat;
}
#app .ntop-nav .nt-sbox, #app .ntop-nav .nt-sbox * { background-color: transparent !important; }
#app .ntop-nav .nt-sbox > * {
  height: 32px !important;
  border-radius: 16px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
}
#app .ntop-nav input { font-size: 14px !important; color: var(--mp-name) !important; }
#app .m-top-nav { width: 100% !important; max-width: none !important; background: var(--mp-cell) !important; border-bottom: 0.5px solid var(--mp-line) !important; }
#app .m-top-nav * { background-color: transparent !important; }
#app .m-top-nav li, #app .m-top-nav .nav-item, #app .m-top-nav span { font-size: 14px !important; color: var(--mp-meta) !important; }
#app .m-top-nav .cur, #app .m-top-nav .cur * { color: var(--mp-name) !important; font-weight: 600 !important; }
#app .m-top-nav .cur em, #app .m-top-nav .cur i, #app .m-top-nav span::after { background: var(--mp-name) !important; }
#app .m-tab-bar {
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  max-width: none !important;
  margin: 0 !important;
  background: var(--mp-bar) !important;
  -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px);
  border-top: 0.5px solid var(--mp-line) !important;
  box-shadow: none !important;
}
#app .m-tab-bar * { background-color: transparent !important; }
#app .m-tab-bar .m-line-gradient { display: none !important; }
#app .m-tab-bar .m-diy-btn { font-size: 13px !important; color: var(--mp-button-icon) !important; }
#app .card11 .card-title { font-size: 13px !important; font-weight: 600 !important; color: var(--mp-meta) !important; background: transparent !important; }

/* ---------- Profile: cover, 64pt ringed avatar over its edge, counts row ---------- */
#app .prf-topbar {
  position: fixed !important;
  top: 0 !important;
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  height: 50px !important;
  margin: 0 !important;
  z-index: 1000 !important;
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
}
#app .prf-topbar .nav-left { left: 9px !important; --mp-glyph: url("${ICONS.back}"); }
#app .prf-topbar .nav-left::after { width: 18px; height: 18px; }
#app .prf-topbar .nav-right { right: 9px !important; left: auto !important; --mp-glyph: url("${MORE}"); }
#app .prf-topbar .nav-right::after { width: 18px; height: 18px; }
#app .profile-header {
  padding: 0 !important;
  background: var(--mp-cell) var(--mp-cover, linear-gradient(var(--mp-seg-sel), var(--mp-seg))) top / 100% 138px no-repeat !important;
  border: 0 !important;
}
#app .profile-header::before, #app .profile-header::after { display: none !important; }
#app .prf-detail {
  align-items: flex-start !important;
  padding: 115px 13px 0 !important;
  margin: 0 !important;
  background: transparent !important;
}
#app .prf-detail > .m-img-box, #app .prf-detail > .m-img-box img {
  width: 64px !important;
  height: 64px !important;
  border-radius: 50% !important;
}
#app .prf-detail > .m-img-box { flex: none; margin: 0 8px 0 0 !important; box-shadow: 0 0 0 3px var(--mp-cell); }
#app .prf-detail .m-text-box { padding: 28px 0 0 !important; margin: 0 !important; }
#app .prf-detail h3 {
  color: var(--mp-name) !important;
  font-size: 17px !important;
  font-weight: 700 !important;
  line-height: 22px !important;
  height: auto !important;
}
#app .prf-detail h3 .lite-iconf { display: none !important; }
#app .prf-detail h4 {
  margin: 2px 0 0 !important;
  color: var(--mp-meta) !important;
  font-size: 13px !important;
  line-height: 18px !important;
}
#app .prf-handle {
  display: flex !important;
  align-items: center;
  padding: 12px 13px 14px !important;
  margin: 0 !important;
  border: 0 !important;
  background: transparent !important;
}
#app .prf-handle > .m-box-center-a { display: flex !important; gap: 14px; }
#app .prf-num {
  display: inline-flex !important;
  align-items: baseline;
  gap: 4px;
  width: auto !important;
  margin: 0 !important;
  font-size: 14px !important;
}
#app .prf-num i { font-style: normal; color: var(--mp-name) !important; font-size: 14px !important; line-height: 20px !important; }
#app .prf-num b { font-weight: 400 !important; color: var(--mp-meta) !important; font-size: 14px !important; line-height: 20px !important; }
#app .prf-num[data-mp="posts"] { display: none !important; }
#app .prf-num[data-mp="followers"] { order: -1; }
#app .prf-handle .dm-btn {
  flex: none;
  width: 28px !important;
  height: 28px !important;
  margin: 0 0 0 8px !important;
  border: 0 !important;
  border-radius: 50% !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  display: flex !important;
  align-items: center;
  justify-content: center;
  color: var(--mp-button-icon) !important;
  cursor: pointer;
}
#app .prf-handle .dm-btn::before, #app .prf-handle .dm-btn::after { border: 0 !important; }
#app .prf-handle .dm-btn i { font-size: 16px !important; line-height: 1 !important; color: inherit !important; }
#app .prf-handle .m-btn i { font-size: 11px !important; line-height: 1 !important; height: auto !important; margin: 0 !important; color: inherit !important; }
#app .prf-handle .m-btn i::before { position: static !important; display: block; transform: none !important; margin: 0 !important; }
/* "置顶" (pinned) above a profile's first post: a small section label */
#app div.m-ctrl-box:has(> .m-diy-btn:only-child) { height: auto !important; padding: 12px 10px 4px 70px !important; border: 0 !important; background: transparent !important; }
#app div.m-ctrl-box:has(> .m-diy-btn:only-child)::before, #app div.m-ctrl-box:has(> .m-diy-btn:only-child)::after { display: none !important; }
#app div.m-ctrl-box:has(> .m-diy-btn:only-child) .m-diy-btn { justify-content: flex-start !important; height: auto !important; }
#app div.m-ctrl-box:has(> .m-diy-btn:only-child) h4 { margin: 0 !important; font-size: 12px !important; font-weight: 600 !important; line-height: 16px !important; color: var(--mp-meta) !important; }
#app .prf-handle .bar-btn { flex: none !important; width: auto !important; margin-left: auto !important; }
#app .prf-handle .m-btn {
  height: 28px !important;
  line-height: 28px !important;
  padding: 0 14px !important;
  border: 0 !important;
  border-radius: 14px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  color: var(--mp-button-icon) !important;
  font-size: 13px !important;
  display: inline-flex !important;
  align-items: center;
  gap: 3px;
  width: auto !important;
}
#app .prf-handle .m-btn::before, #app .prf-handle .m-btn::after { display: none !important; }
#app .lite-reads { display: none !important; }
#app .lite-btn-more { color: var(--mp-meta) !important; font-size: 13px !important; background: transparent !important; border: 0 !important; }
#app .icon_edit {
  left: calc(var(--mp-colx) + var(--mp-col) - 60px) !important;
  right: auto !important;
  width: 44px !important;
  height: 44px !important;
  border-radius: 50% !important;
  background: var(--mp-button) none !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 2px 8px rgba(0, 0, 0, 0.1) !important;
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
}
#app .icon_edit > * { display: none !important; }
#app .icon_edit::after {
  content: "";
  position: absolute;
  inset: 0;
  margin: auto;
  width: 19px;
  height: 19px;
  background: var(--mp-button-icon);
  -webkit-mask: url("${COMPOSE}") center / contain no-repeat;
  mask: url("${COMPOSE}") center / contain no-repeat;
}

/* ---------- Compose: Weibo's page, in the column, sized to its content ---------- */
#app > div.m-wbox:first-child { background: var(--mp-page) !important; }
#app .m-main.m-box-model {
  top: 0 !important;
  bottom: auto !important;
  left: var(--mp-colx) !important;
  right: auto !important;
  width: var(--mp-col) !important;
  height: auto !important;
  max-height: 100vh;
  border-radius: 0 0 12px 12px;
  overflow: hidden;
  background: var(--mp-cell) !important;
  box-shadow: 0 0 0 0.5px var(--mp-button-line), 0 8px 24px rgba(0, 0, 0, 0.08);
}
#app .m-main > main.m-reles-con { flex: none !important; height: auto !important; min-height: 160px; }
#app .m-main .m-lim-width { width: 100% !important; max-width: none !important; margin: 0 !important; }
/* Toolbar: round back | avatar | Send pill */
#app .m-reles-top {
  height: 50px !important;
  padding: 0 9px !important;
  box-sizing: border-box;
  background: var(--mp-bar) !important;
  border: 0 !important;
  box-shadow: none !important;
}
#app .m-reles-top::before, #app .m-reles-top::after { display: none !important; }
#app .m-reles-top > div { padding: 0 !important; margin: 0 !important; }
#app .m-reles-top > div:first-child > i {
  width: 32px !important;
  height: 32px !important;
  border-radius: 50%;
  background: var(--mp-button);
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 1px 2px rgba(0, 0, 0, 0.04);
  display: flex !important;
  align-items: center;
  justify-content: center;
  font-size: 0 !important;
  cursor: pointer;
}
#app .m-reles-top > div:first-child > i::before { display: none !important; }
#app .m-reles-top > div:first-child > i::after {
  content: "";
  width: 18px;
  height: 18px;
  background: var(--mp-button-icon);
  -webkit-mask: url("${ICONS.back}") center / contain no-repeat;
  mask: url("${ICONS.back}") center / contain no-repeat;
}
#app .m-reles-top .m-ruser-img { width: 32px !important; height: 32px !important; border-radius: 50% !important; }
#app .m-reles-top .m-send-btn {
  height: 28px !important;
  line-height: 28px !important;
  padding: 0 14px !important;
  border-radius: 14px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  color: var(--mp-name) !important;
  font-size: 13px !important;
  font-weight: 600 !important;
}
#app .m-reles-top .m-send-btn.disabled { color: var(--mp-meta) !important; font-weight: 400 !important; }
/* Text */
#app .m-reles-con { background: transparent !important; padding: 12px 10px 0 !important; box-sizing: border-box; }
#app .m-reles-con * { background-color: transparent !important; }
#app .m-reles-con textarea {
  padding: 0 !important;
  font-size: 16px !important;
  line-height: 25.6px !important;
  color: var(--mp-text) !important;
  caret-color: var(--mp-accent);
}
#app .m-reles-con textarea::placeholder { color: var(--mp-meta); }
#app .m-reles-con .image-list img { border-radius: 6px; }
/* Bottom bar: visibility pill, then round picture / emoji buttons */
#app .m-main > footer { background: var(--mp-bar) !important; border-top: 0.5px solid var(--mp-line) !important; }
#app .m-main > footer::before, #app .m-main > footer::after,
#app .m-main .composer-footer::before, #app .m-main .composer-footer::after { display: none !important; }
#app .m-main .m-fcb-col { padding: 8px 10px 0 !important; height: auto !important; background: transparent !important; border: 0 !important; }
#app .m-main .visible {
  height: 28px !important;
  padding: 0 12px !important;
  border: 0 !important;
  border-radius: 14px !important;
  background: var(--mp-seg) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line);
  display: flex !important;
  align-items: center;
}
#app .m-main .visible::before, #app .m-main .visible::after { display: none !important; }
#app .m-main .visible h4 { margin: 0 !important; font-size: 13px !important; line-height: 28px !important; color: var(--mp-button-icon) !important; }
#app .m-main .composer-footer, #app .m-main .composer-footer-box { background: transparent !important; border: 0 !important; height: 52px !important; }
#app .m-main .composer-footer-box { padding: 0 10px !important; gap: 8px; justify-content: flex-start !important; }
#app .m-main .composer-footer-box > .m-iconf-col {
  flex: none !important;
  width: 32px !important;
  height: 32px !important;
  border-radius: 50%;
  background: var(--mp-button) !important;
  box-shadow: inset 0 0 0 0.5px var(--mp-button-line), 0 1px 2px rgba(0, 0, 0, 0.04);
  color: var(--mp-button-icon) !important;
  cursor: pointer;
}
#app .m-main .composer-footer-box > .m-iconf-col h4 { font-size: 17px !important; width: auto !important; height: auto !important; margin: 0 !important; color: inherit !important; }
#app .m-main .composer-footer-box > div:not(.m-iconf-col) { flex: 1 !important; }
#app .m-main .m-reles-fnum { font-size: 12px !important; color: var(--mp-meta) !important; }

/* Misc */
/* Weibo's floating refresh button: not needed */
#app .refresh-btn { display: none !important; }
#app .m-tips, #app .m-tips .main-link, #app .comment-content .empty { color: var(--mp-meta) !important; background: transparent !important; font-size: 13px !important; }
`;

  function addStyle() {
    if (document.getElementById('weibo-clean-skin')) return;
    const style = document.createElement('style');
    style.id = 'weibo-clean-skin';
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  // ---------- ☰ menu: the main sections, opened from the timeline's ☰ ----------

  const SECTIONS = [
    ['timeline', NAV('Timeline', '首页'), '/'],
    ['mentions', NAV('Mentions', '@我的'), '/message/atme'],
    ['comments', NAV('Comments', '评论'), '/message/cmts'],
    ['likes', NAV('Likes', '赞'), '/message/like'],
    ['star', NAV('Favorites', '收藏'), '/p/index?containerid=230259'],
    ['profile', NAV('Profile', '我'), '/profile/'],
    ['search', NAV('Search', '搜索'), '/search'],
  ];

  function currentSection() {
    const p = location.pathname;
    if (location.search.includes('230259')) return 'star';
    if (p.startsWith('/message/atme')) return 'mentions';
    if (p.startsWith('/message/cmts')) return 'comments';
    if (p.startsWith('/message/like')) return 'likes';
    if (p.startsWith('/profile')) return 'profile';
    if (p.startsWith('/search')) return 'search';
    if (p === '/' || p === '/beta') return 'timeline';
    return null;
  }

  let menu = null;
  let channelClick = false;

  function closeMenu() {
    if (menu) menu.hidden = true;
  }

  function openMenu() {
    const key = currentSection();
    for (const a of menu.querySelectorAll('[data-key]')) a.classList.toggle('mp-sel', a.dataset.key === key);
    menu.hidden = false;
  }

  function buildMenu() {
    if (menu) return;
    menu = document.createElement('div');
    menu.id = 'mp-menu';
    menu.hidden = true;
    menu.innerHTML =
      `<a class="mp-me" href="/profile/"><span class="mp-avatar"></span><span class="mp-name">${NAV('Profile', '我')}</span></a><hr>` +
      SECTIONS.map(([key, title, href]) =>
        `<a data-key="${key}" href="${href}"><i style="--mp-icon: url('${ICONS[key]}')"></i>${title}</a>`).join('');
    menu.addEventListener('click', (e) => {
      const a = e.target.closest('a');
      if (!a) return;
      e.preventDefault();
      closeMenu();
      // A full load: Weibo's inbox pages only fetch their lists on a fresh load.
      const href = a.getAttribute('href');
      if (location.pathname + location.search !== href) location.assign(href);
    });
    document.body.appendChild(menu);

    document.addEventListener('click', (e) => {
      if (!channelClick && e.target.closest && e.target.closest('.main-top .nav-plus')) {
        e.preventDefault();
        e.stopPropagation();
        if (menu.hidden) openMenu();
        else closeMenu();
        return;
      }
      if (!menu.hidden && !menu.contains(e.target)) closeMenu();
    }, true);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeMenu();
      if (e.key === 'Escape') closeComposer();
    });

    fetch('/api/config', { credentials: 'include' })
      .then((r) => r.json())
      .then((j) => {
        const uid = (j.data && j.data.uid) || '';
        if (!uid) return null;
        for (const a of menu.querySelectorAll('.mp-me, [data-key="profile"]')) a.href = '/profile/' + uid;
        return fetch('/api/container/getIndex?type=uid&value=' + uid, { credentials: 'include' }).then((r) => r.json());
      })
      .then((j) => {
        const info = j && j.data && j.data.userInfo;
        if (!info) return;
        menu.querySelector('.mp-avatar').style.backgroundImage = `url("${info.avatar_hd || info.profile_image_url}")`;
        menu.querySelector('.mp-name').textContent = info.screen_name;
      })
      .catch(() => {});
  }

  // ---------- Post: Weibo's composer in a sheet over the timeline ----------

  let sheet = null;
  let posted = false;

  function closeComposer() {
    if (!sheet) return;
    const s = sheet;
    sheet = null;
    s.classList.remove('mp-open');
    setTimeout(() => s.remove(), 300);
    // The new post shows once the timeline reloads its list.
    if (posted) {
      const refresh = document.querySelector('.refresh-btn');
      if (refresh) refresh.click();
    }
  }

  function openComposer() {
    if (sheet) return;
    closeMenu();
    posted = false;
    sheet = document.createElement('div');
    sheet.id = 'mp-compose';
    sheet.innerHTML = '<div class="mp-scrim"></div><div class="mp-sheet"><iframe src="/compose/"></iframe></div>';
    sheet.querySelector('.mp-scrim').addEventListener('click', closeComposer);
    const frame = sheet.querySelector('iframe');
    frame.addEventListener('load', () => tameComposer(frame));
    document.body.appendChild(sheet);
    const s = sheet;
    requestAnimationFrame(() => requestAnimationFrame(() => s.classList.add('mp-open')));
  }

  // The composer leaves by going back or routing home. Inside the sheet either one closes it,
  // so the timeline underneath never navigates.
  function tameComposer(frame) {
    const win = frame.contentWindow;
    if (!win) return;
    if (!win.location.pathname.startsWith('/compose')) return closeComposer();
    const h = win.history;
    h.back = h.go = closeComposer;
    for (const name of ['pushState', 'replaceState']) {
      const original = h[name].bind(h);
      h[name] = (state, title, url) => {
        if (url != null && !new URL(url, win.location.href).pathname.startsWith('/compose')) return closeComposer();
        return original(state, title, url);
      };
    }
    win.document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeComposer();
    });
    win.document.addEventListener('click', (e) => {
      if (!e.target.closest) return;
      if (e.target.closest('.m-reles-top > div:first-child')) {
        e.preventDefault();
        e.stopPropagation();
        closeComposer();
      } else if (e.target.closest('.m-send-btn:not(.disabled)')) {
        posted = true;
      }
    }, true);
    fitComposer(frame);
    const area = win.document.querySelector('textarea');
    if (area) area.focus();
  }

  // The sheet is as tall as the composer, up to three quarters of the window.
  function fitComposer(frame, tries = 0) {
    const doc = frame.contentDocument;
    const tools = doc && doc.querySelector('.m-reles-top');
    if (!tools) {
      if (tries < 60 && sheet) setTimeout(() => fitComposer(frame, tries + 1), 50);
      return;
    }
    const style = doc.createElement('style');
    style.textContent = 'html, body, #app { background: var(--mp-cell) !important; min-height: 0 !important; }';
    doc.head.appendChild(style);
    const main = tools.closest('.m-main') || doc.getElementById('app');
    const height = Math.ceil(main.getBoundingClientRect().bottom);
    if (height > 100) frame.parentElement.style.height = `min(${height}px, 75vh)`;
  }

  function hookComposer() {
    document.addEventListener('click', (e) => {
      if (!e.target.closest || !e.target.closest('.main-top .lite-iconf-releas')) return;
      e.preventDefault();
      e.stopPropagation();
      openComposer();
    }, true);
  }

  // ---------- Text: what CSS can't reach ----------

  // Short English timestamps: "32 secs", "2 mins", "3 hrs". Chinese keeps Weibo's.
  function shortTime(s) {
    if (ZH) return null;
    const t = s.trim();
    let m;
    if (t === '刚刚') return 'now';
    if ((m = t.match(/^(\d+)秒前$/))) return m[1] + (m[1] === '1' ? ' sec' : ' secs');
    if ((m = t.match(/^(\d+)分钟前$/))) return m[1] + (m[1] === '1' ? ' min' : ' mins');
    if ((m = t.match(/^(\d+)小时前$/))) return m[1] + (m[1] === '1' ? ' hr' : ' hrs');
    if ((m = t.match(/^昨天\s*(.*)$/))) return 'Yesterday ' + m[1];
    return null;
  }

  const ACTION_TITLES = L(['Repost', 'Reply', 'Like'], ['转发', '评论', '赞']);
  const TAB_TITLES = L({ 转发: 'Reposts', 评论: 'Comments', 赞: 'Likes' }, {});

  function decorate(root) {
    root.querySelectorAll('.weibo-text a:not(.mp-seen)').forEach((a) => {
      a.classList.add('mp-seen');
      if (/^\s*#.*#\s*$/.test(a.textContent)) a.classList.add('mp-tag');
    });

    root.querySelectorAll('.weibo-top h4 .time').forEach((el) => {
      const t = shortTime(el.textContent);
      if (t) el.textContent = t;
    });
    root.querySelectorAll('.weibo-top h4 .from').forEach((from) => {
      if (/^\s*来自/.test(from.textContent)) from.textContent = from.textContent.replace(/^\s*来自\s*/, '');
      from.classList.toggle('mp-dot', !!from.textContent.trim());
    });
    // Comments keep the region: "9 mins • 来自 广西"
    root.querySelectorAll('.lite-page-list .lite-bot .time, .lite-msg .lite-time').forEach((el) => {
      if (el.textContent === el.dataset.mpOut) return;
      const raw = el.textContent.trim().replace(/\s+/g, ' ');
      const m = raw.match(/^(.*?)\s*(来自.*)?$/);
      const t = shortTime(m[1]) || m[1];
      el.textContent = el.dataset.mpOut = m[2] ? t + ' • ' + m[2].replace(/^来自\s*/, '来自 ') : t;
    });

    root.querySelectorAll('.f-footer-ctrl:not(.mp-detail-actions), .card9 footer.m-ctrl-box').forEach((footer) => {
      footer.querySelectorAll('.m-diy-btn').forEach((btn, i) => {
        const h4 = btn.querySelector('h4');
        if (!h4) return;
        const v = h4.textContent.trim();
        const isCount = /\d/.test(v);
        btn.classList.toggle('mp-zero', !isCount);
        if (!isCount && v !== ACTION_TITLES[i]) h4.textContent = ACTION_TITLES[i];
      });
    });

    root.querySelectorAll('.lite-page-tab .tab-item > i:first-child').forEach((i) => {
      const node = i.firstChild;
      if (node && node.nodeType === 3 && TAB_TITLES[node.textContent.trim()]) node.textContent = TAB_TITLES[node.textContent.trim()];
    });

    detailActions();
    profileHeader();
    channelSwitcher();
  }

  // The timeline's feed tabs: Following and Hot switch straight to theirs, More opens Weibo's
  // channel sheet for the rest and shows the channel picked there.
  const FEEDS = [['关注', NAV('Following', '关注'), 'following'], ['热门', NAV('Hot', '热门'), 'hot']];

  function openChannels() {
    const plus = document.querySelector('.main-top .nav-plus');
    channelClick = true;
    if (plus) plus.click();
    channelClick = false;
  }

  function currentFeed() {
    const cur = document.querySelector('.main-top .nav_item .item_li.cur span');
    return (cur && cur.firstChild && cur.firstChild.textContent.trim()) || '关注';
  }

  // Weibo's own strip is hidden but still switches the feed; tapping the current feed again
  // scrolls back to the top.
  function selectFeed(name) {
    if (currentFeed() === name) {
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }
    const item = [...document.querySelectorAll('.main-top .nav_item .item_li')].find((li) => li.textContent.trim() === name);
    if (item) item.click();
    else openChannels();
  }

  function channelSwitcher() {
    let feeds = document.getElementById('mp-feeds');
    const bar = document.querySelector('.main-top');
    if (!bar) {
      if (feeds) feeds.remove();
      return;
    }
    if (!feeds) {
      feeds = document.createElement('div');
      feeds.id = 'mp-feeds';
      feeds.innerHTML =
        FEEDS.map(([name, title, icon]) =>
          `<button type="button" data-feed="${name}" style="--mp-icon: url('${ICONS[icon]}')"><span>${title}</span></button>`).join('') +
        `<button type="button" id="mp-channel" style="--mp-icon: url('${ICONS.channels}')"><span>${NAV('More', '更多')}</span></button>`;
      feeds.addEventListener('click', (e) => {
        const btn = e.target.closest('button');
        if (!btn) return;
        closeMenu();
        if (btn.dataset.feed) selectFeed(btn.dataset.feed);
        else openChannels();
      });
    }
    // Inside Weibo's bar, so the feeds stack (and dim) with it.
    if (feeds.parentElement !== bar) bar.appendChild(feeds);
    const name = currentFeed();
    const other = !FEEDS.some(([n]) => n === name);
    for (const btn of feeds.querySelectorAll('[data-feed]')) btn.classList.toggle('mp-sel', btn.dataset.feed === name);
    const more = feeds.querySelector('#mp-channel');
    more.classList.toggle('mp-sel', other);
    const label = more.querySelector('span');
    const text = other ? name : NAV('More', '更多');
    if (label.textContent !== text) label.textContent = text;
    const open = String(!!document.querySelector('.main-top .lite-nav-sublist'));
    if (more.getAttribute('aria-expanded') !== open) more.setAttribute('aria-expanded', open);
  }

  // Profile: cover photo behind the header; counts read
  // "20 Followers  53 Following".
  const COUNT_TITLES = L({ 关注: 'Following', 粉丝: 'Followers', 微博: 'Posts' }, {});
  const COUNT_KINDS = { Following: 'following', Followers: 'followers', Posts: 'posts', 关注: 'following', 粉丝: 'followers', 微博: 'posts' };
  let coverFor = '';

  function profileHeader() {
    const header = document.querySelector('.profile-header');
    if (!header) return;
    header.querySelectorAll('.prf-num b').forEach((b) => {
      const t = COUNT_TITLES[b.textContent.trim()];
      if (t) b.textContent = t;
      const kind = COUNT_KINDS[b.textContent.trim()];
      if (kind && b.parentElement.dataset.mp !== kind) b.parentElement.dataset.mp = kind;
    });
    const uid = (location.pathname.match(/^\/(?:profile|u)\/(\d+)/) || [])[1];
    if (!uid || coverFor === uid) return;
    coverFor = uid;
    fetch('/api/container/getIndex?type=uid&value=' + uid, { credentials: 'include' })
      .then((r) => r.json())
      .then((j) => {
        const cover = j && j.data && j.data.userInfo && j.data.userInfo.cover_image_phone;
        const current = document.querySelector('.profile-header');
        if (cover && current) current.style.setProperty('--mp-cover', `url("${cover}")`);
      })
      .catch(() => {});
  }

  // The detail page's counts live in the tabs; they are shown as the root
  // post's action row. The buttons forward to Weibo's own bottom bar.
  function detailActions() {
    const card = document.querySelector('.lite-page-wrap .main .card9');
    const tab = document.querySelector('.lite-page-tab');
    if (!card || !tab) return;
    let footer = card.querySelector(':scope > .mp-detail-actions');
    if (!footer) {
      footer = document.createElement('footer');
      footer.className = 'f-footer-ctrl mp-detail-actions';
      const kinds = [
        ['lite-iconf-report', '.lite-page-editor .lite-iconf-report'],
        ['lite-iconf-comments', '.lite-page-editor .main-text'],
        ['lite-iconf-like', '.lite-page-editor .lite-iconf-like'],
      ];
      for (const [icon, target] of kinds) {
        const btn = document.createElement('div');
        btn.className = 'm-diy-btn m-box-center-a';
        btn.innerHTML = `<i class="lite-iconf ${icon}"></i><h4></h4>`;
        btn.addEventListener('click', () => {
          const t = document.querySelector(target);
          if (t) t.click();
        });
        footer.appendChild(btn);
      }
      card.appendChild(footer);
    }
    const counts = [...tab.querySelectorAll('.tab-item > i:nth-child(2)')].map((i) => i.textContent.trim());
    footer.querySelectorAll('.m-diy-btn').forEach((btn, i) => {
      const v = counts[i] && counts[i] !== '0' ? counts[i] : ACTION_TITLES[i];
      const h4 = btn.querySelector('h4');
      if (h4.textContent !== v) h4.textContent = v;
      btn.classList.toggle('mp-zero', v === ACTION_TITLES[i]);
    });
    const liked = document.querySelector('.lite-page-editor .lite-iconf-liked, .lite-page-editor .lite-iconf-like.active');
    footer.children[2].classList.toggle('mp-on', !!liked);
  }

  // ---------- Boot ----------

  addStyle();
  const start = () => {
    addStyle();
    buildMenu();
    hookComposer();
    decorate(document);
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => {
        queued = false;
        decorate(document);
      });
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  };
  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();

      },
    },
  },
}))()
