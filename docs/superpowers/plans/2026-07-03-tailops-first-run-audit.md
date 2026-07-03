# TailOps First-Run Audit - 2026-07-03

Scope: issues Monroe or Ben may hit after cloning `tailops-monitor` to try the macOS TailOps app/widget and the planned Wormhole workflow.

## Findings

### P1 - Xcode project was pinned to Monroe's development team

Fresh clones could try to sign with `N6GPP46885`, which Ben likely cannot use. The README says each developer should choose their own team, so the project should not pin Monroe's team.

Status: fixed in `platforms/macos/TailOpsMac/TailOpsMac.xcodeproj/project.pbxproj` by clearing `DEVELOPMENT_TEAM` for app and widget Debug configurations.

### P1 - Release/archive path silently fell back to Debug

The target had Release configurations, but the project-level configuration list only contained Debug while the shared scheme used Release for profile/archive. Xcode could silently report `CONFIGURATION = Debug` for Release commands.

Status: fixed by adding a project-level Release configuration.

### P1 - Widget Release build used Debug-only preview fixtures

After adding a real Release configuration, `TailOpsWidget` failed because production widget placeholder/fallback code referenced `.preview` fixtures that only exist in Debug.

Status: fixed by using empty production-safe `TailnetSnapshot` / `TailnetActionConfiguration` fallbacks in `TailOpsWidget.swift`.

### P1 - Install/widget refresh docs used placeholder DerivedData paths

The local widget refresh docs previously used `~/Library/Developer/Xcode/DerivedData/...` placeholders. That is unsafe for a fresh clone because WidgetKit stale-registration issues depend on installing from the exact current build product.

Status: fixed by documenting a `xcodebuild -showBuildSettings` flow that derives `TARGET_BUILD_DIR`, `FULL_PRODUCT_NAME`, and `BUILT_APP`.

### P1 - Wormhole is not bundled or installed by TailOps

`wormhole` is not present on this Mac right now, and TailOps does not bundle it. First Wormhole UI must show a clear setup gate instead of assuming the command exists.

Recommended first trial dependency:

```bash
brew install magic-wormhole
```

Bundling is possible later, but the reference Magic Wormhole CLI is Python-based and has native crypto dependencies. That should be a separate packaging task with signed per-architecture helper artifacts.

### P2 - Tailscale command discovery needs to be visible in docs and UI errors

The app checks several direct executable paths for Tailscale, not just `tailscale` on `PATH`. Docs now list those paths. Runtime errors should continue to include every checked path so Ben can diagnose missing or differently installed Tailscale.

### P2 - Normal widget validation still requires local signing and WidgetKit refresh discipline

The no-sign Xcode build passes, but a real widget run still requires:

- selecting a local Apple Development team for both app and widget targets;
- signing the shared App Group entitlement;
- installing/launching the built app;
- refreshing PlugInKit/WidgetKit if extension metadata changes.

The macOS README already documents the reliable local refresh loop. Ben should not treat a plain SwiftPM build as proof the live desktop widget updated.

Status: docs now explicitly label no-sign builds as compile-only.

### P2 - Shared scheme referenced the old app product name

The shared `TailOpsMac` scheme used `BuildableName = "TailOpsMac.app"` even though the product is `TailOps.app`.

Status: fixed by updating the scheme BuildableName to `TailOps.app`.

### P2 - Required toolchain was underspecified

The package uses Swift tools 6.0 and the native app targets macOS 14. The root README only said Xcode was installed.

Status: docs now say macOS 14 or newer with Xcode 16 or newer.

### P3 - Browser dashboard remains separate from the native app path

The root repo includes a Node browser dashboard with `npm run serve`, but the macOS app/widget does not require it. The README is clear enough, but first-run instructions should keep Ben on `platforms/macos/TailOpsMac/TailOpsMac.xcodeproj` for the native app.

Status: `package.json` now declares `node >=18`, and the root README calls that out for the browser dashboard.

## Verified During Audit

```bash
cd platforms/macos/TailOpsMac
swift run TailOpsCoreValidation
swift build --target TailOpsIntents
swift build --target TailOpsMacViews
swift build --target TailOpsWidgetViews
xcodebuild -project TailOpsMac.xcodeproj -list
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Release CODE_SIGNING_ALLOWED=NO build
```

All commands passed on Monroe's Mac after the Wormhole foundation changes, `DEVELOPMENT_TEAM` cleanup, and project Release configuration fix.

## Next Hardening Steps

1. Exercise the host-app Wormhole setup gate on Monroe's Mac, where `wormhole` is currently missing.
2. Exercise a real Monroe-to-Ben transfer after Ben installs the same branch and Magic Wormhole.
3. Add cancellation for long-running send/receive processes.
4. Add a signed/bundled-helper decision after the external-command prototype works.
5. When installing for live widget testing, follow the installed-app proof gate: build product path, install to `/Applications/TailOps.app`, hash/launch/verify running path, then verify PlugInKit registration.
