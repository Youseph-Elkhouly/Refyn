import SwiftUI

// MARK: - Tokens

/// Design tokens for the monochrome UI. Every color, size, radius and duration used by a view comes from here.
enum Theme {
    // Color
    static let background = Color(hex: 0x090909)
    static let surface = Color(hex: 0x141414)
    static let input = Color(hex: 0x1B1B1B)
    static let border = Color(hex: 0x292929)
    static let hover = Color(hex: 0x242424)
    static let text = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0xA1A1A1)
    static let textMuted = Color(hex: 0x666666)
    static let primaryFill = Color(hex: 0xFFFFFF)
    static let primaryText = Color(hex: 0x090909)

    // Typography (system font; medium for headings, regular for body)
    static let title = Font.system(size: 15, weight: .medium)
    static let heading = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let editor = Font.system(size: 15)
    static let caption = Font.system(size: 11.5)
    static let mono = Font.system(size: 12.5, design: .monospaced)
    static let lineSpacing: CGFloat = 3

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let panel: CGFloat = 22
    }

    enum Motion {
        static let fast = 0.12
        static let base = 0.2
        static let slow = 0.28
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Motion

/// Eased animation that is skipped when Reduce Motion is on.
private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: Double
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeOut(duration: duration), value: value)
    }
}

extension View {
    func motion<V: Equatable>(_ duration: Double = Theme.Motion.base, value: V) -> some View {
        modifier(MotionModifier(duration: duration, value: value))
    }

    func hairlineBorder(_ radius: CGFloat = Theme.Radius.lg, color: Color = Theme.border) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(color, lineWidth: 1))
    }
}

// MARK: - Mark

/// The Refine symbol: a ring around a solid core.
struct RefineMark: View {
    var size: CGFloat = 12
    var color: Color = Theme.text
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: max(1.2, size / 9))
            Circle().fill(color).frame(width: size * 0.36, height: size * 0.36)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

enum ButtonKind { case primary, secondary, ghost }

struct RefineButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var loading = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, loading: loading)
    }

    struct StyledBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: ButtonKind
        let loading: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(Theme.heading)
                .opacity(loading ? 0 : 1)
                .overlay { if loading { ProgressView().controlSize(.small).colorScheme(kind == .primary ? .light : .dark) } }
                .padding(.horizontal, Theme.Space.md).frame(minHeight: 28)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(fill))
                .overlay { if kind == .secondary { RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(enabled ? Theme.border : Theme.border.opacity(0.6), lineWidth: 1) } }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .onHover { hovering = $0 }
                .motion(Theme.Motion.fast, value: hovering)
                .motion(Theme.Motion.fast, value: configuration.isPressed)
        }

        var foreground: Color {
            switch kind {
            case .primary: enabled ? Theme.primaryText : Theme.textMuted
            case .secondary: enabled ? Theme.text : Theme.textMuted
            case .ghost: enabled ? (hovering ? Theme.text : Theme.textSecondary) : Theme.textMuted
            }
        }

        var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                if !enabled { return loading ? Theme.primaryFill.opacity(0.9) : Theme.hover }
                return Theme.primaryFill.opacity(pressed ? 0.75 : hovering ? 0.88 : 1)
            case .secondary: return pressed ? Theme.hover : hovering && enabled ? Theme.hover : Theme.surface
            case .ghost: return hovering && enabled ? Theme.hover : .clear
            }
        }
    }
}

/// Button with an optional SF Symbol and a loading state.
struct RButton: View {
    let title: String
    var symbol: String?
    var kind: ButtonKind = .secondary
    var loading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11.5, weight: .medium)) }
                Text(title)
            }
        }
        .buttonStyle(RefineButtonStyle(kind: kind, loading: loading))
        .disabled(loading)
    }
}

/// Monochrome icon button with a 28pt hit target and a tooltip.
struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(!enabled ? Theme.textMuted : active || hovering ? Theme.text : Theme.textSecondary)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(active || (hovering && enabled) ? Theme.hover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.fast, value: hovering)
        .accessibilityLabel(help)
    }
}

// MARK: - Inputs

struct RTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(mono ? Theme.mono : Theme.body)
        .focused($focused)
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
        .hairlineBorder(Theme.Radius.md, color: focused ? Theme.textMuted : Theme.border)
        .motion(Theme.Motion.fast, value: focused)
    }
}

/// Borderless multi-line editor with a placeholder.
struct REditor: View {
    @Binding var text: String
    var placeholder = ""
    var font: Font = Theme.editor
    var inset: CGFloat = 0
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        ZStack(alignment: .topLeading) {
            editor
            if text.isEmpty {
                Text(placeholder).font(font).foregroundStyle(Theme.textMuted)
                    .padding(.leading, inset + 5).padding(.top, inset)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var editor: some View {
        let base = TextEditor(text: $text).font(font).lineSpacing(Theme.lineSpacing).scrollContentBackground(.hidden).padding(inset)
        if let focus { base.focused(focus) } else { base }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(Theme.body)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textMuted) }
                    .buttonStyle(.plain).help("Clear search").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
        .hairlineBorder(Theme.Radius.md)
    }
}

/// Compact segmented selector.
struct Segmented<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    @State private var hovered: T?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(label(option)).font(Theme.caption.weight(.medium))
                        .padding(.horizontal, 10).frame(minHeight: 22)
                        .foregroundStyle(selected ? Theme.text : hovered == option ? Theme.textSecondary : Theme.textMuted)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(selected ? Theme.hover : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? option : nil }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.input))
        .hairlineBorder(Theme.Radius.md)
        .motion(Theme.Motion.fast, value: selection)
    }
}

struct RToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
            .tint(Theme.text)
            .accessibilityLabel(title)
    }
}

// MARK: - Structure

struct SectionHeader: View {
    let title: String
    var detail: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.heading).foregroundStyle(Theme.text)
            if let detail { Text(detail).font(Theme.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Muted label above a block of text; sentence case, not uppercase.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Theme.caption.weight(.medium)).foregroundStyle(Theme.textMuted) }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1).accessibilityHidden(true) }
}

/// A bordered group of settings rows.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.surface))
            .hairlineBorder()
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var divider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.body).foregroundStyle(Theme.text)
                    if let detail { Text(detail).font(Theme.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: Theme.Space.md)
                trailing
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if divider { Hairline() }
        }
    }
}

// MARK: - Status, empty and loading states

enum StatusKind { case ready, busy, idle }

struct StatusIndicator: View {
    let kind: StatusKind
    var label: String?

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .ready: Circle().fill(Theme.text).frame(width: 6, height: 6)
            case .busy: ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 10, height: 10)
            case .idle: Circle().stroke(Theme.textMuted, lineWidth: 1).frame(width: 6, height: 6)
            }
            if let label { Text(label).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.textMuted)
            Text(title).font(Theme.heading).foregroundStyle(Theme.text)
            if let detail { Text(detail).font(Theme.caption).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
            if let actionTitle, let action { RButton(title: actionTitle, action: action).padding(.top, Theme.Space.xs) }
        }
        .frame(maxWidth: 280).padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingState: View {
    let label: String
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            ProgressView().controlSize(.small)
            Text(label).font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

/// Keyboard hint such as "⌘↩".
struct KeyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct Waveform: View {
    let levels: [Float]
    var color: Color = Theme.text
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(color).frame(width: 2, height: max(2, CGFloat(level) * 16))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}
