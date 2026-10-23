# Voyager Plugins

Voyager's plugins, one folder each, and the protocol they share with it.
Each plugin's own `AGENTS.md` says how it works; this file is what holds
across them.

- **Independent versions.** Each plugin has its own version (its xcconfig's
  `MARKETING_VERSION`), its own Sparkle key and feed, and its own release
  workflow, triggered by changes to its folder or `Shared/`. A merge to
  `main` releases only what changed.
- **One "latest" release.** Installed Media Plugins read the appcast of this
  repo's *latest* release, asked for at the repo's old name
  `voyager-media-plugin`, which GitHub redirects here. So the Media Plugin's
  releases stay the latest: every other plugin's release is published with
  `--latest=false` and a feed URL of its own. No repo may ever take the old
  name.
- **The protocol lives in two places.** `Shared/PluginProtocol.swift` here,
  and its copy in Voyager. Change both together, and raise
  `protocolVersion` when a change isn't compatible.
- **Voyager reads this checkout.** Debug builds of Voyager take the Restyle
  Plugin's site scripts from a `voyager-plugins` checkout next to Voyager's
  (`../voyager-plugins`).
- **Open source.** Everything here is public. No secrets in the repo: keys
  and tokens live on the release Mac and in the repo's settings.
