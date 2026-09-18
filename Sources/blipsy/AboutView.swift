import SwiftUI

/// Small About window - app name, version, and a link to the GitHub repo.
struct AboutView: View {
    static let repoURL = URL(string: "https://github.com/moharnadreza/blipsy")!
    static let issuesURL = URL(string: "https://github.com/moharnadreza/blipsy/issues")!
    static let authorURL = URL(string: "https://github.com/moharnadreza")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: .systemGreen))
                .frame(width: 46, height: 46)
                .shadow(color: Color(nsColor: .systemGreen).opacity(0.4), radius: 4)

            Text("blipsy")
                .font(.system(size: 22, weight: .bold))

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A quiet menu bar internet connection monitor.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Link("View on GitHub", destination: Self.repoURL)
                Link("Report an issue", destination: Self.issuesURL)
            }
            .font(.callout)

            Link("Made by @moharnadreza", destination: Self.authorURL)
                .font(.caption)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}
