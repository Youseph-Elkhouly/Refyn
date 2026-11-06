import RefineCore
import SwiftUI

struct NotchRootView: View {
    @Bindable var model: AppModel
    let geometry: () -> PanelController.Geometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = geometry()
        ZStack(alignment: .top) {
            shape(g).fill(Color.black)
            if model.isExpanded {
                ExpandedPanelView(model: model)
                    .padding(.top, g.hasNotch ? g.notchHeight : 0)
                    .background(Theme.background.clipShape(shape(g)))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.975, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                    ))
            } else {
                CollapsedPill(model: model, geometry: g)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .clipShape(shape(g))
        .overlay(shape(g).stroke(model.isExpanded ? Theme.border : .clear, lineWidth: 1))
        .animation(reduceMotion ? nil : .timingCurve(0.18, 0.78, 0.22, 1, duration: Theme.Motion.panel), value: model.isExpanded)
        .preferredColorScheme(.dark)
        .tint(Theme.text)
    }

    /// Flat top so the panel reads as growing out of the notch; rounded everywhere on displays without one.
    func shape(_ g: PanelController.Geometry) -> UnevenRoundedRectangle {
        let bottom: CGFloat = model.isExpanded ? Theme.Radius.panel : (g.hasNotch ? 12 : 15)
        let top: CGFloat = g.hasNotch ? 0 : (model.isExpanded ? Theme.Radius.panel : 15)
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }
}

struct CollapsedPill: View {
    let model: AppModel
    let geometry: PanelController.Geometry
    @State private var hovering = false

    var body: some View {
        Button { model.onExpand() } label: {
            HStack(spacing: 8) {
                RefynMark(size: 12, color: hovering ? Theme.text : Theme.textSecondary)
                    .scaleEffect(hovering ? 1.1 : 1)
                if !geometry.hasNotch {
                    Text(model.current?.name ?? "Refyn").font(Theme.caption.weight(.medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: geometry.hasNotch ? geometry.notchWidth : 4)
                status
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface.opacity(hovering ? 0.9 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.base, value: hovering)
        .help(model.current.map { "Refyn — \($0.name)" } ?? "Refyn")
        .accessibilityLabel("Open Refyn")
    }

    @ViewBuilder var status: some View {
        switch model.voice.state {
        case .recording: Waveform(levels: Array(model.voice.levels.suffix(14)))
        case .transcribing: StatusIndicator(kind: .busy)
        default:
            StatusIndicator(kind: model.current == nil ? .idle : model.analysis == .running || model.isOptimizing ? .busy : .ready)
        }
    }
}
