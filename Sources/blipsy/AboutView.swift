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
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(title: "About")
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("A quiet menu bar internet connection monitor.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link("View on GitHub", destination: Self.repoURL)
                    Link("Report an issue", destination: Self.issuesURL)
                }
                .font(.system(size: 12))

                Link("Made by @moharnadreza", destination: Self.authorURL)
                    .font(.system(size: 11))
                    .padding(.top, 2)
            }
            .padding(16)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
