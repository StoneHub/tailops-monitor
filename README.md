# TailOps Monitor

TailOps Monitor is a low-impact macOS tailnet companion for Tailscale users. The primary experience is a Swift menu-bar app plus a WidgetKit desktop widget that keeps useful tailnet shortcuts one click away: SSH, local dashboards, copied IPs, and quick reachability status.

The older browser dashboard is still included as a full-screen visualization and telemetry playground, but the macOS widget suite is now the main product path.

## What It Does

- Shows Tailscale hosts from `tailscale status --json`.
- Adds a macOS menu-bar panel for refreshing and inspecting tailnet hosts.
- Adds a desktop WidgetKit widget with host rows and custom emoji action buttons.
- Adds passive ping context for online peers when the app refreshes, then exposes the cached result in the menu bar and widget.
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
4. Run the `TailOpsMac` scheme.
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
- `TailOpsIntents` provides widget App Intents for copy and refresh actions.
- `TailOpsMac` is the SwiftUI menu-bar app.
- `TailOpsWidget` is the WidgetKit extension.

The widget uses WidgetKit container backgrounds, removable backgrounds, `widgetRenderingMode`, and `widgetAccentable(_:)` so macOS can apply modern tinted and Liquid Glass widget appearances.

More detail: `platforms/macos/TailOpsMac/README.md`.

## macOS Runtime Impact

The WidgetKit extension is passive. It reads the cached shared snapshot and asks WidgetKit for another timeline in about five minutes. It does not run `tailscale`, keep a backend alive, or ping hosts.

The menu-bar app is the active side. It refreshes on app launch, when the menu panel appears, and when the user presses refresh. A refresh currently runs:

- one `tailscale status --json`;
- six `tailscale ping` samples for each online peer.

For a small tailnet this is low impact, but ping controls are the next planned settings work so users can reduce sample count or make ping manual-only.

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
- Add a widget settings gear that opens TailOps settings.
- Show latest ping route and latency text in the widget so the sparkline has context.
- Add ping rate controls: fewer samples and manual-only mode.
- Design and then build a Finder-based TailOps Drop Zone for easier Taildrop sends.
- Add a host picker in macOS settings from the current Tailscale snapshot.
- Replace direct `tailscale status --json` process calls with a helper/XPC path if pursuing a sandboxed distribution build.

Detailed plan: `docs/superpowers/plans/2026-05-14-tailops-macos-control-surface.md`.
