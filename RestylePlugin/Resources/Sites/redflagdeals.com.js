// # redflagdeals.com
//
// What this script must do, written so it can be rebuilt when RedFlagDeals
// changes its page: this comment is the what, the code below the how. When
// they disagree after an RFD update, this comment wins: measure RFD's page
// again (see the plugin's AGENTS.md, Trying one) and fix the code to meet it.
//
// ## Why
//
// RFD's forums already have a mobile design, so they keep it. What makes
// them busy is everything around the deals: a promo banner, ad slots that
// leave empty grey boxes, sponsored "deals" mixed into the list, a video ad
// on a deal's page, a pop-up promotion, and thick grey gaps between cards.
//
// ## Styles
//
// | Style | Its purpose |
// |---|---|
// | Default | Reading the deals: RFD's own design, without the clutter. |
// | None | Voyager's, on every site: RFD as it ships. |
//
// 1. **Default.** RFD's own design, conservatively cleaned:
//    - No ads: no leaderboards above or below, no ad boxes in the list or
//      beside a thread, no video ad between a deal and its replies.
//    - No sponsored offers in the deal list.
//    - No promo banner under the header, no pop-up promotion.
//    - Cards in the list separated by a hairline, not an 8px grey gap.
//    - On a deal's page, less space around each reply's action bar.
//    Covers the main list (Hot Deals) and the details page (a deal's
//    thread); other pages get the same ad removal.
//
// ## Must hold
//
// - Every deal, post, link and control of RFD's own is still there.
// - RFD's light and dark modes keep working.
//
// ## RFD's page, as measured (2026-10-22)
//
// - List: `ul.topics-cards`, a flex column with `gap: 8px` on a grey
//   background; each deal `li.topic-card`, its link `a.thread_info`; a
//   sponsored one's link also has `.sponsored-offer`. Ads in the list are
//   `li.ad_box`.
// - Ads elsewhere: `#header_leaderboard`, `#footer_leaderboard`,
//   `.ad_sidebar_bigbox`, `.forum_topic_inline_bigbox`; the video ad on a
//   thread is `#primisSlider` and `#primisContainer`.
// - The promo banner is `.announcement.message`. Pop-ups ("Brand Hunter"
//   on the list, "Enjoying the Deals?" on a thread, which also fades the
//   page) are `getsitecontrol-widget` elements added at the end of the
//   body; their shadow DOM's `:host` rule keeps them shown against any
//   page CSS, even `!important`, so they have to be removed.
// - Thread: `section.thread_posts > article.post.thread_post`; each reply's
//   `.actionbar_wrapper` has margins of 12.5px above and 25px below.
//
// ## Requests
//
// 2026-10-22
// - Optimise RedFlagDeals. → Default: RFD's design without the clutter.
// - Fix at least the main page and the details page, usually. → Both; a
//   rule in AGENTS.md.
// - Reduce card gaps, as a general direction. → Hairlines between cards;
//   a rule in AGENTS.md.
// - Removing ads is fine. → All ad slots hidden; a rule in AGENTS.md.

(() => {
  const ads = `
    #header_leaderboard, #footer_leaderboard, .ad_box, .ad_sidebar_bigbox,
    .forum_topic_inline_bigbox, #primisSlider, #primisContainer,
    li.topic-card:has(> a.sponsored-offer),
    .announcement.message { display: none !important; }
  `;
  const cards = `
    ul.topics-cards { gap: 1px !important; }
    .thread_post .actionbar_wrapper { margin: 6px 0 8px !important; }
  `;

  // The pop-ups are GetSiteControl widgets, drawn in their own shadow DOM
  // whose `:host` rule outranks any page CSS, so they're removed as they
  // arrive instead: always at the end of the body, so only its direct
  // children are watched.
  const popups = () => {
    const sweep = () => document.querySelectorAll("getsitecontrol-widget").forEach((w) => w.remove());
    let queued = false;
    const watcher = new MutationObserver(() => {
      if (queued) return;
      queued = true;
      // A timeout, not a frame: frames don't come in a hidden panel.
      setTimeout(() => { queued = false; sweep(); });
    });
    const watch = () => { sweep(); watcher.observe(document.body, { childList: true }); };
    document.body ? watch() : document.addEventListener("DOMContentLoaded", watch, { once: true });
    return () => { watcher.disconnect(); document.removeEventListener("DOMContentLoaded", watch); };
  };

  return {
    variants: {
      default: { label: "Default", style: ads + cards, start: popups },
    },
  };
})()
