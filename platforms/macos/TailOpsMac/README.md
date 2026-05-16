# TailOps Mac

Pure Swift macOS platform slice for a low-impact TailOps WidgetKit desktop widget backed by a hidden native host app. This path does not use the Node server.

## Shape

- `Sources/TailOpsCore`: testable Swift package core for parsing `tailscale status --json`, host status, summaries, and host actions.
- `Sources/TailOpsCoreValidation`: executable validation runner for this environment, because the installed command-line Swift toolchain does not expose `XCTest` or Swift `Testing`.
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

At runtime, a locally signed build resolves this to a value like `N6GPP46885.group.dev.tailops.monitor`. `SharedSnapshotStore` reads the signed App Group entitlement first and keeps a legacy fallback for older local builds that wrote to `group.dev.tailops.monitor`.

For local command-line verification without signing:

```bash
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

For normal Xcode Run, select your Apple Development team for the app and widget targets so Xcode can sign the App Group entitlement.

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
- `Widget/TailOpsWidget.swift` for small, medium, large, and extra-large desktop widgets.

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

## Widget-First App

TailOps no longer shows a menu-bar icon by default. The app launches as an `LSUIElement` helper, refreshes the shared widget snapshot, and stays out of the menu bar. The widget gear opens `tailops://settings`, bringing the app forward and showing the floating settings window on the active Space so custom buttons stay reachable from widget-only mode.

The host registers the `tailops://settings` URL scheme as the supported widget-to-app settings path. Widget actions remain intentionally small: they either invoke App Intents for one-shot actions or deep-link back into the containing app when richer UI is needed.

## Taildrop

TailOps currently exposes Taildrop through Finder:

- Finder can show a `Send with TailOps` Service for selected files. The service opens a Taildrop destination picker backed by `tailscale file cp --targets`.

Wishlist: a temporary Finder-based `TailOps Drop Zone` could create one folder per available Taildrop target, then send files dropped into a device folder. A real mounted volume or File Provider extension remains possible later, but the watched-folder design is smaller and more reliable for a local utility.

## Liquid Glass And Widget Rendering

The widget uses WidgetKit container backgrounds and marks the background as removable so macOS can apply clear, tinted, and Liquid Glass appearances. It also uses `widgetRenderingMode` and `widgetAccentable(_:)` to keep primary content legible when the system renders the widget in accented or vibrant modes.

The widget supports medium, large, and extra-large families. It is not freely resizable like a normal app window; macOS only allows the widget families the extension declares and may delay showing new families until WidgetKit reloads the updated extension metadata. TailOps keeps the medium widget usable as a fallback by showing two prioritized online/warning hosts, collapsing extra offline devices into a count, and moving controls into the header instead of a bottom footer. Large and extra-large families switch to a status grid: large shows up to six devices and extra-large shows up to nine devices. Grid tiles keep feature parity with row tiles by showing status, address, latency when available, and up to three quick-action buttons.

When changing supported families or widget metadata, bump `CURRENT_PROJECT_VERSION` for both app and widget targets before installing. WidgetKit and PlugInKit cache extension metadata aggressively; removing stale DerivedData app/widget bundles and re-registering `/Applications/TailOps.app` can be required when the widget picker keeps showing an older `TailOpsMac` entry.

The app target and widget extension both include `Xcode/Assets.xcassets` and use the shared `AppIcon` asset so Finder, Launch Services, and the widget picker display the same TailOps icon.

WidgetKit does not expose arbitrary hover-only controls. TailOps uses always-visible, low-prominence header controls for Tailscale, refresh, last-update time, and settings so settings remain recoverable even with no menu-bar icon and the widget avoids bottom-edge clipping.

Host SSH chips run `OpenSSHInTerminalIntent`, which opens `ssh://<host>` explicitly with Terminal. Plain widget `Link` dispatch for `ssh://` was not reliable enough on macOS.

## Runtime Impact

The widget itself does not ping. It reloads the cached snapshot from the shared App Group on its WidgetKit timeline, currently every five minutes.

The app does the active refresh work. It refreshes on launch and when the refresh button is pressed. Each refresh currently runs:

```text
tailscale status --json
tailscale ping --c 6 --timeout 1500ms --until-direct=false <online-peer>
```

Only online peers are pinged. With two online peers, one refresh means twelve ping samples total. Idle impact is therefore near zero; active impact is proportional to the number of online peers. Ping rate controls are intentionally deferred for now.

## Sandbox Note

The app currently reads Tailscale through:

```text
/usr/bin/env tailscale status --json
```

That is the simplest and lowest-risk first step for a local developer utility. A sandboxed App Store build should not rely on launching arbitrary command-line tools. For that path, replace `ProcessTailscaleStatusProvider` with an XPC helper or a signed privileged helper.

## Verify Core

```bash
swift run TailOpsCoreValidation
```

Expected output:

```text
TailOpsCoreValidation passed
```

## Lifecycle

The widget is intentionally passive. It does not own a backend and does not keep a process alive. The app refreshes state and writes a snapshot; the widget reads that snapshot on its normal WidgetKit timeline.

Removing the widget leaves no backend to kill. Quitting the hidden host app stops refresh work.

## Next Implementation Plan

The next control-surface plan lives at:

```text
docs/superpowers/plans/2026-05-14-tailops-macos-control-surface.md
```

Current progress:

- Native Swift hidden host app and WidgetKit widget are working.
- App and widget share state through the team-prefixed App Group.
- Widget supports small, medium, large, and extra-large families.
- Widget shows reachable hosts first, then offline hosts when space remains, and collapses extra offline hosts.
- Widget rows show latest ping route, latest latency, average latency, and sample count when diagnostics are cached.
- Widget quick actions support SSH, dashboard URLs, and copy actions.
- Widget settings gear opens the hidden host app settings window through an App Intent.
- Finder Service can send selected files through Taildrop.
- Local signed installs are branded as `/Applications/TailOps.app`; `TailOpsMac.app` is the old development product name.

The planned order is:

1. Manually verify the widget gear in the live desktop widget after each install.
2. Improve dashboard action presets and common-port helpers in settings.
3. Continue Finder Taildrop destination and transfer feedback polish.
4. Keep menu-bar UI as optional future scope only if the widget cannot cover a workflow.

Wishlist: TailOps Drop Zone.
