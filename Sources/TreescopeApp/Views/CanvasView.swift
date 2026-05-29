import SwiftUI
import TreescopeViewerCore
import TreescopeProtocol

struct CanvasView: View {
    @EnvironmentObject var session: InspectorSession
    @Binding var showWireframe: Bool
    @Binding var showSnapshots: Bool
    @Binding var exploded: Bool
    @Binding var zoom: Double

    var body: some View {
        ZStack {
            Color(white: 0.12).ignoresSafeArea()

            if let scene = sceneModel {
                GeometryReader { geo in
                    canvasContent(scene: scene, available: geo.size)
                }
            } else {
                ContentUnavailablePlaceholder()
            }

            VStack {
                Spacer()
                zoomControls
            }
            .padding()
        }
        .task(id: backgroundNodeID) {
            if let id = backgroundNodeID { await session.loadSnapshotImage(for: id) }
        }
        .task(id: session.selectedNodeID) {
            if let id = session.selectedNodeID { await session.loadSnapshotImage(for: id) }
        }
    }

    // MARK: Scene assembly

    private struct SceneModel {
        let size: CGSize
        let flat: [CanvasFlatNodeModel]
        let maxDepth: Int
    }

    private var sceneModel: SceneModel? {
        guard let roots = session.snapshot?.roots, !roots.isEmpty else { return nil }
        var flat: [CanvasFlatNodeModel] = []
        var maxW: CGFloat = 1
        var maxH: CGFloat = 1
        var maxDepth = 0
        func walk(_ node: ViewNode, depth: Int) {
            let r = node.frame.cgRect
            flat.append(CanvasFlatNodeModel(id: node.id, node: node, depth: depth, frame: r))
            maxW = max(maxW, r.maxX)
            maxH = max(maxH, r.maxY)
            maxDepth = max(maxDepth, depth)
            for child in node.children { walk(child, depth: depth + 1) }
        }
        roots.forEach { walk($0, depth: 0) }
        return SceneModel(size: CGSize(width: maxW, height: maxH), flat: flat, maxDepth: maxDepth)
    }

    /// The biggest node carrying a snapshot, used as the canvas background.
    private var backgroundNodeID: String? {
        guard let flat = sceneModel?.flat else { return nil }
        return flat
            .filter { $0.node.snapshotID != nil }
            .max { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }?
            .node.snapshotID
    }

    // MARK: Drawing

    private func canvasContent(scene: SceneModel, available: CGSize) -> some View {
        let fit = min(available.width / scene.size.width,
                      available.height / scene.size.height) * 0.88
        let scale = max(0.05, fit * zoom)
        let scaledSize = CGSize(width: scene.size.width * scale, height: scene.size.height * scale)
        let originX = (available.width - scaledSize.width) / 2
        let originY = (available.height - scaledSize.height) / 2
        let explodeStep: CGFloat = exploded ? 26 : 0

        return ZStack(alignment: .topLeading) {
            // Background snapshot of the primary node.
            if showSnapshots, let id = backgroundNodeID, let img = session.snapshotImages[id] {
                ImageDecoder.image(from: img)?
                    .resizable()
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .position(x: originX + scaledSize.width / 2, y: originY + scaledSize.height / 2)
                    .opacity(0.95)
            }

            ForEach(scene.flat) { item in
                NodeOverlay(item: item,
                            scale: scale,
                            origin: CGPoint(x: originX, y: originY),
                            explodeStep: explodeStep,
                            showWireframe: showWireframe,
                            showSnapshots: showSnapshots,
                            isSelected: session.selectedNodeID == item.id,
                            snapshot: session.selectedNodeID == item.id ? session.snapshotImages[item.node.snapshotID ?? ""] : nil)
                    .onTapGesture {
                        session.selectedNodeID = item.id
                        Task { await session.highlightOnDevice(nodeID: item.id) }
                    }
            }
        }
        .rotation3DEffect(.degrees(exploded ? 20 : 0), axis: (x: 0.1, y: 1, z: 0), perspective: 0.4)
        .animation(.easeInOut, value: exploded)
        .animation(.easeInOut, value: zoom)
    }

    private var zoomControls: some View {
        HStack(spacing: 12) {
            Button { zoom = max(0.2, zoom - 0.2) } label: { Image(systemName: "minus.magnifyingglass") }
            Slider(value: $zoom, in: 0.2...4).frame(width: 160)
            Button { zoom = min(4, zoom + 0.2) } label: { Image(systemName: "plus.magnifyingglass") }
            Button { zoom = 1 } label: { Text("100%").font(.caption.monospacedDigit()) }
            Text(String(format: "%.0f%%", zoom * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .buttonStyle(.plain)
    }
}

private struct NodeOverlay: View {
    let item: CanvasFlatNode
    let scale: CGFloat
    let origin: CGPoint
    let explodeStep: CGFloat
    let showWireframe: Bool
    let showSnapshots: Bool
    let isSelected: Bool
    let snapshot: SnapshotImage?

    var body: some View {
        let w = max(1, item.frame.width * scale)
        let h = max(1, item.frame.height * scale)
        let depthOffset = explodeStep * CGFloat(item.depth)
        let x = origin.x + item.frame.midX * scale + depthOffset
        let y = origin.y + item.frame.midY * scale - depthOffset * 0.4

        ZStack {
            if showSnapshots, isSelected, let snapshot, let image = ImageDecoder.image(from: snapshot) {
                image.resizable().frame(width: w, height: h)
            }
            if showWireframe || isSelected {
                Rectangle()
                    .stroke(strokeColor, lineWidth: isSelected ? 2 : 0.5)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                    .frame(width: w, height: h)
            }
        }
        .frame(width: w, height: h)
        .position(x: x, y: y)
        .help(item.node.displayName)
    }

    private var strokeColor: Color {
        isSelected ? Color.accentColor : item.node.kind.tintColor.opacity(0.5)
    }
}

// Mirrors CanvasView.FlatNode for use by the standalone overlay view.
typealias CanvasFlatNode = CanvasFlatNodeModel
struct CanvasFlatNodeModel: Identifiable {
    let id: String
    let node: ViewNode
    let depth: Int
    let frame: CGRect
}

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No hierarchy captured")
                .foregroundStyle(.secondary)
        }
    }
}
