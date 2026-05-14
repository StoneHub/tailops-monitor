import SwiftUI
import TailOpsCore

public struct PingSparklineView: View {
    private let samples: [TailnetPingSample]

    public init(samples: [TailnetPingSample]) {
        self.samples = samples
    }

    public var body: some View {
        GeometryReader { geometry in
            let points = chartPoints(in: geometry.size)

            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(.blue.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(color(for: samples[index].route).opacity(0.48))
                        .frame(width: 4, height: 4)
                        .position(point)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }

        let maxLatency = max(samples.map(\.latencyMilliseconds).max() ?? 1, 1)
        let horizontalStep = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0

        return samples.enumerated().map { index, sample in
            let normalized = min(max(sample.latencyMilliseconds / maxLatency, 0), 1)
            return CGPoint(
                x: CGFloat(index) * horizontalStep,
                y: size.height - (CGFloat(normalized) * size.height)
            )
        }
    }

    private func color(for route: TailnetPingRoute) -> Color {
        switch route {
        case .direct:
            return .green
        case .peerRelay:
            return .orange
        case .derp:
            return .blue
        case .unknown:
            return .secondary
        }
    }
}
