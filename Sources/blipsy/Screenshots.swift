import SwiftUI
import AppKit

/// Renders the real SwiftUI views offscreen to PNGs for the README.
/// Invoked with `blipsy --screenshots <dir>`.
@MainActor
enum Screenshots {
    static func render(to directory: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // A believable past hour: mostly healthy, a lossy patch, a brief outage.
        let now = Date()
        var history: [Sample] = []
        for i in 0..<180 {
            let t = now.addingTimeInterval(-Double(180 - i) * 20)   // ~ every 20s for an hour
            let state: ConnectionState
            switch i {
            case 70...78:   state = .lossy
            case 120...123: state = .down
            default:        state = .connected
            }
            let ms: Double? = state == .down ? nil : Double(16 + (i % 9) * 3)
            history.append(Sample(date: t, state: state, latencyMS: ms))
        }

        // Single-target panel (metrics grid + chart).
        let single = AppModel()
        single.loadPreview(
            statuses: [status("8.8.8.8", .connected, 18.4, 0)],
            history: history, lastChecked: now)
        save(panelView(single), to: "\(directory)/panel-single.png")

        // Hero: a desktop with the menu bar and the panel dropped open beneath the icon.
        save(glanceView(single), to: "\(directory)/glance.png")

        // 1280x640 social preview card for GitHub.
        save(socialCard(single), to: "\(directory)/social.png")

        // Multi-target panel (rows + chart), showing a flaky one.
        let multi = AppModel()
        multi.loadPreview(statuses: [
            status("8.8.8.8", .connected, 18.4, 0),
            status("1.1.1.1", .connected, 22.1, 0),
            status("https://github.com", .lossy, 143, 0.6),
        ], history: history, lastChecked: now)
        save(panelView(multi), to: "\(directory)/panel-multi.png")

        // Settings and About use AppKit-backed controls that ImageRenderer can't
        // draw, so render static look-alikes for the screenshots.
        save(framed(settingsPreview), to: "\(directory)/settings.png")
        save(framed(aboutPreview), to: "\(directory)/about.png")

        print("wrote screenshots to \(directory)/")
    }

    // MARK: - Hero (menu bar + open panel over a desktop)

    private static func glanceView(_ model: AppModel) -> some View {
        ZStack(alignment: .top) {
            // Desktop wallpaper.
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.30, blue: 0.49),
                         Color(red: 0.10, green: 0.12, blue: 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [Color(red: 0.42, green: 0.55, blue: 1.0).opacity(0.35), .clear],
                               center: .init(x: 0.2, y: 1.1), startRadius: 0, endRadius: 520))

            VStack(spacing: 0) {
                menuBar
                HStack(alignment: .top) {
                    Spacer()
                    MenuPanelView(model: model, onSettings: {}, onAbout: {}, onQuit: {})
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10)))
                        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
                        .padding(.top, 8)
                        .padding(.trailing, 10)
                }
                Spacer()
            }
        }
        .frame(width: 900, height: 560)
    }

    private static var menuBar: some View {
        HStack(spacing: 15) {
            Text("Finder").font(.system(size: 13, weight: .semibold))
            Text("File").font(.system(size: 13))
            Text("Edit").font(.system(size: 13))
            Text("View").font(.system(size: 13))
            Spacer()
            Image(systemName: "battery.100percent")
            Image(systemName: "wifi")
            Image(systemName: "magnifyingglass")
            Image(systemName: "switch.2")
            HStack(spacing: 6) {
                Circle().fill(Color(nsColor: .systemGreen)).frame(width: 9, height: 9)
                Text("18 ms").font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
            .foregroundStyle(.white)
            Text("Fri 12:33").font(.system(size: 13)).monospacedDigit()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color.white.opacity(0.82))
        .foregroundStyle(.black.opacity(0.82))
    }

    // MARK: - Social preview card (1280x640)

    private static func socialCard(_ model: AppModel) -> some View {
        ZStack(alignment: .top) {
            // Desktop wallpaper.
            LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.12),
                                    Color(red: 0.10, green: 0.13, blue: 0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(RadialGradient(
                    colors: [Color(nsColor: .systemGreen).opacity(0.26), .clear],
                    center: .init(x: 0.12, y: 1.05), startRadius: 0, endRadius: 560))

            VStack(spacing: 0) {
                // The macOS menu bar with the blipsy item highlighted.
                menuBar
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 18) {
                        appMark
                        Text("blipsy")
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Up, flaky, or down, right in your menu bar.")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.72))
                        HStack(spacing: 22) {
                            legend(Color(nsColor: .systemGreen), "Connected")
                            legend(Color(nsColor: .systemYellow), "Packet loss")
                            legend(Color(nsColor: .systemRed), "Down")
                        }
                        .padding(.top, 6)
                    }
                    .padding(.leading, 76)
                    .padding(.top, 64)

                    Spacer(minLength: 20)

                    // Panel dropped open from the menu bar item on the right.
                    MenuPanelView(model: model, onSettings: {}, onAbout: {}, onQuit: {})
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10)))
                        .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
                        .padding(.top, 12)
                        .padding(.trailing, 44)
                }
                Spacer()
            }
        }
        .frame(width: 1280, height: 640)
    }

    private static var appMark: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.9)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 88, height: 88)
            .overlay(
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.55, green: 0.93, blue: 0.66),
                                 Color(nsColor: .systemGreen),
                                 Color(red: 0.12, green: 0.6, blue: 0.26)],
                        center: .init(x: 0.38, y: 0.34), startRadius: 2, endRadius: 46))
                    .frame(width: 50, height: 50)
                    .overlay(Ellipse().fill(.white.opacity(0.4)).frame(width: 24, height: 13).offset(y: -7))
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    private static func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).font(.system(size: 17)).foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Static previews (no AppKit-backed controls)

    private static var settingsPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                LabeledContent("Ping target") {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldBox("8.8.8.8, 1.1.1.1, https://github.com", width: nil)
                        Text("An IP, hostname, or https:// URL. Comma-separate to watch several at once.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent("Check every") {
                    HStack(spacing: 6) { fieldBox("2", width: 54); stepperBox(); Text("seconds").foregroundStyle(.secondary) }
                }
                LabeledContent("Probes per check") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) { fieldBox("5", width: 54); stepperBox() }
                        Text("Packet loss is measured across the probes in each check.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledContent("Show latency in menu bar") { switchBox(on: true) }
                LabeledContent("Notify on state change") { switchBox(on: true) }
                LabeledContent("Notification sound") { menuBox("Default") }
                LabeledContent("Launch at login") { switchBox(on: false) }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                pillButton("Revert", filled: false)
                pillButton("Save", filled: true)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 430)
    }

    private static var aboutPreview: some View {
        VStack(spacing: 10) {
            Circle().fill(Color(nsColor: .systemGreen)).frame(width: 46, height: 46)
                .shadow(color: Color(nsColor: .systemGreen).opacity(0.4), radius: 4)
            Text("blipsy").font(.system(size: 22, weight: .bold))
            Text("Version 0.1.0").font(.subheadline).foregroundStyle(.secondary)
            Text("A quiet menu bar internet connection monitor.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Text("View on GitHub").foregroundStyle(Color(nsColor: .linkColor))
                Text("Report an issue").foregroundStyle(Color(nsColor: .linkColor))
            }.font(.callout)
            Text("Made by @moharnadreza").font(.caption).foregroundStyle(Color(nsColor: .linkColor)).padding(.top, 2)
        }
        .padding(24).frame(width: 300)
    }

    private static func fieldBox(_ text: String, width: CGFloat?) -> some View {
        HStack { Text(text).font(.system(size: 13)); if width == nil { Spacer(minLength: 0) } }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.15)))
    }

    private static func stepperBox() -> some View {
        RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlColor)).frame(width: 22, height: 22)
            .overlay(Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.15)))
    }

    private static func menuBox(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 13))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlColor)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black.opacity(0.15)))
    }

    private static func switchBox(on: Bool) -> some View {
        Capsule().fill(on ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray).opacity(0.6))
            .frame(width: 38, height: 22)
            .overlay(Circle().fill(.white).frame(width: 18, height: 18).padding(2),
                     alignment: on ? .trailing : .leading)
    }

    private static func pillButton(_ title: String, filled: Bool) -> some View {
        Text(title).font(.system(size: 13))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(filled ? Color.accentColor : Color(nsColor: .controlColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(filled ? 0 : 0.15)))
    }

    // MARK: - View wrappers

    private static func panelView(_ model: AppModel) -> some View {
        MenuPanelView(model: model, onSettings: {}, onAbout: {}, onQuit: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12)))
            .padding(28)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    private static func framed<V: View>(_ view: V) -> some View {
        view
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12)))
            .padding(28)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Helpers

    private static func status(_ raw: String, _ state: ConnectionState, _ ms: Double?, _ loss: Double) -> TargetStatus {
        TargetStatus(target: Target(raw: raw)!, state: state, latencyMS: ms, loss: loss)
    }

    private static func save<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("failed to render \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
