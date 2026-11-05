import RefineCore
import SwiftUI

struct NotchRootView: View {
    @Bindable var model: AppModel
    let geometry: () -> PanelController.Geometry

    var body: some View {
        let g = geometry()
        ZStack(alignment: .top) {
            shape(g).fill(Color.black)
            if model.isExpanded {
                ExpandedPanelView(model: model)
                    .padding(.top, g.hasNotch ? g.notchHeight : 0)
                    .background(Theme.background.clipShape(shape(g)))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                CollapsedPill(model: model, geometry: g)
                    .transition(.opacity)
            }
        }
        .clipShape(shape(g))
        .overlay(shape(g).stroke(model.isExpanded ? Theme.stroke : .clear, lineWidth: 1))
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.isExpanded)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    /// Flat top so the panel reads as growing out of the notch; rounded everywhere on displays without one.
    func shape(_ g: PanelController.Geometry) -> UnevenRoundedRectangle {
        let bottom: CGFloat = model.isExpanded ? 22 : (g.hasNotch ? 12 : 15)
        let top: CGFloat = g.hasNotch ? 0 : (model.isExpanded ? 22 : 15)
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }
}

struct CollapsedPill: View {
    let model: AppModel
    let geometry: PanelController.Geometry

    var body: some View {
        Button { model.onExpand() } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                if !geometry.hasNotch {
                    Text(model.current?.name ?? "Refine").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: geometry.hasNotch ? geometry.notchWidth : 4)
                status
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.current.map { "Refine — \($0.name)" } ?? "Refine")
    }

    @ViewBuilder var status: some View {
        switch model.voice.state {
        case .recording: Waveform(levels: Array(model.voice.levels.suffix(14)), color: Theme.danger)
        case .transcribing: ProgressView().controlSize(.mini)
        default:
            Circle().fill(model.current == nil ? Theme.tertiary : model.analysis == .running ? Theme.warning : Theme.success).frame(width: 6, height: 6)
        }
    }
}
