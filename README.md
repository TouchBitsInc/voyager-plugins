# Voyager Plugins

Open-source plugins for [Voyager](https://touchbits.com), each an app of its
own that adds what Voyager's sandbox can't do by itself.

| Plugin | What it does | Get it |
|---|---|---|
| [Media Plugin](MediaPlugin) | Plays and saves a page's videos and photos in a window of its own | [Latest release](https://github.com/TouchBitsInc/voyager-plugins/releases/latest) |
| [Restyle Plugin](RestylePlugin) | Rearranges sites' own menus and clutter to fit beside Voyager's sidebar | Not released yet |

To install a plugin, download its DMG, open it, and drag the app to
Applications. Installed copies update themselves through Sparkle.

## Layout

- `Shared/PluginProtocol.swift`: how Voyager and its plugins talk. Voyager
  keeps a copy of it; the two must agree, and `protocolVersion` says when they
  don't.
- `MediaPlugin/`, `RestylePlugin/`: one folder per plugin, each with its own
  version, release workflow and Sparkle feed.
- `.github/workflows/`: a merge to `main` that changes a plugin (or `Shared/`)
  builds, signs, notarizes and releases that plugin.

MIT licensed; see [LICENSE](LICENSE).
