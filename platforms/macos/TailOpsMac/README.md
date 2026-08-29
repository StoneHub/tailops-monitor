# TailOps Mac

Pure Swift macOS platform slice for a low-impact TailOps WidgetKit desktop widget backed by a hidden native host app. This path does not use the Node server.

## Shape

- `Sources/TailOpsCore`: testable Swift package core for parsing `tailscale status --json`, host status, summaries, and host actions.
- `Tests/TailOpsCoreTests`: focused XCTest regressions for parsing, widget prioritization, refresh health, and shared-store persistence.
- `Sources/TailOpsCoreValidation`: broader executable compatibility validation retained alongside XCTest.
- `App`: SwiftUI host app source. It owns refresh, runs `tailscale status --json`, gathers ping diagnostics for online peers, writes a cached snapshot, opens settings, and provides Finder Services.
- `Widget`: WidgetKit source. It reads the cached snapshot and shows the most useful reachable hosts first.
- `Shared`: source files that should be included in both the app target and the widget extension target.

## Xcode Target Setup

The repository now includes a minimal Xcode project:

```text
TailOpsMac.xcodeproj
```

Open it in Xcode and use the `TailOpsMac` scheme. The scheme builds:

- `TailOps`: hidden host app product built from the `TailOpsMac` target.
- `TailOpsWidget`: WidgetKit extension embedded in the app.
- Local Swift package products: `TailOpsCore`, `TailOpsShared`, and `TailOpsIntents`.

The target and scheme keep the development name `TailOpsMac`, but the installed app bundle is branded as `TailOps.app` and the widget picker label is `TailOps`.

The targets are configured with a team-prefixed App Group at signing time:

```text
$(TeamIdentifierPrefix)group.dev.tailops.monitor
```

At runtime, a locally signed build resolves this to a value like `N6GPP46885.group.dev.tailops.monitor`. `SharedSnapshotStore` reads the signed App Group entitlement and falls back to app support storage for unsigned command-line verification.

For local command-line compile verification without signing:

```bash
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

That command is compile-only. It does not validate the signed App Group or live WidgetKit behavior.

For normal Xcode Run, select your Apple Development team for both the app and widget targets so Xcode can sign the App Group entitlement. The checked-in project intentionally leaves `DEVELOPMENT_TEAM` blank so a fresh clone is not pinned to another developer's team.

If rebuilding this project manually, the intended target layout is:

1. macOS App target named `TailOpsMac`.
2. Widget Extension target named `TailOpsWidget`.
3. Add this directory as a local Swift package and link `TailOpsCore` into both targets.
4. Add `App/*.swift` and `Shared/*.swift` to the app target.
5. Add `Widget/*.swift` and `Shared/*.swift` to the widget extension target.
6. Enable App Groups for both targets with `$(TeamIdentifierPrefix)group.dev.tailops.monitor`.

The app group identifier lives in `Shared/SharedSnapshotStore.swift`.

## Visual Work

Open these files in Xcode and use the canvas previews:

- `App/TailOpsSettingsView.swift` for custom dashboard/action settings.
- `Widget/TailOpsWidget.swift` for medium, large, and extra-large desktop widgets.

The preview data lives in `Shared/PreviewFixtures.swift`, so visual edits do not need live Tailscale state.

## Custom Links

Dashboard and shortcut buttons use `TailnetActionConfiguration`, which is persisted as:

```text
tailops-actions.json
```

inside the shared app group container, or the fallback `Application Support/TailOpsMac` directory when the app group is not available. The format is:

```json
{
  "hostActions": [
    {
      "hostID": "openclaw",
      "actions": [
        { "emoji": "🖥", "title": "SSH", "kind": "ssh", "target": "openclaw.tailnet.ts.net" },
        { "emoji": "🧭", "title": "Dash", "kind": "url", "target": "http://openclaw.tailnet.ts.net:8080" },
        { "emoji": "📋", "title": "IP", "kind": "copy", "target": "100.64.0.2" }
      ]
    }
  ]
}
```

`hostID` can match the host ID, display name, MagicDNS name, or Tailscale IP. A sample file lives at `config/tailops-actions.sample.json`. The settings window also includes a `+ Host` control so custom button rows can be created even when the target device is not already represented in the imported snapshot.

Custom actions extend the generated per-host defaults instead of replacing them. For example, adding a dashboard link keeps TailOps' generated SSH and Copy IP buttons unless the custom action targets the same SSH host or copied address. Large and extra-large grid widgets show action emoji plus short labels so custom buttons are recognizable on the desktop; compact row widgets keep icon-only chips to preserve space.

## Widget-First App

TailOps no longer shows a menu-bar icon by default. The app launches as an `LSUIElement` helper, refreshes the shared widget snapshot, and stays out of the menu bar. The widget gear is a `Link` to `tailops://settings`. Opening the deep link brings the app forward and shows the floating settings window on the active Space so custom buttons stay reachable from widget-only mode.

The host registers the `tailops://settings` URL scheme as the supported widget-to-app settings path. The visible settings gear uses that deep link. Other widget actions use App Intents for one-shot work or deep-link back into the containing app when richer UI is needed.

## Taildrop

TailOps currently exposes Taildrop through Finder:

- Finder can show a `Send with TailOps` Service for selected files. The service opens a Taildrop destination picker backed by `tailscale file cp --targets`.

The older `TailOpsMenuView` still contains row-drop code, but the current app scene does not mount that view. Treat the Finder Service as the reachable Taildrop entry point.

Cross-account file-send path: TailOps includes a Wormhole send/receive window backed by paired contacts and deterministic transfer codes. Use Magic Wormhole for simple prompt files, Markdown, rich text, and images when the paired user can click receive. Keep Taildrop for same-account devices only. Use SFTP or a future token-authenticated TailOps Inbox receiver only if unattended drops become necessary.

TailOps also runs a bounded pending-transfer signal listener on TCP `39117`. A signed V1 notice contains only sender/file metadata and expiration—never file data or the Wormhole transfer code. Secrets remain in the device-local Keychain, routing uses an exact saved Tailnet node ID, and the receiver enforces constant-time HMAC verification, expiry and replay checks, connection/request limits, and a matching JSON acknowledgement. Both Macs must run the hardened V1 protocol.

Plan: `../../../docs/superpowers/plans/2026-07-03-tailops-file-send-upgrade.html`.

Magic Wormhole is not bundled in TailOps yet. For the first local trials, install it separately:

```bash
brew install magic-wormhole
```

Bundling is possible because Magic Wormhole is MIT-licensed, but the reference CLI is Python-based and depends on native crypto libraries. A bundled version should be a separately signed helper under `Contents/Helpers` or `Contents/Resources`, with per-architecture build artifacts and a clear update process. Do not block the first TailOps Wormhole UI on that packaging work.

If `wormhole` is missing, open `tailops://wormhole` or the widget Wormhole button and TailOps will show the setup gate with the Homebrew install command. Once installed, the same window can save a shared pairing, pick a file to send, or receive into `~/Desktop/TailOps Inbox`.

## Liquid Glass And Widget Rendering

The widget uses WidgetKit container backgrounds and marks the background as removable so macOS can apply clear, tinted, and Liquid Glass appearances. It also opts the widget surface, host tiles, status dots, and action chips out of accent tinting with `widgetAccentable(false)` so passive online/offline status remains colorful when the desktop widget is visible but not focused.

The widget supports medium, large, and extra-large families. It is not freely resizable like a normal app window; macOS only allows the widget families the extension declares and may delay showing new families until WidgetKit reloads the updated extension metadata. TailOps keeps the medium widget usable as a fallback by showing two prioritized online/warning hosts, collapsing extra offline devices into a count, and moving controls into the header instead of a bottom footer. Large and extra-large families switch to a status grid: large shows up to six devices and extra-large shows up to nine devices. Grid tiles keep feature parity with row tiles by showing status, address, latency when available, and up to three quick-action buttons.

When changing supported families, widget metadata, or visible widget layout, bump `CURRENT_PROJECT_VERSION` for both app and widget targets before installing. WidgetKit and PlugInKit cache extension metadata and live extension processes aggressively, so a successful `ditto` to `/Applications` is not enough proof that the desktop widget has reloaded.

The reliable local refresh loop after a widget build starts by resolving the exact app product from the current build:

```bash
BUILD_SETTINGS="$(mktemp)"
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug -showBuildSettings > "$BUILD_SETTINGS"
TARGET_BUILD_DIR="$(awk -F'= ' '/ TARGET_BUILD_DIR = / {print $2; exit}' "$BUILD_SETTINGS")"
FULL_PRODUCT_NAME="$(awk -F'= ' '/ FULL_PRODUCT_NAME = / {print $2; exit}' "$BUILD_SETTINGS")"
BUILT_APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
test -d "$BUILT_APP" && echo "$BUILT_APP"
```

Then install and refresh from that resolved product path only:

```bash
ditto "$BUILT_APP" /Applications/TailOps.app
pluginkit -r "$BUILT_APP/Contents/PlugIns/TailOpsWidget.appex"
rm -rf "$BUILT_APP" "$TARGET_BUILD_DIR/TailOpsWidget.appex"
pluginkit -a /Applications/TailOps.app/Contents/PlugIns/TailOpsWidget.appex
lsregister -f -R -trusted /Applications/TailOps.app
killall TailOps TailOpsWidget NotificationCenter ControlCenter Dock
open /Applications/TailOps.app
pluginkit -m -i dev.tailops.monitor.widget -D -vvv
```

The final `pluginkit` check should show exactly one `dev.tailops.monitor.widget`, and its path should be `/Applications/TailOps.app/Contents/PlugIns/TailOpsWidget.appex`. If a DerivedData widget remains registered or a stale `TailOpsWidget` process is still running, the visible desktop widget can keep rendering old UI even though the installed app bundle is current.

The app target and widget extension both include `Xcode/Assets.xcassets` and use the shared `AppIcon` asset so Finder, Launch Services, and the widget picker display the same TailOps icon.

WidgetKit does not expose arbitrary hover-only controls. TailOps uses always-visible, low-prominence header controls for Tailscale, refresh, last-update time, and settings so settings remain recoverable even with no menu-bar icon and the widget avoids bottom-edge clipping.

Host SSH chips run `OpenSSHInTerminalIntent`, which opens `ssh://<host>` explicitly with Terminal. Plain widget `Link` dispatch for `ssh://` was not reliable enough on macOS.

## Runtime impact

The widget itself does not ping. It reloads the cached snapshot from the shared App Group and asks WidgetKit for another timeline after 15 minutes.

The app does the active refresh work. It refreshes on launch, once per hour while the app remains alive, and when the refresh button is pressed. Each refresh currently runs:

```text
tailscale status --json
tailscale ping --c 6 --timeout 1500ms --until-direct=false <online-peer>
```

Only online peers are pinged, and ping diagnostics are throttled to at most once per hour. With two online peers, one ping refresh means twelve ping samples total. Refreshes inside the one-hour window keep cached ping diagnostics instead of running another ping burst.

## Sandbox note

The app currently reads Tailscale through:

```text
/usr/local/bin/tailscale status --json
/Applications/Tailscale.app/Contents/MacOS/tailscale status --json
/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json
/opt/homebrew/bin/tailscale status --json
/usr/bin/tailscale status --json
```

That is the simplest and lowest-risk first step for a local developer utility. A sandboxed App Store build should not rely on launching arbitrary command-line tools. For that path, replace `ProcessTailscaleStatusProvider` with an XPC helper or a signed privileged helper.

## Verify core

```bash
swift test
swift run TailOpsCoreValidation
```

The XCTest target covers focused regressions while the validation executable keeps the broader legacy checks. Expected validation-runner output:

```text
TailOpsCoreValidation passed
```

## Lifecycle

The widget is intentionally passive. It does not own a backend and does not keep a process alive. The app refreshes state and writes a snapshot; the widget reads that snapshot on its normal WidgetKit timeline.

Removing the widget leaves no backend to kill. Quitting the hidden host app stops refresh work.

## Current state

- Native Swift hidden host app and WidgetKit widget are working.
- App and widget share state through the team-prefixed App Group.
- Widget supports medium, large, and extra-large families.
- Widget shows reachable hosts first, then offline hosts when space remains, and collapses extra offline hosts.
- Widget rows show latest and average latency when diagnostics are cached. Grid tiles show latest latency.
- Widget quick actions support SSH, dashboard URLs, and copy actions.
- Widget settings gear opens the hidden host app through `tailops://settings`.
- Finder Service can send selected files through Taildrop.
- Local signed installs are branded as `/Applications/TailOps.app`; `TailOpsMac.app` is the old development product name.

Current follow-up work:

1. Manually verify the widget gear in the live desktop widget after each install.
2. Improve dashboard action presets and common-port helpers in settings.
3. Add QR setup and explicit cancellation to the Wormhole flow.
4. Exercise Wormhole send and receive between two signed, current Mac installs.
5. Keep menu-bar UI as optional future scope only if the widget cannot cover a workflow.

The completed native control-surface plan is archived at `../../../docs/archive/2026-05/2026-05-14-tailops-macos-control-surface.md`. Active Wormhole follow-up remains in `../../../docs/superpowers/plans/2026-07-03-tailops-file-send-upgrade.html`.

Wishlist: TailOps Drop Zone.
