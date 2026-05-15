# TailOps Monitor

TailOps Monitor is a low-impact macOS tailnet companion for Tailscale users. The primary experience is now a WidgetKit desktop widget backed by a hidden Swift host app. The widget keeps useful tailnet shortcuts one click away: SSH, local dashboards, copied IPs, and quick reachability status.

The older browser dashboard is still included as a full-screen visualization and telemetry playground, but the macOS widget suite is now the main product path.

## What It Does

- Shows Tailscale hosts from `tailscale status --json`.
- Adds a desktop WidgetKit widget with host rows, ping context, and custom emoji action buttons.
- Uses a hidden native host app for refresh, settings, App Group sharing, and Finder Services.
- Adds passive ping context for online peers when the host app refreshes, then exposes the cached result in the widget.
- Adds Taildrop shortcuts through menu-row file drops and a Finder Service.
- Lets you configure custom actions for each host:
  - `ssh`: opens `ssh://host`.
  - `url`: opens HTTP dashboards, admin pages, Home Assistant, OpenClaw, router UIs, logs, and other web tools.
  - `copy`: copies an IP address or other configured value through an App Intent.
- Shares widget state through an App Group instead of running a Node backend.
- Keeps the widget passive: removing the widget leaves no backend process to kill.

## Project Layout

```text
platforms/macos/TailOpsMac/       Swift macOS app, widget, core package, and Xcode project
src/                              Browser dashboard server and telemetry modules
tests/                            Node test suite for browser/server telemetry behavior
data/agents.sample.json           Sample AI agent phonebook data
docs/assets/                      Visual references and dashboard captures
```

## macOS Quick Start

Requirements:

- macOS with Xcode installed.
- Tailscale CLI available as `tailscale`.
- An Apple ID in Xcode for local development signing.

Open the real app/widget project:

```bash
open platforms/macos/TailOpsMac/TailOpsMac.xcodeproj
```

In Xcode:

1. Select the `TailOpsMac` scheme.
2. Select target `TailOpsMac`, open **Signing & Capabilities**, enable **Automatically manage signing**, and choose your team.
3. Repeat for target `TailOpsWidget`.
4. Run the `TailOpsMac` scheme. The built app product is branded as `TailOps.app`.
5. Open macOS **Edit Widgets**, search for **TailOps**, and add the widget.

For command-line verification without signing:

```bash
cd platforms/macos/TailOpsMac
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Custom Widget Actions

The app settings UI edits the same action configuration that the widget reads. Actions are stored as `tailops-actions.json` in the shared App Group container, with a fallback to `Application Support/TailOpsMac` when App Groups are unavailable.

Example:

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

`hostID` can match a host ID, display name, MagicDNS name, or Tailscale IP. A sample file is available at:

```text
platforms/macos/TailOpsMac/config/tailops-actions.sample.json
```

## macOS Architecture

The macOS implementation avoids a Node backend:

- `TailOpsCore` parses Tailscale status and models hosts/actions.
- `TailOpsShared` stores snapshots and action config for app/widget sharing.
- `TailOpsIntents` provides widget App Intents for copy, refresh, settings, and opening Tailscale.
- `TailOpsMac` is the hidden SwiftUI host app for refresh, settings, and Finder Services.
- `TailOpsWidget` is the WidgetKit extension.

The widget uses WidgetKit container backgrounds, removable backgrounds, `widgetRenderingMode`, and `widgetAccentable(_:)` so macOS can apply modern tinted and Liquid Glass widget appearances.

More detail: `platforms/macos/TailOpsMac/README.md`.

## Current macOS Progress

As of May 15, 2026, the current branch has a widget-first native Swift macOS build. The app/widget are locally signed with a shared App Group, the widget reads cached snapshots, the hidden host app owns live Tailscale refresh and settings, and Taildrop is available through the Finder Service.

The installed local debug app is `/Applications/TailOps.app`. The Xcode scheme and target remain named `TailOpsMac`, but the app bundle, widget picker label, and icon resources are branded as TailOps.

Next implementation batch:

1. Exercise the widget gear/settings flow in the real desktop widget after install.
2. Polish the settings editor for custom dashboard presets and common ports.
3. Continue right-click Taildrop polish around destination picking and transfer feedback.
4. Decide whether any menu-bar surface is worth restoring later as optional, not primary.

Recent checkpoint polish:

- Widget header spacing was adjusted to avoid clipping on the desktop.
- The widget now declares the extra-large family for more room when macOS offers it.
- The widget extension includes the shared app icon asset catalog so the widget picker no longer falls back to a generic icon.
- The built app product is `TailOps.app` instead of `TailOpsMac.app`.

Deferred for now: ping-rate controls and TailOps Drop Zone. Drop Zone remains wishlist only.

## macOS Runtime Impact

The WidgetKit extension is passive. It reads the cached shared snapshot and asks WidgetKit for another timeline in about five minutes. It does not run `tailscale`, keep a backend alive, or ping hosts.

The hidden host app is the active side. It refreshes on app launch and when the user presses refresh from the widget. A refresh currently runs:

- one `tailscale status --json`;
- six `tailscale ping` samples for each online peer.

For a small tailnet this is low impact. Ping rate controls are not in the next implementation batch; keep evaluating the default after the widget shows clearer ping context.

## Verify The Swift Platform

```bash
cd platforms/macos/TailOpsMac
swift run TailOpsCoreValidation
swift build --target TailOpsMacViews
swift build --target TailOpsWidgetViews
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Browser Dashboard

The browser dashboard remains available for full-screen visualization, live telemetry experiments, and the AI phonebook surface.

Run it with:

```bash
npm run serve
```

Then open:

```text
http://127.0.0.1:4173/
```

Endpoints:

```text
GET /api/telemetry
GET /api/agents
GET /.well-known/agent.json
```

The server reads live Tailscale hosts through `tailscale status --json`. It can also pull ASUSWRT router telemetry through Home Assistant when `TAILOPS_HA_URL` and `TAILOPS_HA_TOKEN` are set.

Run the Node test suite with:

```bash
npm test
```

## AI Phonebook

The browser dashboard exposes a machine-readable local agent directory:

- `window.tailopsAgentDirectory`
- `window.tailopsReachableAgents`
- `<script id="tailops-agent-directory" type="application/json">`
- `/api/agents`

This is intended to evolve into an MCP resource/tool so local AI agents can discover reachable tailnet peers.

## Next Work

- Add launch-at-login and menu-bar icon visibility settings.
- Add a widget-to-app entry point so hiding the menu icon still has a recovery path.
- Show latest ping route and latency text in the widget so the sparkline has context.
- Add a host picker in macOS settings from the current Tailscale snapshot.
- Replace direct `tailscale status --json` process calls with a helper/XPC path if pursuing a sandboxed distribution build.

Wishlist: a Finder-based TailOps Drop Zone for easier Taildrop sends.

Detailed plan: `docs/superpowers/plans/2026-05-14-tailops-macos-control-surface.md`.
