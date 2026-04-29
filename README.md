# TailOps Monitor

Ambient Tailscale device performance dashboard for a local network. The first build is a dependency-free static web app that renders a mesh constellation of hosts, animated traffic flows, CPU temperature health rings, and a top-activity spotlight.

## Design Reference

- Stitch project: https://stitch.withgoogle.com/projects/2020355768956197107
- Current concept screenshot: `docs/assets/stitch-final-mesh-combo.png`

## What It Shows

- Tailscale-style hosts: `atlas-win11`, `nuc-lab`, `nas-vault`, `pi-dns`, `media-mac`, `work-laptop`, `homelab-router`
- Per-host CPU, memory, disk, disk I/O, network in/out, latency, packet loss, uptime, CPU temperature, exit-node and subnet-route state
- Automatically selected top active host, weighted toward network throughput and disk I/O
- Agent availability indicators for OpenClaw, MCP, and local worker agents

## AI Phonebook

The visible dashboard stays ambient, but the browser exposes a machine-readable contact directory:

- `window.tailopsAgentDirectory`
- `window.tailopsReachableAgents`
- `<script id="tailops-agent-directory" type="application/json">`
- sample file: `data/agents.sample.json`

This is intended to evolve into `/api/agents` or an MCP resource/tool when the dashboard gets a live backend.

## Run Locally

Open `index.html` in a browser for local-only viewing, or serve it on your LAN with:`r`n`r`n```bash`r`nnpm run serve`r`n``` `r`n`r`nThe server binds to `0.0.0.0:4173` by default and exposes the phonebook at `/api/agents`.

Run tests with:

```bash
npm test
```

## Next Integration Points

- Replace simulated telemetry in `src/telemetry.js` with Tailscale, host sensor, and process data.
- Serve `data/agents.sample.json` as `/api/agents` from a small local backend.
- Add MCP server support so local AI agents can discover reachable peers from the phonebook.

