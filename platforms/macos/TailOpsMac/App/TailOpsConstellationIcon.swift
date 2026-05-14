import SwiftUI
import TailOpsCore

struct TailOpsConstellationIcon: View {
    let trafficLight: TailnetSummary.TrafficLight

    var body: some View {
        Canvas { context, size in
            let points = constellationPoints(in: size)
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            path.addLine(to: points[2])
            path.addLine(to: points[0])
            path.move(to: points[2])
            path.addLine(to: points[3])
            path.addLine(to: points[4])
            path.move(to: points[1])
            path.addLine(to: points[4])

            context.stroke(
                path,
                with: .color(.primary.opacity(0.76)),
                style: StrokeStyle(lineWidth: max(size.width * 0.075, 1.2), lineCap: .round, lineJoin: .round)
            )

            for (index, point) in points.enumerated() {
                let isStatusNode = index == 3
                let diameter = size.width * (isStatusNode ? 0.29 : 0.21)
                let rect = CGRect(
                    x: point.x - diameter / 2,
                    y: point.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isStatusNode ? statusColor : .primary)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var statusColor: Color {
        switch trafficLight {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .offline:
            return .red
        }
    }

    private func constellationPoints(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width * 0.20, y: size.height * 0.66),
            CGPoint(x: size.width * 0.36, y: size.height * 0.28),
            CGPoint(x: size.width * 0.64, y: size.height * 0.40),
            CGPoint(x: size.width * 0.80, y: size.height * 0.18),
            CGPoint(x: size.width * 0.78, y: size.height * 0.78)
        ]
    }
}

#if DEBUG
#Preview("Constellation Icon") {
    HStack(spacing: 18) {
        TailOpsConstellationIcon(trafficLight: .healthy)
        TailOpsConstellationIcon(trafficLight: .warning)
        TailOpsConstellationIcon(trafficLight: .offline)
    }
    .frame(width: 120, height: 34)
    .padding()
}
#endif
