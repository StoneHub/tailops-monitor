import Foundation
import TailOpsCore

#if DEBUG
public extension TailnetSnapshot {
    static let preview = TailnetSnapshot(hosts: [
        TailnetHost(
            id: "mac",
            name: "monroe-mac",
            role: .thisDevice,
            status: .online,
            operatingSystem: "macOS",
            primaryAddress: "100.64.0.1",
            magicDNSName: "monroe-mac.tailnet.ts.net",
            lastSeen: nil,
            services: []
        ),
        TailnetHost(
            id: "openclaw",
            name: "openclaw",
            role: .peer,
            status: .online,
            operatingSystem: "linux",
            primaryAddress: "100.64.0.2",
            magicDNSName: "openclaw.tailnet.ts.net",
            lastSeen: nil,
            services: [
                TailnetService(label: "OpenClaw", url: URL(string: "http://openclaw.tailnet.ts.net:8080")!)
            ]
        ),
        TailnetHost(
            id: "router",
            name: "asus-router",
            role: .peer,
            status: .warning,
            operatingSystem: "asuswrt",
            primaryAddress: "100.64.0.3",
            magicDNSName: "router.tailnet.ts.net",
            lastSeen: nil,
            services: [
                TailnetService(label: "Router", url: URL(string: "http://router.tailnet.ts.net")!)
            ]
        ),
        TailnetHost(
            id: "pixel",
            name: "pixel-test",
            role: .peer,
            status: .offline,
            operatingSystem: "android",
            primaryAddress: "100.64.0.4",
            magicDNSName: "pixel-test.tailnet.ts.net",
            lastSeen: Date(timeIntervalSinceNow: -3600),
            services: []
        )
    ])
}

public extension TailnetActionConfiguration {
    static let preview = TailnetActionConfiguration(hostActions: [
        TailnetHostActionConfiguration(
            hostID: "openclaw",
            actions: [
                TailnetQuickAction(emoji: "🖥", title: "SSH", kind: .ssh, target: "openclaw.tailnet.ts.net"),
                TailnetQuickAction(emoji: "🧭", title: "Dash", kind: .url, target: "http://openclaw.tailnet.ts.net:8080"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.2")
            ]
        ),
        TailnetHostActionConfiguration(
            hostID: "asus-router",
            actions: [
                TailnetQuickAction(emoji: "📡", title: "Admin", kind: .url, target: "http://router.tailnet.ts.net"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.3")
            ]
        ),
        TailnetHostActionConfiguration(
            hostID: "monroe-mac",
            actions: [
                TailnetQuickAction(emoji: "🏠", title: "Local", kind: .url, target: "http://127.0.0.1:4173"),
                TailnetQuickAction(emoji: "📋", title: "IP", kind: .copy, target: "100.64.0.1")
            ]
        )
    ])
}
#endif
