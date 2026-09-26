# TailOps Monitor Design Spec

Stitch project: https://stitch.withgoogle.com/projects/2020355768956197107

Reference concept: `docs/assets/stitch-final-mesh-combo.png`

## Goal

Build an ambient, screensaver-like Tailscale network performance dashboard. It should show a mesh constellation of hosts, flowing traffic, chart-heavy telemetry, CPU temperature, and a hidden machine-readable agent phonebook for AI agents on the local network.

## Product Shape

The first screen is the product. There is no landing page, hero, sidebar, heavy menu, or dense table. The primary surface is a full-screen mesh visualization showing hosts as nodes with health rings and animated traffic flows. The busiest host is automatically spotlighted with larger charts and status detail.

## Telemetry Model

Each host tracks CPU, memory, disk use, disk I/O, network in/out, latency, packet loss, uptime, online status, exit-node status, subnet-route status, CPU temperature, and active service/process summaries. The dashboard computes an activity score weighted toward network throughput and disk I/O so the top active host changes as the simulated data changes.

## Agent Phonebook

Each host may expose zero or more local agents. The visible UI shows only compact agent availability indicators. Under the hood the app exposes a JSON-style directory with host name, Tailscale IP, MagicDNS name, agent type, availability, contact endpoint, capabilities, and last seen time. This can later become an MCP resource or tool.

## Visual Direction

Use the Stitch Mesh Constellation concept as the target, with restrained System Aquarium flow energy. The palette is dark graphite/ink with cyan, green, amber, and red status accents. Shapes stay crisp with 8px or smaller radius. Text is minimal, code-native, and readable from a second monitor.

## Local Build Scope

The initial implementation is a dependency-free static web app using HTML, CSS, SVG/canvas, and JavaScript modules. It uses simulated data now, with clean seams for later live Tailscale, hardware sensor, and agent heartbeat integrations.
