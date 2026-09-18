import SwiftUI
import AppKit

/// The single Settings screen - classic macOS label-column form matching the
/// demo: right-aligned labels, controls in the second column, captions beneath.
///
/// Monitoring fields (target / interval / probes) edit a local draft and only
/// take effect on **Save**, so blipsy doesn't probe half-typed targets. Display
/// toggles apply instantly since they're harmless and re-render immediately.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @State private var targetsText: String
    @State private var interval: Int
    @State private var probeCount: Int

    init(settings: AppSettings) {
        self.settings = settings
        _targetsText = State(initialValue: settings.targetsText)
        _interval = State(initialValue: settings.interval)
        _probeCount = State(initialValue: settings.probeCount)
    }

    private var hasChanges: Bool {
        targetsText != settings.targetsText
            || interval != settings.interval
            || probeCount != settings.probeCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                LabeledContent("Ping target") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("", text: $targetsText, prompt: Text("e.g. 8.8.8.8"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        caption("An IP, hostname, or https:// URL. Comma-separate to watch several at once.")
                    }
                }

                LabeledContent("Check every") {
                    HStack(spacing: 6) {
                        TextField("", value: $interval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 54)
                        Stepper("", value: $interval, in: 1...3600)
                            .labelsHidden()
                        Text("seconds").foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Probes per check") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            TextField("", value: $probeCount, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 54)
                            Stepper("", value: $probeCount, in: 1...20)
                                .labelsHidden()
                        }
                        caption("Packet loss is measured across the probes in each check.")
                    }
                }

                Divider()

                Toggle("Show latency in menu bar", isOn: $settings.showLatency)
                Toggle("Notify on state change", isOn: $settings.notifyOnChange)

                Picker("Notification sound", selection: $settings.notificationSound) {
                    ForEach(AppSettings.soundChoices, id: \.self) { name in
                        Text(name == "None" ? "None (silent)" : name).tag(name)
                    }
                }
                .disabled(!settings.notifyOnChange)
                .onChange(of: settings.notificationSound) { newValue in
                    // Preview the chosen sound (Default/None have no preview).
                    if newValue != "None", newValue != "Default" {
                        NSSound(named: newValue)?.play()
                    }
                }

                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            .formStyle(.columns)
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button("Revert", action: revert)
                    .disabled(!hasChanges)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        guard hasChanges else { return }
        settings.applyMonitoring(targetsText: targetsText, interval: interval, probeCount: probeCount)
    }

    private func revert() {
        targetsText = settings.targetsText
        interval = settings.interval
        probeCount = settings.probeCount
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
