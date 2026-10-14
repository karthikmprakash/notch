# Notch — a Dynamic Island for the MacBook notch

[![CI](https://github.com/karthikmprakash/notch/actions/workflows/ci.yml/badge.svg)](https://github.com/karthikmprakash/notch/actions/workflows/ci.yml)
[![Release](https://github.com/karthikmprakash/notch/actions/workflows/release.yml/badge.svg)](https://github.com/karthikmprakash/notch/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/karthikmprakash/notch?sort=semver)](https://github.com/karthikmprakash/notch/releases/latest)

A menu bar app that turns the area around the notch into a Dynamic Island:
resting → compact → peek → expanded, with tiles inside, peeks for apps/charger/
battery/Focus, and a live Claude Code bridge that can approve or deny tool calls
from the notch.

Plain Swift + AppKit/SwiftUI. No Dock icon, no sandbox, no analytics, no accounts.

- **Requires:** macOS 14 or later (developed and checked on macOS 27), Apple Silicon.
- **Persona dashboards are included.** See below for workspace controls and [Roadmap](#roadmap) for the original build steps.

---

## Hover and alignment refinements

The dashboard now uses equal outer gutters and a shared responsive column grid.
The four workspace tabs are centered independently of the pin and settings buttons.
Card content uses a consistent 12-point inset.

Hover detection samples the cursor’s screen position every 50 ms, including when
the panel ignores mouse input. The activation area extends 12 points to either side
and 10 points below the notch, with a 250 ms opening dwell. An 8-point boundary
margin and 300 ms exit grace prevent accidental closure when crossing an edge.
The extra hover area does not intercept clicks. Pending window shrink operations
are cancelled when reopening, and status peeks no longer interrupt an open dashboard.

`swift test` includes layout, hover cancellation/re-entry, and permission protection
checks in addition to workspace persistence and timer tests.

## Persona workspaces

Switch dashboards in the island’s top bar, in the menu bar’s **Workspace** menu,
or in **Settings → Workspace**. Each workspace keeps its own tile visibility,
order, widths, layout, and density across launches. Existing tile preferences
migrate into Everyday.

- **Everyday:** music, weather, messages, and system controls in a wide ribbon.
- **Developer:** live Claude activity, a focus timer, system controls, and
  Terminal / Xcode / VS Code launch buttons in a two-row board.
- **Media:** music and controls above weather and Music / Spotify / QuickTime
  launch buttons.
- **Focus:** timer and next calendar event, with fewer distractions.

Choose **Ribbon** (10 cells per row) or **Board** (6 cells per row), and
**Compact** (82-point tiles) or **Comfortable** (112-point tiles). Right-click a
tile to hide or resize it. Settings lets you reorder tiles and restore only the
current workspace’s defaults. Small tiles have a separate minimal layout.

The focus timer supports **15 / 25 / 50 minutes**, pause and reset, and a
completion peek. Switching workspaces or themes preserves the running session.
Calendar access is requested only when you click **Allow calendar access**.

**⌃⌥Space** opens or closes the island globally. The pin control keeps it open;
unpinning keeps it open until you move away, and a click outside closes a pinned island. App launch buttons are disabled when the app isn’t
installed. The app grid adapts to the available width and lists all discovered
apps, with scrolling.

Settings has Workspace, Integrations, General, and Developer tabs. Developer
shows the latest 30 tool calls in memory (the latest 12 in Settings), with full,
selectable command details. This history is cleared when Notch quits. The
activity tile displays status only; approvals still use the complete permission
card. No hooks are installed automatically.

Validation: `swift test` covers independent workspace persistence, migration,
preset wrapping, and timer duration. Both matte themes and workspace switching
were checked in the native app. White Matte now uses slightly darker tile fills
(`#E9EBEF`) to match the card separation in the reference images.

## Install

```bash
brew install --cask karthikmprakash/tap/notch
```

The fully-qualified name is what makes this work: `brew install --cask notch` only
resolves once this tap is on your machine (Homebrew searches tapped taps, plus the
official `homebrew/cask`). It works bare from the second install on. Getting the
bare name to work for *everyone* means being accepted into `homebrew/cask`, which
requires a notarized, Developer ID-signed build plus enough adoption to clear
Homebrew's notability bar — see [Releases, CI and the tap](#releases-ci-and-the-tap).

That puts `Notch.app` in /Applications and links the same binary as `notch`, so
the Claude Code hook command is just `notch --hook` no matter where Homebrew
lives.

The build is **signed ad-hoc, not notarized**, and macOS is harsh about that: a
quarantined, non-notarized bundle is **deleted** the first time its executable
runs — not merely blocked. That would take the `notch --hook` command down with
it, so the cask strips the download's quarantine flag during install. If the app
ever disappears from /Applications, that is Gatekeeper:

```bash
brew reinstall --cask notch
```

Notarized builds need a Developer ID certificate and an Apple Developer Program
membership. The release workflow already handles them: see
[Releases, CI and the tap](#releases-ci-and-the-tap).

## Build and run

```bash
./build.sh                 # release build -> build/Notch.app
./build.sh debug           # debug build
./build.sh release run     # build, quit the running copy, launch it
open build/Notch.app       # run it any time
```

`build.sh` assembles a real `.app` bundle (Info.plist + `LSUIElement`), and signs
it with your Apple Development identity if you have one, otherwise ad-hoc. The
bundle identifier is always `dev.kmp.notch` — keep it stable, or macOS asks for
permissions again after every build.

## Try it

1. `./build.sh release run`
2. Menu bar → a small pill icon.
3. **Hover the notch** — nothing for 0.25 s, then the island opens. Move away and
   it closes. **Click it** to keep it open; click anywhere else to close.
4. Menu bar icon:
   - **Workspace** → Everyday / Developer / Media / Focus; **Tiles** → show/hide, resize, reset
   - **Theme** → Dark Matte / White Matte, **Weather city…**, **Settings…** (⌘,)
   - **App grid**; **Diagnostics** → test peeks, compact pill, permission card, resting
   - **Start at login**, **Quit Notch** (⌘Q)
5. Play something in Spotify or Apple Music with the music tile on: the first
   time, macOS asks for Automation permission (one prompt per player).

## Releases, CI and the tap

| workflow | what it does |
|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | on every push and PR: `swift build`, `swift test`, assembles the `.app`, verifies the signature **and every privacy-usage key** (a missing one makes TCC abort the app at runtime), times the hook CLI, uploads the bundle as an artifact |
| [`release.yml`](.github/workflows/release.yml) | on a `v*` tag: builds **universal** (arm64 + x86_64), optionally signs with a Developer ID and notarizes, packages `Notch-<version>.zip`, publishes the GitHub release with a sha256, and bumps the Homebrew cask |

Cutting a release:

```bash
# 1. bump Resources/Info.plist (CFBundleShortVersionString + CFBundleVersion)
# 2. commit, then tag — the tag must match Info.plist or the workflow fails
git commit -am "Notch 0.2.0"
git tag -a v0.2.0 -m "Notch 0.2.0"
git push origin main --tags
```

Optional repository secrets (Settings → Secrets and variables → Actions):

| secret | effect when set |
|---|---|
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | base64 of a **Developer ID Application** `.p12`; signs the app properly |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` | notarizes and staples the app, so Gatekeeper stops asking (needs an Apple Developer Program membership) |
| `TAP_TOKEN` | fine-grained PAT with write access to `homebrew-tap`; the release bumps the cask automatically |

Without `TAP_TOKEN`, bump the tap by hand after a release — `tools/update-cask.sh`
writes both the tap copy and a reference copy under `Casks/`:

```bash
SHA=$(curl -sL https://github.com/karthikmprakash/notch/releases/download/v0.2.0/Notch-0.2.0.zip | shasum -a 256 | awk '{print $1}')   # or use the release's sha256.txt
./tools/update-cask.sh 0.2.0 "$SHA" --write --tap-dir ../homebrew-tap --push
```

## What's in it

| Tile | Notes |
|---|---|
| **Music** | Spotify + Apple Music over AppleScript. Never launches a player that is closed. Vinyl artwork, title/artist, progress with elapsed/total, prev/play-pause/next, and the current **synced lyric line from LRCLIB** (free, no key, cached in `~/Library/Application Support/Notch/Lyrics`). In Dark Matte the blurred cover fills the tile; in White Matte the tile stays flat. |
| **Weather** | Open-Meteo (free, no key). Big temperature, still icon, city, high/low. City comes from the settings window; the geocode is cached. Refreshes every 15 min. |
| **Messages** | Latest unread conversations, read-only: name, unread count, last line, time. Opens `chat.db` **read-only** and never writes to it. Needs Full Disk Access, and says so until you grant it. |
| **Quick controls** | Wi-Fi toggle + state, AirDrop settings, dark mode, volume (click = mute, drag = level), brightness (click = cycle, drag = level), and a button that opens the **app grid** inside the island. |
| **Calendar** *(optional)* | Next event via EventKit; asks for permission when you choose Allow calendar access. |
| **Focus timer** *(optional)* | 25 minutes, start/pause/reset. |

**Peeks** (small bubbles under the notch, 2–4 s): app opened/quit with its icon,
charger connected/unplugged, battery at 20 % and 10 %, Do Not Disturb on/off.

## Claude Code, live in the notch

The app is also the hook binary: `Notch --hook` reads the hook JSON on stdin,
tells the app what Claude is doing over a unix socket
(`~/Library/Application Support/Notch/notch.sock`), and for permission requests
waits for your answer and prints the decision back to Claude Code.

- **While Claude works:** the compact pill shows the current step icon (reading,
  editing, running, searching) on the left and a small animated 3×3 grid on the right.
- **When Claude needs permission:** the island opens with the tool, the **whole
  command** (scrollable, never truncated, selectable) and **Allow**/**Deny**.
  Global shortcuts: **⌃⌥A** allow, **⌃⌥D** deny — Carbon hot keys, so no
  Accessibility permission is needed. If you don't answer, nothing is printed and
  Claude Code falls back to its own prompt.
- **When Claude stops:** a peek says "Claude finished · took 2m 14s".

### Add these lines to `~/.claude/settings.json` yourself

The Settings window has a **Copy** button with exactly this, filled in with your own
binary path (use that one if you built from source instead of Homebrew):

```json
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "notch --hook", "timeout": 5 } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "notch --hook", "timeout": 5 } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "notch --hook", "timeout": 5 } ] }
    ],
    "PermissionRequest": [
      { "hooks": [ { "type": "command", "command": "notch --hook", "timeout": 120 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "notch --hook", "timeout": 5 } ] }
    ]
  }
}
```

Merge the `hooks` object into your existing file — don't replace it. Notes:

- `PermissionRequest` is what makes Allow/Deny actually decide anything. If your
  Claude Code version doesn't support it yet, delete that block: the card still
  appears (as information), and Claude asks in the terminal as usual.
- The `PreToolUse` hook costs about **10–20 ms** per tool call (measured).
- The hook never blocks Claude when the app isn't running: it exits silently.

## Permissions

Nothing is requested at launch. Each permission is asked when the feature that
needs it is first used:

| Permission | Asked when | Why |
|---|---|---|
| Automation (Apple Events) → Spotify / Music | first music interaction | read the current track, send play/pause. One prompt per player, only for the player you use |
| Calendar (EventKit full access) | Allow calendar access clicked | next event |
| Full Disk Access | messages tile switched on | read `~/Library/Messages/chat.db`. macOS can't prompt: the tile tells you where to grant it |
| Focus status (`INFocusStatusCenter`) | first launch | DND peeks. Without it the app says "Focus status not granted" instead of guessing. Needs `NSFocusStatusUsageDescription`, which is in Info.plist — without that key macOS **kills the app** |
| Bluetooth | not used | no tile reads Bluetooth state; the usage description is in Info.plist anyway |
| Accessibility | **never** | Allow/Deny hot keys use Carbon, not event taps |

Login at start is an `SMAppService` toggle (System Settings → General → Login
Items), off until you turn it on.

## Privacy

- Only two network requests exist: **Open-Meteo** (the city you type) and
  **LRCLIB** (artist/title/duration of the song playing, for lyrics).
- Spotify's cover art is the third, optional one: Spotify's AppleScript API only
  exposes artwork as a URL, so that image is fetched and cached locally. Turn it
  off in Settings → *Fetch Spotify cover art* and you get a neutral vinyl instead.
- Apple Music artwork is read from the player locally.
- Everything else is local: no accounts, no analytics, no telemetry. The only
  local server is the unix socket the Claude hook talks to.

## Where things are

| file | what |
|---|---|
| `Sources/Notch/NotchApp.swift` | entry point, and the `--hook` CLI switch |
| `Sources/Notch/AppDelegate.swift` | menu bar item and menu |
| `Sources/Notch/IslandController.swift` | panel, window geometry, pointer gate, clicks |
| `Sources/Notch/IslandModel.swift` | state machine, layout, service wiring |
| `Sources/Notch/IslandView.swift` | the SwiftUI island |
| `Sources/Notch/IslandShape.swift` | island + notch band shapes |
| `Sources/Notch/Theme.swift`, `Settings.swift`, `AppPaths.swift` | palettes, settings, paths, small helpers |
| `Sources/Notch/Music.swift` | Spotify/Music AppleScript + LRCLIB lyrics |
| `Sources/Notch/Weather.swift`, `Messages.swift`, `SystemControls*.swift`, `Calendar.swift` | the other tiles' back ends |
| `Sources/Notch/Tiles.swift` | the tile views |
| `Sources/Notch/AppGrid.swift` | app grid + permission card |
| `Sources/Notch/ClaudeBridge.swift`, `UnixSocket.swift`, `HookCLI.swift` | the Claude Code bridge |
| `Sources/Notch/PeekCenter.swift` | app/power/Focus peeks |
| `Sources/Notch/SettingsWindow.swift` | the settings window |
| `DESIGN.md` | the layout spec measured from your mockups |
| `design/` | the two mockups, kept for step-by-step comparison |

## Traps this app already handles

- `NSPanel.isFloatingPanel = true` **resets the window level** to 3, silently
  putting the island behind the menu bar. It's set before `level`, and the level
  (26) is asserted with `CGWindowListCopyWindowInfo`.
- AppKit's default `constrainFrameRect` keeps windows out of the menu bar strip,
  which pushed the island 32 pt down. Overridden in `IslandPanel`.
- Click-through: the panel is exactly as wide as the island and sets
  `ignoresMouseEvents` unless the pointer is inside it, so it never swallows
  clicks meant for the menu bar or an app below. A global mouse-moved monitor
  opens that gate; the panel's own tracking area takes over once inside.
- `@Published` notifies on **willSet** and SwiftUI reads the body inside that
  notification, so a plain `state = new` renders the *old* value and never
  re-reads. Every state change sends `objectWillChange` again after the write.
- Child services (weather, music, …) publish on their own objects; the model
  forwards those changes, otherwise the tiles would never update.
- Tiles are clipped to their own rounded rectangle, and the blurred music cover
  is blurred inside the tile's frame and clipped after, so no blur spills out.
- `INFocusStatusCenter` needs `NSFocusStatusUsageDescription` in Info.plist. A
  missing key doesn't just fail — TCC aborts the process.

## Dev hooks

Environment variables, ignored when unset:

```bash
NOTCH_DEBUG_STATE=expanded|compact|peek|resting|grid|permission   # start in that state
NOTCH_DEBUG_WORKSPACE=everyday|developer|media|focus
NOTCH_DEBUG_THEME=dark|white        # force a theme (not saved)
NOTCH_DEBUG_CITY=Lisbon             # override the weather city
NOTCH_DEBUG_DUMP=1                  # geometry dump + trace, also written to
                                    # ~/Library/Application Support/Notch/debug.log
NOTCH_DEBUG_FETCH=1                 # refresh weather + messages at launch
NOTCH_DEBUG_AUTOALLOW=1             # answer permission cards automatically
NOTCH_DEBUG_SETTINGS=1              # open the settings window at launch
```

Launch them through LaunchServices so the app keeps its bundle identity:

```bash
open -n build/Notch.app --env NOTCH_DEBUG_STATE=expanded --env NOTCH_DEBUG_DUMP=1
```

(The same binary with `--hook` runs as the Claude Code hook.)

## Remove it completely

```bash
pkill -x Notch                                     # quit
defaults delete dev.kmp.notch                      # preferences
rm -rf ~/Library/Application\ Support/Notch        # lyrics + artwork caches, socket, debug log
rm -rf build/Notch.app                             # the app bundle
```
Turn off *Start at login* in the menu first (or remove it in System Settings →
General → Login Items). No launch agents, no helpers, no kernel extensions.

## Roadmap

1. **done** — island window: notch geometry, resting/compact/peek/expanded, springs, shadow, themes, pointer gate, menu.
2. **done** — theme + settings persistence.
3. **done** — tile system: 1/2/3-cell tiles, show/hide, reorder, per-tile clipping.
4. **done** — music tile with Spotify/Music and synced LRCLIB lyrics.
5. **done** — weather, messages, quick controls, app grid, calendar, focus timer.
6. **done** — peeks: apps, charger, battery 20/10 %, Focus.
7. **done** — Claude Code bridge: hooks → socket, step indicator, permission card with Allow/Deny + ⌃⌥A/⌃⌥D, "Done" with duration.
8. **done** — settings window, launch at login, CPU pass, this README.

## Known limits (say them, don't fake them)

- **AirDrop**: macOS removed the scriptable AirDrop visibility preference on your
  version (`com.apple.NetworkBrowser` no longer exists) and Control Center's
  AirDrop picker has no public API. The button opens the AirDrop & Handoff
  settings pane instead of pretending to toggle.
- **Brightness**: no public API, so it uses the private `DisplayServices`
  framework — internal display only. If the symbols ever vanish the control shows
  as unavailable instead of silently doing nothing.
- **Wi-Fi toggle**: `networksetup`; if macOS refuses, it retries once through an
  administrator prompt and reports the error in the log rather than lying.
- **Dark mode**: needs Automation permission for System Events (macOS has no
  other public route).
- **Messages**: without Full Disk Access the tile shows the exact path to grant it.

### Compact notch navigation

Workspace tabs now sit in two wings beside the hardware cutout. Their positions
stay fixed across Board and Ribbon layouts. Compact density is the default
(existing workspace compositions are preserved); Comfortable remains available
in Settings. Apps, pin, and customization live in the small bottom utility row.
Click the timer value to select its duration even in Compact mode.

Workspace changes are immediate. The panel uses a stable transparent backing
window, removing the competing AppKit resize and SwiftUI layout animations.
Only the visible island accepts mouse input; the rest remains click-through.
Regression tests cover workspace changes, pointer behavior, and profile migration.
