import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.051, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.08, blue: 0.11)
    static let raised = Color(red: 0.115, green: 0.108, blue: 0.145)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.69, green: 0.58, blue: 0.98)
    static let accentStrong = Color(red: 0.45, green: 0.33, blue: 0.80)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let success = Color(red: 0.42, green: 0.85, blue: 0.56)
    static let warning = Color(red: 0.98, green: 0.76, blue: 0.36)
    static let danger = Color(red: 0.97, green: 0.47, blue: 0.47)
    static let mono = Font.system(size: 12.5, design: .monospaced)
    static let label = Font.system(size: 10, weight: .semibold)
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.label).tracking(1.3).foregroundStyle(Theme.tertiary)
    }
}

/// Icon button used in the panel header and toolbars.
struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(active ? Theme.accent : hovering ? Theme.text : Theme.secondary)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? Theme.accent.opacity(0.14) : hovering ? Color.white.opacity(0.06) : .clear))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .accessibilityLabel(help)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(prominent ? Color.white : Theme.text)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(prominent ? Theme.accentStrong : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(prominent ? Theme.accent.opacity(0.5) : Theme.stroke))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.secondary
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12.5))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }
}

struct Waveform: View {
    let levels: [Float]
    var color: Color = Theme.accent
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(color).frame(width: 2, height: max(2, CGFloat(level) * 16))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}
