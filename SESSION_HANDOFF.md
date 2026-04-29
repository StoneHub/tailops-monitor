# TailOps Monitor Session Handoff

Date: 2026-04-29
Workspace root: `C:\Users\monro\Codex\tailops-monitor`

## Current Goal

Build TailOps Monitor into an ambient, screensaver-style Tailscale operations dashboard. It should show a visual mesh of all tailnet devices, highlight the currently most active host, surface CPU temperature where available, and expose an under-the-hood AI agent phonebook for local network agents.

The preferred visual direction is the Stitch "Mesh" concept with light chart overlays, not a menu-heavy admin console.

## Important Addresses

- Local dashboard: `http://127.0.0.1:4173/`
- LAN dashboard from other local devices: `http://192.168.50.78:4173/`
- Live telemetry API: `http://127.0.0.1:4173/api/telemetry`
- Agent phonebook API: `http://127.0.0.1:4173/api/agents`
- A2A-style agent card: `http://127.0.0.1:4173/.well-known/agent.json`
- Home Assistant on fcfdev: `http://100.104.71.37:8123/`
- Home Assistant MCP bridge on fcfdev: `http://100.104.71.37:8086/mcp`
- Stitch design reference: `https://stitch.withgoogle.com/projects/2020355768956197107`

## Current Implementation

- Dependency-free Node server in `server.js` and `src/server.js`.
- Browser UI in `index.html` and `src/app.js`.
- Tailscale live telemetry from `tailscale status --json`.
- Local Windows CPU/memory via CIM when available.
- Simulated demo fallback when opened from `file://` or when live telemetry fails.
- AI phonebook module in `src/agents.js`.
- Home Assistant ASUSWRT adapter in `src/home-assistant.js`.
- Tests in `tests/*.test.js`.

## Recent Commits

- `e6b70c1 feat: add tailops ambient monitor`
- `761d898 feat: use live tailscale telemetry`
- `57a4f08 feat: publish tailops agent card`
- `51c3e69 feat: add home assistant router telemetry`

No public GitHub push has been done yet. Confirm explicitly before publishing because the repo would become public if pushed to `@stonehub`.

## Home Assistant Status

Home Assistant had been broken on fcfdev because its venv was missing. It was repaired by recreating the venv, installing Home Assistant 2025.1.4, pinning `pycares<5`, and restarting `homeassistant.service`.

Current known state:

- `homeassistant.service` is active.
- HA responds at `http://100.104.71.37:8123/`.
- `ha-mcp.service` is active.
- HA MCP bridge responds at `http://100.104.71.37:8086/mcp`.
- The bridge URL was fixed from `https://127.0.0.1:8123` to `http://127.0.0.1:8123`.
- The bridge token in `/home/monroe/.homeassistant-token` is invalid.
- `hass --script auth list` reported zero users at the time of repair.

Current blocker: create or provide a valid Home Assistant long-lived access token, then restart TailOps with:

```powershell
$env:TAILOPS_HA_URL = "http://100.104.71.37:8123"
$env:TAILOPS_HA_TOKEN = "<home-assistant-long-lived-access-token>"
npm run serve
```

Once that token is set, TailOps should add a virtual `ZenWiFi XD5` router host to `/api/telemetry`.

## ASUSWRT Entities Targeted

These were found in Home Assistant's entity registry:

```text
sensor.192_168_50_1_cpu_usage
sensor.192_168_50_1_cpu_core_1_usage
sensor.192_168_50_1_cpu_core_2_usage
sensor.192_168_50_1_cpu_core_3_usage
sensor.192_168_50_1_cpu_core_4_usage
sensor.192_168_50_1_memory_usage
sensor.192_168_50_1_memory_free
sensor.192_168_50_1_memory_used
sensor.192_168_50_1_cpu_temperature
binary_sensor.zenwifi_xd5_7890_wan_status
sensor.zenwifi_xd5_7890_wan_status
```

## Verification

Last known test command:

```powershell
npm test
```

Result: 17 passing tests.

The sandbox blocked Node's test-runner worker spawn with `spawn EPERM`; running the same command with escalation succeeded.

Last known live telemetry state without HA token:

```json
{
  "available": false,
  "source": "home-assistant",
  "homeAssistantUrl": "http://100.104.71.37:8123",
  "error": "TAILOPS_HA_TOKEN is not set"
}
```

This is expected until a valid HA token is supplied.

## Suggested Next Session Steps

1. Start the new Codex session with workspace root `C:\Users\monro\Codex\tailops-monitor`.
2. Confirm `git status -sb` is clean.
3. Start or restart the server with `npm run serve`.
4. Open `http://127.0.0.1:4173/api/telemetry` and confirm Tailscale live data.
5. Add a valid Home Assistant long-lived access token to `TAILOPS_HA_TOKEN`.
6. Confirm `/api/telemetry` includes `integrations.homeAssistant.available: true`.
7. Confirm the virtual `ZenWiFi XD5` router host appears with CPU, memory, WAN status, and CPU temperature.
8. Consider making `/api/agents` generated from live Tailscale plus discovered MCP/A2A endpoints instead of using `data/agents.sample.json`.
9. Consider adding a real MCP server/resource for the phonebook.
10. Only after explicit approval, publish the repo to GitHub under `@stonehub`.

## Workflow Notes

The current projectless session started in `C:\Users\monro\Documents\Codex\...`, while the real project is in `C:\Users\monro\Codex\tailops-monitor`. That mismatch caused git metadata writes under `.git` to need escalation. Future work should start with `C:\Users\monro\Codex\tailops-monitor` as the workspace root.

Global user preference has already been documented in `C:\Users\monro\.codex\AGENTS.md`: place projects under `C:\Users\monro\Codex`.
