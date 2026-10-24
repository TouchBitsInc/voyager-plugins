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
- **Tags.** The Media Plugin's releases are tagged by plain version (`0.2.3`),
  as they always were; every other plugin's carry its name (`restyle-0.1`),
  and its workflow reads only its own tags, as the Media one reads only
  plain ones.
- **The protocol lives in two places.** `Shared/PluginProtocol.swift` here,
  and its copy in Voyager. Change both together, and raise
  `protocolVersion` when a change isn't compatible.
- **Installed, always.** Voyager only uses plugins installed in
  /Applications and signed by the team, Debug builds included. To run Voyager
  against this checkout, `Scripts/install-dev.sh` builds every plugin
  team-signed and installs it, keeping released copies aside
  (`--restore` puts them back).
- **Open source.** Everything here is public. No secrets in the repo: keys
  and tokens live on the release Mac and in the repo's settings.
