import Cocoa
import SwiftUI

// The "Ring Gauge" logo: the same progress-ring shape the dashboard's own
// goal indicator will eventually use, promoted to the app's brand mark
// (see znotes/design.md §2). There's no real goal value to drive this yet,
// so `progress` is a fixed placeholder until the goal feature lands.

/// Bare ring — track + progress arc, no frame. Reused standalone or inside
/// `RingGaugeMark`'s tile.
struct RingGauge: View {
    @Environment(\.theme) private var theme
    var progress: Double = 0.72
    var lineWidth: CGFloat = 6
    var trackColor: Color? = nil
    var progressColor: Color? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor ?? theme.borderSoft, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(progressColor ?? theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The ring inside a small rounded "app icon" tile — used in the dashboard
/// header next to the "KeyStats" wordmark.
struct RingGaugeMark: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 30
    var progress: Double = 0.72

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [theme.surfaceRaised, theme.bg],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .overlay(
                RingGauge(progress: progress, lineWidth: size * 0.11)
                    .padding(size * 0.22)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Menu bar icon

/// macOS forces status-bar icons to render as system-colored template
/// images regardless of app theme, so this draws in plain black — only the
/// alpha channel of a template image is ever used.
enum MenuBarIcon {
    static func ringGaugeTemplate(size: CGFloat = 18, progress: Double = 0.72, lineWidth: CGFloat = 2.4) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = lineWidth / 2 + 1
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - inset

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()

            let startAngle: CGFloat = 90
            let endAngle = startAngle - CGFloat(360 * max(0, min(1, progress)))
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
