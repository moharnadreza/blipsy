import SwiftUI
import AppKit

/// A live, behind-window blur (native menu material) exposed to SwiftUI so it can
/// be clipped by a `clipShape`. Doing the material and rounding inside SwiftUI
/// keeps everything outside the rounded shape transparent, so no window backing
/// shows white behind the panel's corners.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
