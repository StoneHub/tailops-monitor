# TailOps Monitor

TailOps is a macOS-first Tailscale companion. The supported product is the WidgetKit extension plus its hidden Swift host app. The Node browser dashboard remains in this repository as an unsupported experiment for visualization and agent-directory prototyping.

## Support boundary

| Area | State | Proof boundary |
| --- | --- | --- |
| Native macOS app and widget | Supported product | Signed App Group build, installed app, running process, and WidgetKit registration are separate checks |
| Taildrop Finder Service | Supported same-account transfer path | Requires the local Tailscale CLI and a reachable destination |
| Magic Wormhole | Interactive cross-account transfer path | Requires the external `wormhole` CLI and both participants to be present |
| Browser dashboard | Unsupported experiment | Local Node process only; no hosted deployment is configured |
| Agent directory | Static prototype data | `/api/agents` reads `data/agents.sample.json`; it is not live agent discovery |

TailOps is the live operational client for Monroe's Fleet. The separate private Fleet repository owns durable identity, desired state, runbooks, and dated evidence. TailOps does not import that inventory or treat it as live health. See [ADR-0002](docs/adr/0002-fleet-integration.md).

The repository has no production web deployment. The browser server binds to `127.0.0.1` unless a user explicitly changes `HOST`, and it has no application-level authentication.

## Repository layout

```text
platforms/macos/TailOpsMac/       Native app, widget, shared state, intents, and Swift tests
src/                              Browser dashboard server and telemetry modules
tests/                            Node tests for the browser experiment
data/agents.sample.json           Static agent-directory prototype data
docs/                             Current agent guidance, architecture decisions, and history
```

## Native quick start

Requirements:

- macOS 14 or newer
- Xcode 16 or newer
- the Tailscale CLI
- an Apple Development team for signed App Group and WidgetKit testing
- optional Magic Wormhole CLI for cross-account file-transfer trials

Install the optional Wormhole dependency:

```bash
brew install magic-wormhole
```

Open the project:

```bash
open platforms/macos/TailOpsMac/TailOpsMac.xcodeproj
```

In Xcode, select an Apple Development team for both `TailOpsMac` and `TailOpsWidget`, then run the `TailOpsMac` scheme. The installed product is branded `TailOps.app`.

Compile without signing:

```bash
cd platforms/macos/TailOpsMac
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

That command proves compilation only. It does not prove that a signed App Group works, that `/Applications/TailOps.app` matches the build, or that the visible desktop widget loaded the new extension.

## Native runtime model

The hidden host app owns active work:

- runs `tailscale status --json` on launch, on an accepted refresh request, and every hour while the app remains alive;
- keeps managed Fleet nodes in the shared snapshot while hiding Mullvad provider peers tagged `tag:mullvad-exit-node`;
- samples each online peer with six `tailscale ping` attempts at most once per hour;
- writes snapshots, refresh health, settings, and non-secret Wormhole state to the App Group or local fallback;
- owns Settings, Finder Services, Wormhole orchestration, and the pending-transfer listener.

The widget is passive. It reads shared files and asks WidgetKit for a new timeline after 15 minutes. It supports medium, large, and extra-large families. Removing the widget leaves no separate backend process, while quitting the host app stops active refresh work.

## Actions and settings

TailOps supports three host action kinds:

- `ssh`: opens `ssh://host` with Terminal.
- `url`: opens an HTTP or HTTPS dashboard.
- `copy`: copies the configured value.

Settings stores host actions in `tailops-actions.json` and preferences in `tailops-preferences.json`. Files live in the signed App Group when available, with `Application Support/TailOpsMac` as the unsigned fallback.

Example action configuration:

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

A sample file lives at `platforms/macos/TailOpsMac/config/tailops-actions.sample.json`.

## File transfer

Use Taildrop for same-account devices. The reachable native entry point is the Finder Service named `Send with TailOps`.

Use Magic Wormhole for interactive cross-account transfers. Pairing secrets stay in the device-local Keychain. Shared JSON contains non-secret contact and transfer metadata only. Pending notices never contain file data or a Wormhole transfer code.

The pending-notice client routes to the configured Tailnet node. The receiver validates pairing ID, Keychain secret, HMAC, expiry, replay state, and bounded request structure. It does not independently authenticate the incoming transport peer as a Tailscale node.

Current Wormhole follow-up work remains in [the file-send upgrade plan](docs/superpowers/plans/2026-07-03-tailops-file-send-upgrade.html).

## Validation gates

Run the focused source checks with:

```bash
npm test
cd platforms/macos/TailOpsMac
swift test
swift run TailOpsCoreValidation
swift build --target TailOpsMacViews
swift build --target TailOpsWidgetViews
```

GitHub Actions also runs unsigned Debug and Release Xcode builds. A passing source build or CI run is not installed-widget proof. Signed App Group behavior, the copied application bundle, the running executable, and the visible widget each need their own evidence.

## Browser experiment

Run the unsupported local dashboard with:

```bash
npm run serve
```

Open `http://127.0.0.1:4173/`.

Local endpoints:

```text
GET /api/telemetry
GET /api/agents
GET /.well-known/agent.json
```

The server can read live Tailscale status and optional ASUSWRT telemetry through Home Assistant. Set `TAILOPS_HA_URL` and `TAILOPS_HA_TOKEN` locally for that integration. The URL defaults to loopback. Do not commit the token.

To expose the server to a trusted LAN or tailnet, set `HOST` explicitly. The server prints a warning because its endpoints have no authentication. Do not expose it to the public internet.

## Current follow-up work

- Add a host picker and common dashboard presets to Settings.
- Add explicit QR setup and cancellation controls to the Wormhole flow.
- Validate Wormhole between two signed, current Mac installs.
- Decide whether sandboxed distribution justifies a signed helper or XPC path for Tailscale commands.
- Keep the Finder-based Drop Zone as wishlist work.

## Project records

- [Domain glossary](CONTEXT.md)
- [Native product decision](docs/adr/0001-native-product-boundary.md)
- [April browser concept](docs/archive/2026-04/2026-04-29-tailops-monitor-design.md)
- [April implementation plan](docs/archive/2026-04/2026-04-29-tailops-monitor-implementation.md)
- [May native control-surface plan](docs/archive/2026-05/2026-05-14-tailops-macos-control-surface.md)
- [July first-run audit](docs/archive/2026-07/2026-07-03-tailops-first-run-audit.md)
- [July trust-hardening report](docs/archive/2026-07/2026-07-11-tailops-trust-hardening.html)

TailOps Monitor is available under the [MIT License](LICENSE).
