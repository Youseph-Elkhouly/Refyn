import AppKit
import RefineCore
import SwiftUI

/// `Refyn --snapshot <dir>` renders the panel's main states to PNGs and exits. Used to check the UI
/// without screen-recording permission; it uses a throwaway database and never touches real data.
@MainActor
enum Snapshots {
    static func run(into dir: URL) async {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let tmp = FileManager.default.temporaryDirectory.appending(path: "refine-snapshot-\(UUID().uuidString)")
            let model = AppModel(store: try WorkspaceStore(databaseURL: tmp.appending(path: "db.sqlite")))
            let size = PanelController.expandedSize
            let geometry = PanelController.Geometry(hasNotch: true, notchWidth: 180, notchHeight: 32)

            model.isExpanded = false
            try render(NotchRootView(model: model, geometry: { geometry }), CGSize(width: 276, height: 32), dir.appending(path: "collapsed.png"))

            model.isExpanded = true
            model.input = "add pagination to the users endpoint in `src/server/index.ts`, don't break existing clients, and add tests"
            try render(NotchRootView(model: model, geometry: { geometry }), CGSize(width: size.width, height: size.height + 32), dir.appending(path: "compose.png"))

            model.plan = try await PromptOptimizer(provider: nil).optimize(.init(text: model.input, mode: .advanced))
            model.route = .result
            try render(NotchRootView(model: model, geometry: { geometry }), CGSize(width: size.width, height: size.height + 32), dir.appending(path: "result.png"))

            model.route = .compose
            model.mode = .custom
            try render(NotchRootView(model: model, geometry: { geometry }), CGSize(width: size.width, height: size.height + 32), dir.appending(path: "custom.png"))
            model.mode = .auto
            print("Snapshots written to \(dir.path)")
        } catch {
            print("Snapshot failed: \(error)")
        }
    }

    static func render<V: View>(_ view: V, _ size: CGSize, _ url: URL) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
