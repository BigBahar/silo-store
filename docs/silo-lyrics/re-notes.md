# Silo Lyrics: research notes

Status as of 2026-11-12. This is a clean-room build: behaviour was taken from public information, no code or assets from Dynamic Lyrics.

## What "Dynamic Lyrics" is
- Closed-source App Store app, bundle `com.dynamiclyrics.app`, by aSynch1889 (iOS / iPadOS / macOS).
- Public feature list (from `aSynch1889/DynamicLyrics-legal`): real-time bilingual lyrics, translation, Live Activities, widgets, floating window, optional Shazam recognition.
- No source exists to fork. `X1er0/DynamicLyrics-iOS` is a README-only repo.
- Its IPA is FairPlay-encrypted; analysing the binary needs a decrypted IPA, which we do not have.

## rea (morluto/rea)
- MIT-licensed MCP for reverse engineering binaries, JS/Electron apps and websites (`npx rea-agents setup`).
- **Not installed yet.** Setup downloads from npm and edits the agent's MCP config, which I did not do unattended. Run it when you are back, then point it at the Spotify web player (open.spotify.com) lyrics view to extract line timing, scroll and colour behaviour.
- Until then the lyrics view follows the commonly known Spotify behaviour: current line large and bright, neighbours dimmed, smooth scroll to keep the current line near the top third.

## How Silo Lyrics works
| Piece | Choice |
| --- | --- |
| Now playing | Spotify Web API `GET /v1/me/player/currently-playing`, polled every 3 s; position interpolated locally from `progress_ms` |
| Auth | Authorization Code + PKCE (`ASWebAuthenticationSession`), tokens in Keychain, no client secret |
| Lyrics | LRCLIB `/api/get`, fallback `/api/search` (synced within 3 s of the track duration) |
| Display | Full-screen view plus ActivityKit Live Activity (Dynamic Island compact/expanded/minimal, Lock Screen) |

## Known limits
- **Live Activity updates only run while the app process is alive.** iOS suspends the app shortly after it leaves the foreground, so island lines stop updating. Reliable background updates need an APNs push-to-update server (Live Activity push tokens) polling Spotify server-side; not built. Plain-text fallback: the island shows the last line.
- Spotify Development Mode apps need the owner to have Premium and are limited to a few allowed users.
- `NSSupportsLiveActivitiesFrequentUpdates` is set, but the system can still throttle updates.
- iOS cannot replace its own app; "Update now" opens `sidestore://install?url=…` and SideStore does the install.
- Nothing here has been compiled or run: this machine has no Swift/Xcode. Only the LRC parser logic was verified (Node port, run against live LRCLIB data).
