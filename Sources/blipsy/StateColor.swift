import SwiftUI

/// The one place that maps a connection state to its SwiftUI color, so the
/// panel, timeline, and any future view stay consistent.
func stateColor(_ state: ConnectionState) -> Color {
    switch state {
    case .connected: return Color(nsColor: .systemGreen)
    case .lossy:     return Color(nsColor: .systemYellow)
    case .down:      return Color(nsColor: .systemRed)
    case .unknown:   return Color(nsColor: .systemGray)
    }
}
