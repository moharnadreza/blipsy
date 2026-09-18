import AppKit

// `--test` runs the pure-logic regression suite (no GUI, no network).
if CommandLine.arguments.contains("--test") {
    exit(TestRunner.run())
}

// `--selftest [host]` runs one ICMP burst and prints the result, then exits.
// Handy for verifying probing without a GUI session.
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run(arguments: CommandLine.arguments)
    exit(0)
}

// `--screenshots [dir]` renders the SwiftUI views to PNGs for the README.
if let idx = CommandLine.arguments.firstIndex(of: "--screenshots") {
    let dir = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : "docs"
    MainActor.assumeIsolated { Screenshots.render(to: dir) }
    exit(0)
}

// Process entry runs on the main thread; adopt the main actor so we can build
// the @MainActor delegate and app model.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu-bar-only agent, no Dock icon
    app.run()
}
