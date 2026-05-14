# TailOps Mac

Pure Swift macOS platform slice for a low-impact TailOps menu-bar app plus WidgetKit widget. This path does not use the Node server.

## Shape

- `Sources/TailOpsCore`: testable Swift package core for parsing `tailscale status --json`, host status, summaries, and host actions.
- `Sources/TailOpsCoreValidation`: executable validation runner for this environment, because the installed command-line Swift toolchain does not expose `XCTest` or Swift `Testing`.
- `App`: SwiftUI menu-bar app source. It owns refresh, runs `tailscale status --json`, gathers ping diagnostics for online peers, writes a cached snapshot, and opens SSH/HTTP/Taildrop actions.
- `Widget`: WidgetKit source. It reads the cached snapshot and shows the most useful reachable hosts first.
- `Shared`: source files that should be included in both the app target and the widget extension target.

## Xcode Target Setup

The repository now includes a minimal Xcode project:

```text
TailOpsMac.xcodeproj
```

Open it in Xcode and use the `TailOpsMac` scheme. The scheme builds:

- `TailOpsMac`: menu-bar app.
- `TailOpsWidget`: WidgetKit extension embedded in the app.
- Local Swift package products: `TailOpsCore`, `TailOpsShared`, and `TailOpsIntents`.

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

- `App/TailOpsMenuView.swift` for the menu-bar panel.
- `Widget/TailOpsWidget.swift` for small and medium desktop widgets.

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

`hostID` can match the host ID, display name, MagicDNS name, or Tailscale IP. A sample file lives at `config/tailops-actions.sample.json`.

## Taildrop

TailOps currently exposes Taildrop in two places:

- The menu-bar host rows accept file drops and send them with `tailscale file cp`.
- Finder can show a `Send with TailOps` Service for selected files. The service opens a Taildrop destination picker backed by `tailscale file cp --targets`.

Wishlist: a temporary Finder-based `TailOps Drop Zone` could create one folder per available Taildrop target, then send files dropped into a device folder. A real mounted volume or File Provider extension remains possible later, but the watched-folder design is smaller and more reliable for a local utility.

## Liquid Glass And Widget Rendering

The widget uses WidgetKit container backgrounds and marks the background as removable so macOS can apply clear, tinted, and Liquid Glass appearances. It also uses `widgetRenderingMode` and `widgetAccentable(_:)` to keep primary content legible when the system renders the widget in accented or vibrant modes.

The widget supports small, medium, and large families. It is not freely resizable like a normal app window; macOS only allows the widget families the extension declares. The medium widget intentionally prioritizes online/warning hosts and collapses extra offline devices into a count so the layout stays readable.

WidgetKit does not expose arbitrary hover-only controls. Instead of a gear-first design, the next plan uses a widget-to-app entry point: small widgets can open TailOps when tapped, medium widgets can open TailOps from background/empty space, and large widgets can expose a low-prominence app/settings affordance without competing with refresh or host action buttons.

## Runtime Impact

The widget itself does not ping. It reloads the cached snapshot from the shared App Group on its WidgetKit timeline, currently every five minutes.

The app does the active refresh work. It refreshes on launch, when the menu panel appears, and when the refresh button is pressed. Each refresh currently runs:

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

Removing the widget therefore leaves no backend to kill. Quitting the menu-bar app stops refresh work.

## Next Implementation Plan

The next control-surface plan lives at:

```text
docs/superpowers/plans/2026-05-14-tailops-macos-control-surface.md
```

Current progress:

- Native Swift menu-bar app and WidgetKit widget are working.
- App and widget share state through the team-prefixed App Group.
- Widget supports small, medium, and large families.
- Widget shows reachable hosts first and collapses extra offline hosts.
- Menu-bar rows support refresh, quick actions, ping sparkline context, and Taildrop file drops.
- Finder Service can send selected files through Taildrop.

The planned order is:

1. Shared app preferences.
2. Launch at login.
3. Menu bar icon visibility with a widget-to-app recovery path.
4. Widget-to-app entry point instead of a hover-only gear.
5. Latest ping route/latency text in widget rows.

Wishlist: TailOps Drop Zone.
