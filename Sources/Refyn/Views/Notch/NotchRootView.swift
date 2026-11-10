import RefineCore
import SwiftUI

/// The notch outline at one size. Everything visible is drawn or clipped by this shape, so width, height and
/// corner radius move as one animated value and no view has to lay out again on each frame.
struct NotchSurfaceShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(topRadius, bottomRadius)) }
        set { width = newValue.first.first; height = newValue.first.second; topRadius = newValue.second.first; bottomRadius = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: max(0, topRadius), bottomLeadingRadius: max(0, bottomRadius),
                               bottomTrailingRadius: max(0, bottomRadius), topTrailingRadius: max(0, topRadius), style: .continuous)
            .path(in: CGRect(x: rect.midX - width / 2, y: rect.minY, width: max(0, width), height: max(0, height)))
    }
}

struct NotchRootView: View {
    @Bindable var model: AppModel
    let geometry: () -> PanelController.Geometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = geometry()
        let expanded = model.isExpanded
        let compact = PanelController.compactSize(model: model, geometry: g)
        let panel = PanelController.panelSize(model: model, geometry: g)
        let size = expanded ? panel : compact
        let surface = shape(g, size: size)
        let spring = reduceMotion ? nil : Animation.spring(expanded ? Theme.Motion.surfaceOpen : Theme.Motion.surfaceClose)
        let colorCurve = motion(expanded ? Theme.Motion.surfaceColorToPanel : Theme.Motion.surfaceColorToNotch)
        // An overlay, so the fixed-size content can never size the root: the hosting view would center an oversized root and push the notch off the compact window.
        Color.clear.overlay(alignment: .top) { ZStack(alignment: .top) {
            surface.animation(colorCurve) {
                $0.foregroundStyle(expanded ? Theme.background : Theme.notch)
                    .shadow(color: .black.opacity(expanded ? 0.16 : 0), radius: 20, y: 8)
            }
            ZStack(alignment: .top) {
                CollapsedPill(model: model, geometry: g)
                    .frame(width: compact.width, height: compact.height)
                    .animation(motion(expanded ? Theme.Motion.compactContentOut : Theme.Motion.compactContentIn)) { $0.opacity(expanded ? 0 : 1) }
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)
                ExpandedPanelView(model: model)
                    .padding(.top, g.hasNotch ? g.notchHeight : 0)
                    .frame(width: panel.width, height: panel.height, alignment: .top)
                    .animation(motion(expanded ? Theme.Motion.panelContentIn : Theme.Motion.panelContentOut)) { $0.opacity(expanded ? 1 : 0) }
                    .allowsHitTesting(expanded)
                    .disabled(!model.panelContentEnabled)
                    .accessibilityHidden(!expanded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(surface)
            surface.stroke(lineWidth: 1).animation(colorCurve) { $0.foregroundStyle(expanded ? Theme.border : .clear) }
                .allowsHitTesting(false)
        } }
        .animation(spring, value: size)
        .preferredColorScheme(.light)
        .tint(Theme.text)
    }

    private func motion(_ animation: Animation) -> Animation? { reduceMotion ? nil : animation }

    /// Flat top so the panel reads as growing out of the notch; rounded everywhere on displays without one.
    func shape(_ g: PanelController.Geometry, size: CGSize) -> NotchSurfaceShape {
        let bottom: CGFloat = model.isExpanded ? Theme.Radius.panel : (g.hasNotch ? 12 : 15)
        let top: CGFloat = g.hasNotch ? 0 : (model.isExpanded ? Theme.Radius.panel : 15)
        return NotchSurfaceShape(width: size.width, height: size.height, topRadius: top, bottomRadius: bottom)
    }
}

struct CollapsedPill: View {
    let model: AppModel
    let geometry: PanelController.Geometry
    @State private var hovering = false

    var body: some View {
        Button { model.onExpand() } label: {
            HStack(spacing: 8) {
                RefynMark(size: 12, color: hovering ? Theme.notchText : Theme.notchTextSecondary)
                    .scaleEffect(hovering ? 1.1 : 1)
                if !geometry.hasNotch {
                    Text(model.current?.name ?? "Refyn").font(Theme.caption.weight(.medium)).foregroundStyle(Theme.notchTextSecondary).lineLimit(1)
                }
                Spacer(minLength: geometry.hasNotch ? geometry.notchWidth : 4)
                status
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.notchHover.opacity(hovering ? 0.9 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .colorScheme(.dark)
        .tint(Theme.notchText)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.base, value: hovering)
        .help(model.current.map { "Refyn — \($0.name)" } ?? "Refyn")
        .accessibilityLabel("Open Refyn")
    }

    @ViewBuilder var status: some View {
        switch model.voice.state {
        case .recording: Waveform(levels: Array(model.voice.levels.suffix(14)), color: Theme.notchText)
        case .transcribing: StatusIndicator(kind: .busy, dotColor: Theme.notchText, ringColor: Theme.notchTextMuted)
        default:
            StatusIndicator(kind: model.current == nil ? .idle : model.analysis == .running || model.isOptimizing ? .busy : .ready, dotColor: Theme.notchText, ringColor: Theme.notchTextMuted)
        }
    }
}
