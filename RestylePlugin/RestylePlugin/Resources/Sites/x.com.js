// # x.com
//
// What this script must do, written so it can be rebuilt when X changes its
// page: this comment is the what, the code below the how. When they disagree
// after an X update, this comment wins: measure X's page again (see the
// plugin's AGENTS.md, Trying one) and fix the code to meet it.
//
// ## Why
//
// X's menu is a column on the left, right beside Voyager's sidebar, which
// doubles up the chrome and squeezes the timeline. Voyager's panel is often
// narrow (about 450px of page), so every pixel of width matters.
//
// ## Styles
//
// Offered in the ⋯ menu's Styles, in this order; the first is the default.
// Each exists for its own kind of use, so all of them stay.
//
// | Style | Its purpose |
// |---|---|
// | Bottom bar | Everyday use: the menu always in reach, the timeline gets the full width. Moves X's chrome to where Voyager's isn't. |
// | Hidden, slides up at the bottom | Reading: no chrome at all until it's wanted; the bar is one flick of the pointer away, at the edge furthest from Voyager's sidebar. |
// | Hidden, slides out at the left | Reading, for those used to X's menu as it is: X's own column when wanted, never beside Voyager's sidebar otherwise. |
// | On the right | Keeping X's full menu, labels and all, always shown, but on the side away from Voyager's sidebar. |
// | None | Voyager's, on every site: X as it ships, and the fallback when an X update breaks the others. |
//
// Tried and dropped: a floating dock (a pill above the bottom edge), which
// covered content without giving more room than the bar.
//
// 1. **Bottom bar.** X's menu becomes one row along the bottom of the page.
//    - 48px tall, the page's background (light, dim and dark all right), a
//      hairline top border.
//    - Icons only, no labels; no X logo.
//    - In the bar, in order: Home, Explore, Notifications, Messages, Profile,
//      More. Six, the most a bottom bar holds (AGENTS.md);
//      anything more goes behind More.
//    - No Post button: the composer is already at the top of the timeline.
//    - No account button (the avatar): Profile is already in the bar. Switching
//      accounts isn't reachable in this style; use None for that.
//    - Like an iOS tab bar: every item in the bar is a 44px slot, the slots spaced equally across the
//      whole width, so a narrow panel spreads them out rather than bunching
//      them.
//    - Everything else in X's nav (Grok, Follow, Calls, Premium, Money,
//      History, and whatever X adds later) is hidden from the bar. X's More
//      button opens a panel above the bar listing those items, icon and name,
//      with X's own More menu as its last row. The panel closes on a click
//      outside or Escape.
//    - The timeline gets padding at the bottom so nothing sits under the bar.
//    - Six 44px slots fit even the narrowest panel, so the bar never scrolls.
// 2. **Hidden, slides up at the bottom.** As 1, but off-screen until the
//    pointer reaches the bottom 8px of the page; it slides up (0.2s, none
//    under reduced motion) and slides away once the pointer is 16px clear of
//    it. No padding at the bottom.
// 3. **Hidden, slides out at the left.** X's menu as X draws it, as an
//    overlay off the left edge. It opens only after the pointer rests in the
//    left 8px for 300ms (crossing in from Voyager's sidebar mustn't open it)
//    and closes once the pointer is 16px clear.
// 4. **On the right.** X's menu as X draws it, moved to the right of the
//    timeline.
// 5. **None.** Voyager's own, at the top of Styles: no changes.
//
// In 1–3 the timeline column uses the width the menu gave up.
//
// ## Must hold in every style
//
// - Every item shown still works: links navigate in place, More opens X's
//   menu; where shown, the account button opens its menu and Post opens the
//   composer.
// - Nothing the page uses is taken: no clicks other than More's in styles
//   1–2, no keys other than Escape while the panel is open.
// - Works at a 450px-wide page and at full screen, in X's light, dim and dark
//   themes, in English and Chinese.
//
// ## Requests
//
// What was asked for, in order, and what came of it. Newest last.
//
// 2026-10-22
// - Take X's left menu out of the way of Voyager's sidebar; usually move
//   it to the bottom. → Bottom bar, the default.
// - Offer several ways to try on the real site, not mockups. → Styles,
//   switched in the ⋯ menu.
// - Remove the floating dock. → Dropped.
// - Keep the styles as options for the user. → All kept; see Styles.
// - Bottom bar: move the non-essential items into More. → Six in the bar,
//   the rest in a panel from More.
// - Bottom bar: equal spacing across the width when narrow, like an iOS
//   tab bar. → 44px slots spaced evenly.
// - Remove Post; the composer is already at the top. → Dropped.
// - Remove the account avatar on the right. → Dropped.
// - A bottom bar holds 5–6 items at most; the rest go into More (a rule
//   for every site's horizontal bottom bar). → In AGENTS.md; X has six.
// - A None option in Styles, for not applying any. → Voyager adds None to
//   every site's Styles; X's own "As X has it" removed.
// - The first style is the default. → Bottom bar, first, as it was.
//
// ## X's page, as measured (2026-10-22)
//
// These are what the script hangs on. Check them first when it breaks.
//
// - The menu is `header[role="banner"]`. Inside it, a `position: fixed`
//   column holds, in order: a box with `h1` (the X logo), a box with
//   `nav[role="navigation"]`, a box with the Post link, then a box with the
//   account button.
// - Nav items are direct children of the nav: `a` links, plus a `button`
//   for More. Test IDs: `AppTabBar_Home_Link`, `AppTabBar_Explore_Link`,
//   `AppTabBar_Notifications_Link`, `AppTabBar_Follow_Link`,
//   `AppTabBar_DirectMessage_Link`, `AppTabBar_Calls_Link`,
//   `premium-hub-tab`, `AppTabBar_Profile_Link`, `AppTabBar_More_Menu`.
//   Grok, Money and History have no test ID. Each item's `aria-label` is its
//   name in the page's language.
// - Post is `a[data-testid="SideNav_NewTweet_Button"]`; the account button
//   is `button[data-testid="SideNav_AccountSwitcher_Button"]`, its avatar in
//   `[data-testid^="UserAvatar-Container"]`.
// - X stretches each nav item to the column's width, and keeps the
//   icon-only column even at 450px: there is no phone layout to allow for.
// - Labels, where shown, are `[dir]` text inside each nav item. Post's
//   `[dir]` box holds its icon as well as its label: never hide it.
// - X's boxes between the header and its items fight a row: laid out as
//   they are, they squeeze the nav to about 40px and stretch Post's box
//   across the rest. The bar sets them all `display: contents`, so the
//   items sit in the header's row directly.
// - The page background is the body's inline `background-color`, which X
//   changes with the theme.
// - X's class names (`css-…`, `r-…`) change with every deploy: never use them.

(() => {
  const header = 'header[role="banner"]';
  const chain = `${header} div:has(nav[role="navigation"])`;

  // The menu as one row of icons, wherever it's then put: like an iOS tab
  // bar, the items spaced equally across it. Every box between the header
  // and its items steps aside (`display: contents`), so X's nav links sit in the header's row directly; X's own boxes
  // otherwise squeeze the nav and stretch Post's. Each item is a 44px slot,
  // its icon centred.
  //
  // Post and the account button are left out: the composer is already at
  // the top of the timeline, and Profile is in the bar.
  const items = [`nav[role="navigation"] > a`, `nav[role="navigation"] > button`].map((i) => `${header} ${i}`).join(", ");
  const row = `
    ${header} {
      display: flex !important; flex-direction: row !important; align-items: center !important;
      justify-content: space-evenly !important; padding: 0 !important; margin: 0 !important;
      overflow-x: auto !important; scrollbar-width: none !important;
    }
    ${chain}, ${header} nav[role="navigation"],
    ${header} div:has([data-testid="SideNav_NewTweet_Button"]),
    ${header} div:has([data-testid="SideNav_AccountSwitcher_Button"]) { display: contents !important; }
    ${header} div:has(> h1) { display: none !important; }
    ${items} {
      display: flex !important; flex: 0 0 44px !important; width: 44px !important; height: 48px !important;
      min-width: 0 !important; margin: 0 !important; padding: 0 !important;
      align-items: center !important; justify-content: center !important;
    }
    /* No Post: the composer is already at the top of the timeline. No
       account button: Profile is in the bar already. */
    ${header} a[data-testid="SideNav_NewTweet_Button"], ${header} [data-testid="SideNav_AccountSwitcher_Button"] { display: none !important; }
    ${header} nav a [dir] { display: none !important; }
  `;
  const bar = `
    ${header} {
      position: fixed !important; left: 0 !important; right: 0 !important; bottom: 0 !important;
      top: auto !important; height: 48px !important; z-index: 10 !important;
      background: var(--voyager-bg) !important; border-top: 1px solid rgba(128, 128, 128, 0.25) !important;
    }
  `;
  const wide = `
    main[role="main"] > div, main[role="main"] > div > div { width: 100% !important; max-width: none !important; }
    [data-testid="primaryColumn"] { max-width: none !important; flex: 1 1 auto !important; }
  `;
  const room = (px) => `main[role="main"] { padding-bottom: ${px}px !important; }`;
  const slide = (away) => `
    ${header} { transform: ${away} !important; transition: transform 0.2s ease !important; }
    html.voyager-menu-shown ${header} { transform: none !important; }
    @media (prefers-reduced-motion: reduce) { ${header} { transition: none !important; } }
  `;

  // The menu wears the page's background: X sets the body's inline, and
  // again when its theme — light, dim, dark — changes.
  const theme = () => {
    const root = document.documentElement;
    const paint = () => document.body && root.style.setProperty("--voyager-bg", getComputedStyle(document.body).backgroundColor);
    const watcher = new MutationObserver(paint);
    const watch = () => { paint(); watcher.observe(document.body, { attributes: true, attributeFilter: ["style"] }); };
    document.body ? watch() : document.addEventListener("DOMContentLoaded", watch, { once: true });
    return () => { watcher.disconnect(); document.removeEventListener("DOMContentLoaded", watch); root.style.removeProperty("--voyager-bg"); };
  };

  // A hidden menu shows when the pointer reaches its edge. At the bottom
  // that's enough; at the left the pointer has to rest there, or every
  // trip in from Voyager's sidebar would open it. It hides once the
  // pointer is well away from it.
  const reveal = (edge) => {
    const root = document.documentElement, zone = 8, rest = edge === "left" ? 300 : 0;
    let timer = null;
    const show = (on) => root.classList.toggle("voyager-menu-shown", on);
    const move = (e) => {
      if (edge === "left" ? e.clientX <= zone : e.clientY >= innerHeight - zone) {
        timer ??= setTimeout(() => show(true), rest);
        return;
      }
      clearTimeout(timer); timer = null;
      const menu = document.querySelector(header);
      // Not while the More panel is open: it sits above the bar, and
      // reaching for its upper rows would slide the bar away under it.
      if (!root.classList.contains("voyager-menu-shown") || !menu || document.getElementById("voyager-more")) return;
      const r = menu.getBoundingClientRect(), slack = 16;
      if (e.clientX < r.left - slack || e.clientX > r.right + slack || e.clientY < r.top - slack || e.clientY > r.bottom + slack) show(false);
    };
    document.addEventListener("pointermove", move, { passive: true });
    return () => { clearTimeout(timer); document.removeEventListener("pointermove", move); show(false); };
  };
  const both = (...starts) => () => { const undos = starts.map((s) => s()); return () => undos.forEach((u) => u()); };

  // A bar keeps what's used most; the rest of X's nav — and whatever X adds
  // to it later — goes behind X's own More button, in a panel above the
  // bar. Its last row is X's More menu itself.
  const essential = ["AppTabBar_Home_Link", "AppTabBar_Explore_Link", "AppTabBar_Notifications_Link", "AppTabBar_DirectMessage_Link", "AppTabBar_Profile_Link", "AppTabBar_More_Menu"];
  const extra = `${header} nav[role="navigation"] > :is(a, button)${essential.map((id) => `:not([data-testid="${id}"])`).join("")}`;
  const more = `${header} [data-testid="AppTabBar_More_Menu"]`;
  const tucked = `
    ${extra} { display: none !important; }
    #voyager-more {
      position: fixed; right: 8px; bottom: 56px; z-index: 11; min-width: 200px; padding: 6px 0;
      border-radius: 12px; background: var(--voyager-bg); color: inherit;
      border: 1px solid rgba(128, 128, 128, 0.25); box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
      font: 15px -apple-system, system-ui, sans-serif;
    }
    #voyager-more button {
      display: flex; align-items: center; gap: 12px; width: 100%; padding: 10px 16px;
      border: 0; background: none; color: inherit; font: inherit; text-align: left; cursor: pointer;
    }
    #voyager-more button:hover { background: rgba(128, 128, 128, 0.12); }
    #voyager-more svg { width: 22px; height: 22px; fill: currentColor; }
  `;
  const overflow = () => {
    let panel = null, passing = false;
    const close = () => { panel?.remove(); panel = null; };
    const row = (icon, label, act) => {
      const b = document.createElement("button");
      if (icon) b.append(icon.cloneNode(true));
      b.append(label);
      b.onclick = () => { close(); act(); };
      return b;
    };
    const open = (button) => {
      panel = document.createElement("div");
      panel.id = "voyager-more";
      panel.setAttribute("role", "menu");
      for (const item of document.querySelectorAll(extra)) {
        panel.append(row(item.querySelector("svg"), item.getAttribute("aria-label") ?? "", () => item.click()));
      }
      panel.append(row(button.querySelector("svg"), button.getAttribute("aria-label") ?? "More", () => { passing = true; button.click(); passing = false; }));
      document.body.append(panel);
    };
    const click = (e) => {
      const button = e.target.closest?.(more);
      if (button && !passing) {
        e.preventDefault(); e.stopPropagation();
        panel ? close() : open(button);
      } else if (panel && !panel.contains(e.target)) close();
    };
    const key = (e) => { if (e.key === "Escape") close(); };
    document.addEventListener("click", click, true);
    document.addEventListener("keydown", key, true);
    return () => { close(); document.removeEventListener("click", click, true); document.removeEventListener("keydown", key, true); };
  };

  return {
    variants: {
      bottom: { label: "Bottom bar", style: row + bar + tucked + wide + room(48), start: both(theme, overflow) },
      "reveal-bottom": { label: "Hidden, slides up at the bottom", style: row + bar + tucked + slide("translateY(100%)") + wide, start: both(theme, overflow, () => reveal("bottom")) },
      "reveal-left": {
        label: "Hidden, slides out at the left",
        style: `
          ${header} {
            position: fixed !important; left: 0 !important; top: 0 !important; bottom: 0 !important;
            width: auto !important; z-index: 10 !important;
            background: var(--voyager-bg) !important; border-right: 1px solid rgba(128, 128, 128, 0.25) !important;
          }
          ${header} > div, ${header} > div > div { position: static !important; height: 100% !important; }
        ` + slide("translateX(-100%)") + wide,
        start: both(theme, () => reveal("left")),
      },
      // The header holds the menu's place in X's row; after the main
      // column, the inner fixed column — no left of its own — follows it.
      right: {
        label: "On the right",
        style: `
          ${header} { order: 2 !important; }
          ${header} > div > div > div { align-items: flex-start !important; }
        `,
      },
    },
  };
})()
