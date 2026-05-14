# TailOps macOS Control Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-controlled launch, menu-bar visibility, a reliable widget-to-app recovery path, and clearer ping context while keeping TailOps low-impact.

**Architecture:** Keep the widget passive and make the menu-bar app the only process that runs Tailscale CLI commands. Store preferences in the shared app group so app and widget can agree on display choices, but keep command execution inside the app. Use an App Intent or URL route for a widget control that opens TailOps when the menu-bar icon is hidden.

**Tech Stack:** SwiftUI, WidgetKit, AppIntents, ServiceManagement, App Group storage, existing `TailOpsCore`, `TailOpsShared`, and `TailOpsCoreValidation`.

---

## Current Save Point

The current branch is `codex/macos-widget-platform`. As of this plan, the app builds and runs as a signed local macOS app, the widget reads the shared snapshot from the team-prefixed App Group, the menu bar uses the constellation icon, and Taildrop is available through drag/drop in the menu plus a Finder Service.

## Progress Snapshot - 2026-05-14

Completed:

- Native Swift/Apple macOS path selected over a Node-backed widget.
- Xcode project exists for `TailOpsMac` plus embedded `TailOpsWidget`.
- App and widget sign locally with the team-prefixed App Group.
- Shared snapshot storage works in the team-prefixed App Group with legacy fallback.
- Menu-bar app reads `tailscale status --json`, refreshes manually/on launch/on menu open, and writes the widget snapshot.
- Menu-bar host rows sort by useful/recent availability.
- Menu-bar rows show ping sparkline context and accept file drops for Taildrop.
- Finder Service exists for `Send with TailOps`, backed by `tailscale file cp --targets`.
- Widget supports small, medium, and large families.
- Widget uses the constellation SF Symbol, avoids the inactive-focus white-pill rendering issue, prioritizes reachable hosts, and collapses extra offline hosts into a count.
- Widget has refresh and copy intents.
- Custom host action config exists for SSH, dashboard URLs, and copy actions.
- Root and macOS READMEs describe the native macOS product path, runtime impact, Taildrop state, and next plan.

Next implementation batch:

1. Add shared app preferences for launch/login/menu visibility/widget app-entry state.
2. Add `Launch at login` in settings using `ServiceManagement`.
3. Add `Show menu bar icon` setting.
4. Add a widget-to-app entry point instead of a hover-only gear.
5. Show latest ping route and latency text in widget rows so the sparkline has context.

Secondary backlog:

- Add a host picker in macOS settings from the current Tailscale snapshot.
- Add terminal preference support for SSH actions.
- Replace direct `tailscale` process calls with an XPC/helper path if pursuing sandboxed distribution.

Deferred:

- Ping rate/sample controls are dropped from the next batch.
- TailOps Drop Zone remains wishlist only.
- A real mounted drive/File Provider Taildrop surface is deferred until a watched-folder Drop Zone proves useful.

Current refresh behavior:

- The widget timeline reloads every 5 minutes from `tailops-snapshot.json`.
- The widget does not run `tailscale status` or `tailscale ping`.
- The app refreshes on launch, when the menu panel appears, and when the refresh button is pressed.
- Each app refresh runs `tailscale status --json`.
- For each online peer, each app refresh runs `tailscale ping --c 6 --timeout 1500ms --until-direct=false <host>`.

The current idle impact is therefore near zero beyond WidgetKit reading a small JSON file. The active refresh cost is one `tailscale status` command plus six ping samples per online peer.

## Files

- Modify: `platforms/macos/TailOpsMac/Sources/TailOpsCore/TailOpsCore.swift`
- Modify: `platforms/macos/TailOpsMac/Sources/TailOpsCoreValidation/TailOpsCoreValidation.swift`
- Modify: `platforms/macos/TailOpsMac/Shared/SharedSnapshotStore.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailOpsMacApp.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailOpsMenuView.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailOpsSettingsView.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailnetMonitor.swift`
- Modify: `platforms/macos/TailOpsMac/Widget/TailOpsWidget.swift`
- Modify: `platforms/macos/TailOpsMac/Intents/TailOpsWidgetIntents.swift`
- Modify: `platforms/macos/TailOpsMac/Package.swift`

## Task 1: Shared App Preferences

**Files:**
- Modify: `platforms/macos/TailOpsMac/Sources/TailOpsCore/TailOpsCore.swift`
- Modify: `platforms/macos/TailOpsMac/Sources/TailOpsCoreValidation/TailOpsCoreValidation.swift`
- Modify: `platforms/macos/TailOpsMac/Shared/SharedSnapshotStore.swift`

- [ ] **Step 1: Write the failing validation**

Add a validation function named `appPreferencesRoundTripThroughSharedStore()` in `TailOpsCoreValidation.swift`:

```swift
private static func appPreferencesRoundTripThroughSharedStore() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appending(path: "TailOpsPreferencesValidation-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let store = SharedSnapshotStore(baseURLs: [rootURL])
    let preferences = TailOpsAppPreferences(
        launchAtLogin: true,
        showMenuBarIcon: false,
        opensSettingsFromWidget: true
    )

    try store.saveAppPreferences(preferences)
    let loaded = try store.loadAppPreferences()

    expect(loaded == preferences, "expected shared app preferences to round trip")
}
```

Call it from `main()` before the final print.

- [ ] **Step 2: Run validation to verify it fails**

Run:

```bash
cd platforms/macos/TailOpsMac
swift run TailOpsCoreValidation
```

Expected: compile failure because `TailOpsAppPreferences`, `saveAppPreferences`, and `loadAppPreferences` do not exist yet.

- [ ] **Step 3: Add the model**

Add to `TailOpsCore.swift`:

```swift
public struct TailOpsAppPreferences: Codable, Equatable, Sendable {
    public let launchAtLogin: Bool
    public let showMenuBarIcon: Bool
    public let opensSettingsFromWidget: Bool

    public init(
        launchAtLogin: Bool = false,
        showMenuBarIcon: Bool = true,
        opensSettingsFromWidget: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.opensSettingsFromWidget = opensSettingsFromWidget
    }
}
```

- [ ] **Step 4: Add store methods**

Extend `SharedSnapshotStoring` and `SharedSnapshotStore` in `SharedSnapshotStore.swift`:

```swift
func loadAppPreferences() throws -> TailOpsAppPreferences?
func saveAppPreferences(_ preferences: TailOpsAppPreferences) throws
```

Use the path `tailops-preferences.json` and the existing `loadFirstExisting` / `write` helpers.

- [ ] **Step 5: Run validation to verify it passes**

Run:

```bash
cd platforms/macos/TailOpsMac
swift run TailOpsCoreValidation
```

Expected: `TailOpsCoreValidation passed`.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/TailOpsMac/Sources/TailOpsCore/TailOpsCore.swift \
  platforms/macos/TailOpsMac/Sources/TailOpsCoreValidation/TailOpsCoreValidation.swift \
  platforms/macos/TailOpsMac/Shared/SharedSnapshotStore.swift
git commit -m "feat: add shared TailOps app preferences"
```

## Task 2: Launch At Login Setting

**Files:**
- Modify: `platforms/macos/TailOpsMac/App/TailOpsSettingsView.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailOpsActionSettingsModel.swift`

- [ ] **Step 1: Add settings model state**

Add `@Published var launchAtLogin = false` to the settings model and load it from `SharedSnapshotStore.loadAppPreferences()`.

- [ ] **Step 2: Add ServiceManagement writer**

In the settings model, add:

```swift
@MainActor
func setLaunchAtLogin(_ enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = enabled
        savePreferences()
    } catch {
        validationMessage = error.localizedDescription
    }
}
```

Import `ServiceManagement`.

- [ ] **Step 3: Add the settings toggle**

In `TailOpsSettingsView.swift`, add a toggle labeled `Launch at login` bound to `setLaunchAtLogin(_:)`.

- [ ] **Step 4: Build**

Run:

```bash
cd platforms/macos/TailOpsMac
swift build --target TailOpsMacViews
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug build
```

Expected: both builds succeed.

- [ ] **Step 5: Commit**

```bash
git add platforms/macos/TailOpsMac/App/TailOpsSettingsView.swift \
  platforms/macos/TailOpsMac/App/TailOpsActionSettingsModel.swift
git commit -m "feat: add launch at login preference"
```

## Task 3: Menu Bar Icon Visibility

**Files:**
- Modify: `platforms/macos/TailOpsMac/App/TailOpsMacApp.swift`
- Modify: `platforms/macos/TailOpsMac/App/TailOpsSettingsView.swift`

- [ ] **Step 1: Add app-level preference state**

Load `TailOpsAppPreferences.showMenuBarIcon` in `TailOpsMacApp` through an observable preferences object.

- [ ] **Step 2: Conditionally show `MenuBarExtra`**

Wrap the existing `MenuBarExtra` scene in a branch that only emits it when `showMenuBarIcon` is true.

- [ ] **Step 3: Keep a recovery path**

Add the widget-to-app control in Task 4 before hiding the menu bar icon is exposed. The app must always have a route back to settings.

- [ ] **Step 4: Add the settings toggle**

Add a setting labeled `Show menu bar icon`. Include help text: disabling this leaves the app running quietly for widget refresh and settings access through the widget's TailOps app control.

- [ ] **Step 5: Build and run**

Run:

```bash
cd platforms/macos/TailOpsMac
swift build --target TailOpsMacViews
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug build
```

Expected: both builds succeed and disabling the toggle removes the menu bar extra after relaunch.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/TailOpsMac/App/TailOpsMacApp.swift \
  platforms/macos/TailOpsMac/App/TailOpsSettingsView.swift
git commit -m "feat: add menu bar icon visibility setting"
```

## Task 4: Widget-To-App Entry Point

**Files:**
- Modify: `platforms/macos/TailOpsMac/Intents/TailOpsWidgetIntents.swift`
- Modify: `platforms/macos/TailOpsMac/Widget/TailOpsWidget.swift`

- [ ] **Step 1: Add an App Intent or URL route**

Add `OpenTailOpsIntent` that opens the app with a `tailops://open` URL route. If a direct AppIntent-to-URL path is awkward on macOS, use `.widgetURL(URL(string: "tailops://open"))` on the widget background and keep the explicit refresh button as the only small header control.

- [ ] **Step 2: Prefer an app affordance, not a gear**

Do not add a visible gear as the primary design. WidgetKit does not expose arbitrary hover-only controls, and a gear competes with the refresh control. Use one of these instead:

- Small widget: tapping the widget body opens TailOps.
- Medium widget: tapping empty/background space opens TailOps; host buttons still perform host actions.
- Large widget: add a low-prominence `slider.horizontal.3` or `app.badge` button labeled by accessibility as `Open TailOps settings`.

The visual goal is recovery/access, not an in-widget settings surface.

- [ ] **Step 3: Build**

Run:

```bash
cd platforms/macos/TailOpsMac
swift build --target TailOpsWidgetViews
xcodebuild -project TailOpsMac.xcodeproj -scheme TailOpsMac -configuration Debug build
```

Expected: widget target and full app build succeed.

- [ ] **Step 4: Commit**

```bash
git add platforms/macos/TailOpsMac/Intents/TailOpsWidgetIntents.swift \
  platforms/macos/TailOpsMac/Widget/TailOpsWidget.swift
git commit -m "feat: add widget TailOps entry point"
```

## Task 5: Ping Context In Widget

**Files:**
- Modify: `platforms/macos/TailOpsMac/Widget/TailOpsWidget.swift`
- Modify: `platforms/macos/TailOpsMac/Sources/TailOpsCoreValidation/TailOpsCoreValidation.swift`

- [ ] **Step 1: Add validation for ping label formatting**

Add a core helper so widget and menu text can format route and latency consistently:

```swift
let ping = TailnetPingSummary(samples: [
    TailnetPingSample(latencyMilliseconds: 12, route: .direct)
])
expect(ping.summaryLabel == "Direct 12 ms", "expected latest ping label")
```

- [ ] **Step 2: Implement the label**

Add `summaryLabel` to `TailnetPingSummary` in `TailOpsCore.swift`.

- [ ] **Step 3: Show label in focused widget rows**

In `WidgetHostActionRow`, show the latest ping label beside the IP address or below the hostname when `host.diagnostics?.ping` is available.

- [ ] **Step 4: Keep graph as secondary**

Keep the sparkline at low opacity and make the text label the primary context.

- [ ] **Step 5: Build and validate**

Run:

```bash
cd platforms/macos/TailOpsMac
swift run TailOpsCoreValidation
swift build --target TailOpsWidgetViews
```

Expected: validation and widget view build pass.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/TailOpsMac/Sources/TailOpsCore/TailOpsCore.swift \
  platforms/macos/TailOpsMac/Sources/TailOpsCoreValidation/TailOpsCoreValidation.swift \
  platforms/macos/TailOpsMac/Widget/TailOpsWidget.swift
git commit -m "feat: show latest ping context in widget"
```

## Wishlist: Taildrop Drop Zone

The TailOps Drop Zone remains a useful future idea, but it is not part of the next implementation batch.

Preferred future shape:

- A temporary Finder folder named `TailOps Drop Zone`.
- One child folder per available Taildrop target.
- Dropping a file into a device folder sends it with `tailscale file cp`.
- After send, TailOps confirms success and clears or archives the dropped file.

A real mounted volume or File Provider extension stays out of scope until the watched-folder version proves useful.
