import SwiftUI

/// A tapered needle shape pointing straight up, meant to be rotated with `.rotationEffect`
/// anchored at its own center (which coincides with the gauge pivot).
struct NeedleView: View {
    var body: some View {
        NeedleShape()
            .fill(Color.orange)
            .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1.5)
    }
}

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let tipLength = rect.height * 0.42
        let tailLength = rect.height * 0.06
        let baseWidth = rect.width * 0.055

        var path = Path()
        path.move(to: CGPoint(x: center.x - baseWidth / 2, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y - tipLength))
        path.addLine(to: CGPoint(x: center.x + baseWidth / 2, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + tailLength))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black
        NeedleView()
            .frame(width: 300, height: 300)
            .rotationEffect(.degrees(45))
    }
    .ignoresSafeArea()
}
