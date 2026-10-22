// # v2ex.com
//
// What this script must do, written so it can be rebuilt when V2EX changes
// its page: this comment is the what, the code below the how. When they
// disagree after a V2EX update, this comment wins: measure V2EX's page again
// (see the plugin's AGENTS.md, Trying one) and fix the code to meet it.
//
// ## Why
//
// V2EX serves desktop browsers a fixed two-column page with no mobile
// viewport: its content is at least 600px wide and the topic column always
// keeps 310px free for the right sidebar. In Voyager's panel (about 450px)
// the topics end up squeezed into a sliver and the page scrolls sideways.
//
// ## Styles
//
// | Style | Its purpose |
// |---|---|
// | Default | Reading V2EX in a narrow panel: one column, as on a phone. |
// | None | Voyager's, on every site: V2EX as it ships. |
//
// 1. **Default.** V2EX as a single mobile-like column, like Weibo's:
//    - One column across the whole width; no sideways scrolling at any
//      width.
//    - The important buttons stay in a top bar that fits: logo, a search
//      box that shrinks, the account links.
//    - The topics (or the topic and its replies) first; the right sidebar
//      (sign in or your account, hot topics, nodes) follows below them;
//      the empty left bar is hidden.
//    - Both rows of node tabs wrap, so every tab is in sight; nothing in
//      them overlaps.
//    - Calm cards: in a topic row only the title stands out — in the text
//      colour, 15px; the avatar 40px and rounded; the node, author, time
//      and last replier on one line that trails off ("…") rather than
//      wrapping; the reply count plain grey, no pill. Replies get the same
//      avatar.
//    - Pictures and embeds in posts and replies never overflow; code
//      blocks and wide tables scroll sideways inside themselves; long
//      links wrap.
//    - Boxes run edge to edge, square, with no page padding left or
//      right.
//    - Flat and clean: no shadows, no gradient band under the top bar, no
//      glossy buttons; plain surfaces, hairline separators.
//    - Vertical spacing tight, for V2EX only: no gaps between boxes (a
//      hairline separates them), 6px above and below a row's content;
//      cards (a topic in the list, a reply) get 12px.
//
// ## Must hold
//
// - Nothing hidden: every link, tab, button and box V2EX shows is still
//   there, only moved or resized — except the end of a long details line
//   in a topic row, which trails off.
// - V2EX's own light and dark themes keep working.
//
// ## V2EX's page, as measured (2026-10-22)
//
// - `#Top > .content > .site-nav` holds `#Logo`, `#search-container`
//   (246px wide) and `.tools` (the links).
// - `#Wrapper > .content` holds `#Leftbar` (empty), `#Rightbar` (270px,
//   floated right) and then `#Main` (margin 0 310px 0 20px), in that order:
//   the sidebar comes first in the page.
// - `.content` has `min-width: 600px; max-width: 1100px`.
// - `#Tabs` and `#SecondaryTabs` are the node tabs on the home page, spaced
//   with `&nbsp;` text; signed in, the second row also has a link floated
//   right.
// - Posts are `.topic_content`, replies `.reply_content`; topic rows are
//   `.cell.item`, each a table.
// - Boxes are `.box`; `.sep20` is the 20px gap between them.
// - There is no `<meta name="viewport">`.
// - The page's own inline `<style>` sets `body { min-width: 820px }`: the
//   main cause of sideways scrolling.
//
// ## Requests
//
// 2026-10-22
// - Fix V2EX's style: make the content fit, as on mobile. → Default, one
//   column with the sidebar below.
// - Most sites should look like their mobile version, or like Weibo's
//   Default. → One column here; a rule in AGENTS.md.
// - Content across the whole width; important buttons to a top or bottom
//   bar. → No width cap; the top bar keeps logo, search and links.
// - No page padding left or right. → Boxes edge to edge, square.
// - The content river (topics, a topic's replies) uses the entire width.
//   → As above; the term is in AGENTS.md.
// - Reduce V2EX's vertical gaps (V2EX only, not a global rule). → 4px
//   between boxes, 6px row padding.
// - Remove the gaps (the grey band under the top bar, between boxes). →
//   Boxes meet, hairlines between them.
// - The two tab rows should wrap. → Both wrap; the second row's
//   right-floated link no longer overlaps its tabs.
// - (Follow-up) wrapped tab lines started indented. → Even gaps, no
//   &nbsp; runs.
// - Increase the cards' vertical spacing. → Topic rows and replies get
//   12px above and below.
// - More card-like, not busy. → Calm cards (see Default).
// - Keep it safe; don't overcomplicate it so it breaks. → Kept to sizes,
//   colours and spacing on V2EX's own structure; a rule in AGENTS.md.
// - Prefer a flat, simple, clean design. → Shadows, gradients and glossy
//   buttons removed; a rule in AGENTS.md.

(() => {
  const column = `
    body { min-width: 0 !important; }
    #Top .content, #Wrapper .content, #Bottom .content {
      min-width: 0 !important; max-width: none !important; box-sizing: border-box !important;
    }
    /* Topics first, then the sidebar: it comes first in the page. */
    #Wrapper .content { display: flex !important; flex-direction: column !important; }
    #Leftbar { display: none !important; }
    /* Edge to edge, as on a phone: no page padding, square boxes. */
    #Main { order: 1; margin: 0 !important; width: auto !important; padding: 0 !important; }
    #Rightbar { order: 2; float: none !important; width: auto !important; margin: 0 !important; padding: 0 !important; }
    #Main .box, #Rightbar .box { border-radius: 0 !important; }
    /* V2EX's own spacing is airy for a narrow panel: tighter gaps
       between boxes and inside rows (this site's choice, not a rule). */
    .sep20 { height: 0 !important; }
    .sep10 { height: 4px !important; }
    .sep5 { height: 2px !important; }
    .cell { padding-top: 6px !important; padding-bottom: 6px !important; }
    /* Cards — a topic in the list, a reply — get more room than the rest. */
    .cell.item, #Main .cell[id^="r_"] { padding-top: 12px !important; padding-bottom: 12px !important; }
  `;
  const top = `
    #Top { padding: 0 8px !important; }
    #search-container { width: auto !important; flex: 1 1 auto !important; min-width: 60px !important; }
    .site-nav .tools { flex: 0 0 auto !important; white-space: nowrap !important; }
  `;
  // Both tab rows wrap, every tab in sight; a link V2EX floats right on
  // the second row (signed in) takes its place on the wrapped lines
  // rather than overlapping the tabs.
  const tabs = `
    /* V2EX spaces its tabs with &nbsp; runs, which indent a wrapped line;
       even gaps instead, the spaces shrunk to nothing. */
    #Tabs, #SecondaryTabs {
      display: flex !important; flex-wrap: wrap !important; align-items: center !important;
      gap: 6px 14px !important; font-size: 0 !important; overflow: visible !important;
    }
    /* The top row's tabs are pills with padding of their own. */
    #Tabs { gap: 4px 2px !important; }
    #Tabs > *, #SecondaryTabs > * {
      font-size: 14px !important; line-height: 1.6 !important; margin: 0 !important; float: none !important;
    }
  `;
  // Flat: V2EX's shadows, its gradient band under the top bar, and its
  // glossy buttons go; plain surfaces and hairlines stay.
  const flat = `
    #Wrapper { background-image: none !important; background-color: var(--box-background-alt-color, #f5f5f5) !important; }
    #Top { box-shadow: none !important; border-bottom: 1px solid var(--box-border-color) !important; }
    .box, .button, .super.button, .normal.button, .tag, .page_normal, .page_current, .page_input,
    .radio-group, .radio-group > label {
      box-shadow: none !important; text-shadow: none !important; background-image: none !important;
    }
  `;
  // Calm cards: one thing stands out in each, the title. A smaller,
  // rounded avatar; the title in the text colour; the details on one line,
  // trailing off rather than wrapping; the reply count plain.
  const cards = `
    /* Fixed columns, or the one-line details stretch the row's table. */
    .cell.item > table { table-layout: fixed !important; }
    .cell.item td:first-child, .cell.item td:first-child img.avatar,
    #Main .cell[id^="r_"] td:first-child, #Main .cell[id^="r_"] td:first-child img.avatar {
      width: 40px !important; max-width: 40px !important;
    }
    .cell.item img.avatar, #Main .cell[id^="r_"] img.avatar { height: 40px !important; border-radius: 10px !important; }
    .cell.item td:first-child + td, #Main .cell[id^="r_"] td:first-child + td { width: 12px !important; }
    .cell.item .item_title { font-size: 15px !important; line-height: 1.35 !important; }
    .cell.item .item_title a, .cell.item .item_title a:visited { color: var(--box-foreground-color) !important; }
    .cell.item .topic_info {
      display: block !important; white-space: nowrap !important; overflow: hidden !important;
      text-overflow: ellipsis !important; line-height: 1.6 !important; margin-top: 4px !important;
    }
    .cell.item .topic_info a.node { background: none !important; padding: 0 !important; color: inherit !important; }
    .cell.item td:last-child { width: 36px !important; }
    .cell.item a.count_livid, .cell.item a.count_orange {
      background: none !important; color: var(--color-fade) !important; font-weight: 500 !important;
      font-size: 13px !important; padding: 0 !important;
    }
  `;
  const posts = `
    .topic_content, .reply_content { overflow-wrap: anywhere !important; }
    .topic_content img, .reply_content img, .topic_content video, .reply_content video,
    .topic_content iframe, .reply_content iframe {
      max-width: 100% !important; height: auto !important;
    }
    .topic_content pre, .reply_content pre { max-width: 100% !important; overflow-x: auto !important; }
    .topic_content table, .reply_content table { display: block !important; max-width: 100% !important; overflow-x: auto !important; }
  `;

  return {
    variants: {
      default: { label: "Default", style: column + flat + top + tabs + cards + posts },
    },
  };
})()
