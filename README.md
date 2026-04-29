# TailOps Monitor

Ambient Tailscale device performance dashboard for a local network. The app renders a mesh constellation of hosts, animated traffic flows, CPU temperature health rings when available, and a top-activity spotlight.

## Design Reference

- Stitch project: https://stitch.withgoogle.com/projects/2020355768956197107
- Current concept screenshot: `docs/assets/stitch-final-mesh-combo.png`

## What It Shows

- Live Tailscale hosts from `tailscale status --json` when served with `npm run serve`
- Tailscale peer online/offline state, OS, MagicDNS name, Tailscale IP, relay, activity state, tx/rx counters, exit-node and subnet-route state
- Local machine CPU and memory from Windows CIM when available
- Placeholder fields for remote CPU, memory, disk, disk I/O, packet loss, and CPU temperature until a per-host agent reports them
- Automatically selected top active host, weighted toward network throughput and disk I/O
- Agent availability indicators for OpenClaw, MCP, and local worker agents

## AI Phonebook

The visible dashboard stays ambient, but the browser exposes a machine-readable contact directory:

- `window.tailopsAgentDirectory`
- `window.tailopsReachableAgents`
- `<script id="tailops-agent-directory" type="application/json">`
- server endpoint: `/api/agents`
- sample file: `data/agents.sample.json`

This is intended to evolve into an MCP resource/tool so local AI agents can discover reachable peers from the phonebook.

## Run Locally

Open `index.html` in a browser for local-only demo viewing, or serve it on your LAN with:

```bash
npm run serve
```

The server binds to `0.0.0.0:4173` by default.

Dashboard:

```text
http://127.0.0.1:4173/
```

Live telemetry endpoint:

```text
http://127.0.0.1:4173/api/telemetry
```

Agent phonebook endpoint:

```text
http://127.0.0.1:4173/api/agents
```

The browser falls back to simulated demo telemetry when opened directly from `file://`.

Run tests with:

```bash
npm test
```

## Next Integration Points

- Add a per-host TailOps/OpenClaw agent that reports remote CPU, memory, disk, process, and CPU temperature data.
- Replace `data/agents.sample.json` with a generated or discovered live agent registry.
- Add MCP server support so local AI agents can query the phonebook directly.
