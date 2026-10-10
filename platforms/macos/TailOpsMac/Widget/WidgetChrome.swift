import AppKit
import SwiftUI
import WidgetKit

/// Look-and-feel conventions for Monroe's desktop widgets. Fan Lever keeps a
/// matching copy in its `Shared/WidgetChrome.swift`; change both together so
/// the widgets stay consistent side by side.
///
/// Nothing here chooses a color. macOS supplies the glass platter, Light or
/// Dark appearance, the Clear and Tinted widget styles, the glass tint amount,
/// and the accent color. Widgets only layer translucent system fills on top and
/// take their tint from System Settings.
enum WidgetChrome {
    /// The accent color chosen in System Settings → Appearance.
    ///
    /// `Color.accentColor` stays SwiftUI's default blue when WidgetKit renders
    /// off-screen. AppKit's control accent follows the person's choice.
    static var accent: Color { Color(nsColor: .controlAccentColor) }

    static let tileCornerRadius: CGFloat = 12
    static let pillHeight: CGFloat = 22
}

extension View {
    /// Applies the system widget background and accent. Use once, on the
    /// widget's root view.
    ///
    /// The fill is translucent so the system glass platter shows through, and
    /// WidgetKit removes it for the Clear and Tinted widget styles.
    func widgetChromeSurface() -> some View {
        containerBackground(.fill.tertiary, for: .widget)
            .tint(WidgetChrome.accent)
    }

    /// Groups related content on a raised, translucent card. A highlighted tile
    /// draws an accent border instead of the hairline.
    func widgetChromeTile(
        cornerRadius: CGFloat = WidgetChrome.tileCornerRadius,
        highlighted: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.fill.secondary, in: shape)
            .overlay {
                if highlighted {
                    shape.strokeBorder(.tint, lineWidth: 2)
                } else {
                    shape.strokeBorder(.separator, lineWidth: 1)
                }
            }
    }

    /// Secondary status line at the bottom of a widget.
    func widgetChromeFootnote() -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Widget title row: an accent symbol, the widget's name, and trailing
/// controls in the secondary style.
struct WidgetChromeHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 18, height: 18)
                .widgetAccentable()
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Capsule label for widget buttons. Standard pills are neutral; tinted and
/// selected pills use the system accent.
struct WidgetChromePill<Label: View>: View {
    enum Prominence {
        case standard
        case tinted
        case selected
    }

    var prominence: Prominence = .standard
    /// Icon-only pills use less horizontal padding.
    var iconOnly = false
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .frame(height: WidgetChrome.pillHeight)
            .padding(.horizontal, iconOnly ? 2 : 7)
            .background(background, in: Capsule())
    }

    private var foreground: AnyShapeStyle {
        prominence == .standard ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint)
    }

    private var background: AnyShapeStyle {
        switch prominence {
        case .standard:
            return AnyShapeStyle(.fill.secondary)
        case .tinted:
            return AnyShapeStyle(.tint.opacity(0.14))
        case .selected:
            return AnyShapeStyle(.tint.opacity(0.28))
        }
    }
}
