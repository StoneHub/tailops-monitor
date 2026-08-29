# TailOps

TailOps is a macOS-first Tailscale companion. This glossary names the product boundary, network objects, transfer paths, and proof terms used throughout the repository.

## Language

**Supported native product**:
The WidgetKit extension and hidden Swift host app that make up the supported macOS product.
_Avoid_: Browser dashboard, Node widget, menu-bar app as the primary product

**Browser experiment**:
The unsupported full-screen dashboard retained for telemetry visualization and agent-directory exploration.
_Avoid_: Production dashboard, supported web product, live agent discovery

**Tailnet host**:
A device represented by Tailscale status and shown in TailOps.
_Avoid_: Agent, service

**Fleet node**:
A Tailnet host Monroe manages and includes in operational views.
_Avoid_: Every Tailscale peer, provider node

**Provider node**:
Infrastructure enrolled by an external network provider, such as a Mullvad exit node. It remains available to Tailscale but is not part of Monroe's Fleet.
_Avoid_: Fleet node, managed host

**Fleet registry**:
The separate Git-backed record of durable device identity, desired state, runbooks, and dated evidence. It is not a live health source.
_Avoid_: TailOps snapshot, live dashboard

**Shared snapshot**:
A serialized view of Fleet nodes that the native host app writes and the widget reads.
_Avoid_: Live widget state, backend state

**Taildrop**:
Same-account file transfer through Tailscale.
_Avoid_: Cross-account transfer

**Wormhole transfer**:
An interactive cross-account file transfer with a paired contact. Both participants must be present.
_Avoid_: Taildrop, unattended inbox

**Pending notice**:
Signed, short-lived file metadata that tells a paired Tailnet peer a Wormhole transfer is waiting. It never contains file data or a transfer code.
_Avoid_: Transfer payload, invitation code

**Installed-widget proof**:
Evidence that one signed app build is installed and running, and that WidgetKit registered and displayed its matching extension.
_Avoid_: Compile proof, copied-bundle proof, CI proof
