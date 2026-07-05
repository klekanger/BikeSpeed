import SwiftUI

struct StatRow: View {
    let systemImage: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                Text(label)
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    ZStack {
        Color.black
        StatRow(systemImage: "speedometer", label: "Average speed", value: "24.7 km/h")
            .padding()
    }
    .ignoresSafeArea()
}
