# Fleet registry and TailOps live-state ownership

TailOps is the live operational client for Monroe's Fleet, while the separate Fleet repository owns durable device identity, desired state, runbooks, and dated evidence. TailOps must integrate through narrow adapters and stable contracts instead of importing Fleet files or copying private inventory into this repository. Live health comes from current local adapters such as Tailscale status; checked-in Fleet observations never become runtime truth.

Provider infrastructure remains outside the managed Fleet even when Tailscale lists it as a peer. TailOps hides peers tagged `tag:mullvad-exit-node` from managed-fleet views by default. A caller may request all peers for diagnostics, but widgets and Settings use the managed-fleet policy.
