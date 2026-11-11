# Silo Lyrics

Synced Spotify lyrics on iPhone, including a Live Activity in the Dynamic Island. Part of the Silo apps, distributed through Silo Store.

## Build (on a Mac)
1. Create a Spotify app at <https://developer.spotify.com/dashboard> (the owner needs Premium for Development Mode). Add redirect URI `silolyrics://callback`.
2. `cp Config.xcconfig.sample Config.xcconfig` and paste the Client ID.
3. `brew install xcodegen && xcodegen`, open `SiloLyrics.xcodeproj`, run on a device (Live Activities don't show in every simulator setup).
4. Core logic tests: `swift test` in this folder (macOS).

## Layout
- `Sources/SiloLyricsKit` – LRC parser, sync engine, LRCLIB client, Spotify PKCE auth and player client, shared Live Activity attributes
- `App/` – SwiftUI app (lyrics view, settings, updater)
- `Widget/` – Live Activity / Dynamic Island
- `scripts/check-lrc.mjs` – Linux check of the parser against live LRCLIB data

Research and limits: `../docs/silo-lyrics/re-notes.md`.
