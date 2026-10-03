import SwiftUI

public struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = -1.0

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.5),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.8)
                    .offset(x: phase * geo.size.width * 1.5)
                    .blendMode(.screen)
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.8)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

public extension View {
    func shimmering() -> some View {
        modifier(ShimmerEffect())
    }
}

public struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    public init(color: Color = CodexTheme.accentGreen) {
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isPulsing ? 0.3 : 0.7))
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            isPulsing = true
        }
    }
}
