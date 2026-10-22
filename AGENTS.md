# Restyle Plugin

Changes how a site looks and behaves inside Voyager, site by site: its own
chrome out of the way, the content given the room, whatever else a site
needs to sit well beside Voyager's.

Voyager keeps its sidebar on the left: a column of site icons, 77pt wide
(`Voyager/Scenes/Sidebar/SidebarViewModel.swift`). Many sites put their own
menu on the left too — X's nav, YouTube's guide, Weibo's — so a page opens
with two menus side by side and its content pushed right and squeezed. The
first restyles rearrange a site around its content. What that takes is
decided site by site; moving the menu to a bar at the bottom is the usual
first answer, not a rule.

## How it fits Voyager

**Today:** Debug builds only. `Voyager/Scenes/Browser/PageRestyle.swift`
reads the scripts straight from this folder, named by `-RestyleDir` (see
Trying one); there's no plugin app yet, and Settings' plugin toggle doesn't
affect restyles. Each site's script goes into its pages at document start,
main frame only, in the default content world — next to the muter and
media clicks in `BrowserViewModel.installUserScripts()` — and the ⋯ menu's
Styles lists the page's styles.

**Planned:** a plugin like the Media Plugin (`../MediaPlugin`), and for the
same reason: its scripts go into pages, so it ships as a team-signed app in
/Applications that Voyager checks (`Voyager/Services/Plugins.swift`), the
signed carrier of `Resources/manifest.json` and `Resources/Sites/*.js`, its
trigger kind `page.restyle`. Unlike `media.click` there's no request to the
app. With the plugin off in Settings, sites will be as they ship.

## One file per site

A site's script is `Resources/Sites/<domain>.js`, named after its domain:
`x.com.js`. It covers the domain and its subdomains, so `x.com.js` also
covers `mobile.x.com`; where two files cover a page, the more specific
wins (`m.weibo.cn.js` over a `weibo.cn.js`). Each file is its own script in
the page, so a mistake in one leaves the other sites working. Nothing is listed in the manifest,
whose trigger is just `{ "kind": "page.restyle" }`. Adding a site means
adding its file.

Each script opens with its requirements, as a comment: why the site needs
restyling, each style with its purpose and how it should look and behave,
what must hold in all of them, styles tried and dropped, and the site's
page as last measured (selectors, structure, quirks). One file, so the two
can't drift apart. Sites change their pages without warning; when a script
breaks, its comment is what the code is rebuilt from: measure the page
again, update the comment's measurements, then fix the code until it meets
the rest. A new site starts with its comment.

The comment ends its requirements with **Requests**: each thing asked for
the site, in order with its date, and what came of it (done, how, or why
not). New requests are added there as they come, so the reasons behind
the styles survive the conversation they were asked in.

Keep the rest of the comment current too: every UI change asked for (an item moved or
dropped, spacing, a style added or removed) goes into it in the same change
as the code, with why. Code that does something its comment doesn't say is
a bug in one of them. `Sites/x.com.js` is the example to follow.

## A site's script

One expression, as the media scripts are: the site's variants, each a way to
rearrange it, the first the default:

```js
(() => {
  // shared CSS pieces and helpers
  return {
    variants: {
      bottom: { label: "Bottom bar", style: "…", start() { …; return undo; } },
    },
  };
})()
```

`style` is the whole rearrangement, when CSS can do it. `start`, optional,
is whatever CSS can't (theme colours, reveal on hover), and returns its undo.
Voyager's wrapper puts `style` in one `<style id="voyager-restyle">`, runs
`start`, and undoes it before switching. A script never adds a `<style>` of
its own.

A style can also be someone else's published userscript, adopted whole
(`Sites/m.weibo.cn.js`): its code unchanged as the style's `start`, its
source, version and licence in the header. Only one that runs without
Tampermonkey's APIs (`@grant none`), and only after reading all of it: no
requests beyond the site's own, no eval, no cookies or storage it doesn't
need. Such a script adds its own `<style>` and can't be undone, so the style
says `reload: true` and switching to or from it reloads the page. Name its
file for the exact host it was written for.

Variants are the user's options for a site, offered in the ⋯ menu's
Styles: two to four that fit it, best first. **The first is the default**,
what a site gets until the user picks another. Voyager adds **None** at the
top of every site's Styles, apart from the rest: the site as it ships, for
anyone who doesn't want a restyle. A script never declares its own "off".
The choice is kept in the site's own storage.

## How we do the UI

Case by case. Start from what people use a site for (X's timeline, an
article's text, a video and its comments), then ask what crowds it, and
pick the pattern that fits that site. Most often it's the bottom bar; when
a site calls for something else (a menu already at the top, a right column
that matters more than the left one), do that instead and say why in the
script's comment.

1. **Bottom bar (the usual choice).** The site's menu becomes one row of
   icons, fixed along the bottom of the page, labels hidden, about 48px
   tall, the page's own background and a hairline top border.
   - **5–6 items at most, More included**, as on an iOS tab bar. Pick the
     ones used most; everything else goes behind the site's More (or one
     the restyle adds), so the bar never scrolls or shrinks its icons.
     This limit is for a horizontal bottom bar only; a menu kept as a
     column (left, right) keeps all its items.
   - Items spaced equally across the bar's whole width, icons centred in
     44px slots. The content
   gets `padding-bottom` to match so nothing hides under it. Many sites
   already have this bar in their phone layout (X does under 500px wide);
   copy its look rather than inventing one.
2. **Hidden, reveal at the bottom.** As 1, but the bar sits off-screen and
   slides up (`transform`, 0.2s ease) when the pointer reaches the bottom
   8px; it slides away when the pointer leaves it.
3. **Hidden, reveal at the left.** The menu slides in from the left edge as
   an overlay above the content. The pointer must *rest* in the left 8px for
   300ms: crossing that edge on the way in from Voyager's sidebar mustn't
   open it.
4. **Right side.** The menu moves to the right of the content, as it is.

Common to all:

- **Full width for the content.** With the menu gone, the main column uses
  the room.
- **Nothing lost by accident.** Every item stays reachable — in the bar,
  behind More, or elsewhere on the page — unless the site's script comment says it's
  dropped and why (X's Post, which the timeline's composer already does).
- **Never steal the page's input.** Reveal zones are thin and only react to
  pointer position; no click or key the site uses is taken. A shortcut, if
  any, needs a modifier.
- **Follow the site's theme.** Colours come from the page
  (`getComputedStyle(document.body).backgroundColor`), so light, dim and
  dark modes all look right.
- **Motion is short and optional.** 0.2s transforms; none under
  `prefers-reduced-motion`.

## Writing one

- **Selectors that last.** ARIA roles, `data-testid`, tag structure: X's menu
  is `header[role="banner"]`, its links `nav[role="navigation"] a`. Never the
  generated class names (`css-175oi2r`, `r-…`); they change every deploy.
- **CSS first.** Rearranging is CSS with `!important` against the site's
  inline styles. JS only for reveal, theme colours and what CSS can't
  select.
- **Single-page apps.** X, YouTube re-render without reloading; CSS keeps
  applying. If JS must find elements, one `MutationObserver` on the body,
  throttled to a frame.
- **Comments say why**, as the media scripts do: what the site does that the
  rule works around.

## Trying one

On the real site, in a Debug build of Voyager
(`Voyager/Scenes/Browser/PageRestyle.swift`). Launch it unsigned, which
leaves it outside the sandbox, with the plugin's source folder:

```sh
open -n <Debug>/Voyager.app --args -RestyleDir "$PWD/Plugins/RestylePlugin/RestylePlugin/Resources"
```

The ⋯ menu's Styles switches between the site's styles live. The choice is
kept in the site's own storage. Scripts are read whenever a browser view
sets up its page scripts (at launch, and again on some changes), so
relaunch after editing one to be sure every view has it.

Check each variant at three window widths (narrow panel, half screen, full),
in light and dark, and that the menu's every item still works.

Measure the site's real DOM before writing CSS for it, never guess.
Lessons from X:

- X keeps its left menu, icons only, even in a 450px panel; there's no
  phone layout to dodge.
- X stretches each nav item across its column, so in a row each one takes
  the full width. Size items to their icons.
- X's nav has 14 items; a bottom bar keeps six and the rest go behind
  More (see the bottom bar's limit above).
