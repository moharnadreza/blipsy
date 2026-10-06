import SwiftUI

/// The blipsy app mark: the glossy green dot from the app icon.
struct BrandMark: View {
    var size: CGFloat = 22
    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(red: 0.58, green: 0.93, blue: 0.68),
                         Color(nsColor: .systemGreen),
                         Color(red: 0.12, green: 0.6, blue: 0.26)],
                center: .init(x: 0.38, y: 0.34), startRadius: 1, endRadius: size * 0.65))
            .frame(width: size, height: size)
            .overlay(Ellipse().fill(.white.opacity(0.4))
                .frame(width: size * 0.5, height: size * 0.28).offset(y: -size * 0.14))
            .shadow(color: Color(nsColor: .systemGreen).opacity(0.35), radius: size * 0.14)
    }
}

/// Shared window header so every blipsy window (Settings, About, Outage History)
/// opens with the same identity lockup and spacing.
struct BrandHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("blipsy")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
