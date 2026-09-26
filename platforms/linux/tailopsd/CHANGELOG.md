# Changelog

## 0.2.0

- Add the collector node's own health to each observation: OS, kernel, uptime, load, memory, root disk, failed systemd units, and the hottest thermal sensor, with warnings for full disks, low memory, failed units, and heat. Each probe fails independently without failing the snapshot.
- Add `--no-host` to omit host health.

## 0.1.0

- Add the versioned Fleet observation contract.
- Exclude Mullvad provider nodes by default.
- Add runtime diagnostics and atomic snapshot output.
- Add optional restricted systemd timer packaging.
