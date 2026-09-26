# Retire the browser dashboard

TailOps removes the Node browser dashboard (`server.js`, `index.html`, `src/`, `tests/`, `data/`) from the repository. This supersedes the browser-experiment half of [ADR-0001](0001-native-product-boundary.md); the native product boundary it describes is unchanged.

By September 2026 the dashboard no longer served the product. It resolved its static root with a Windows-only path trick, so `/` and `/api/agents` returned 404 on macOS and Linux. A malformed percent escape in any request crashed the process, the server accepted any `Host` header, and its charts, demo hosts, and agent phonebook were simulated or static data. It also carried one router's Home Assistant entity IDs in a public repository. The native widget and `tailopsd` cover the live-state paths it prototyped, and it had not changed since April.

The last version is tagged `browser-dashboard-final`. Reviving a browser surface should start from that tag, move under `platforms/web/`, reuse the `tailopsd` status collector and Mullvad provider filter, and fix the issues above before it ships.
