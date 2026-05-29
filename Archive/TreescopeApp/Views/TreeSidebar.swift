import SwiftUI
import TreescopeViewerCore
import TreescopeProtocol

struct TreeSidebar: View {
    @EnvironmentObject var session: InspectorSession

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(session.displayRoots) { node in
                        NodeRow(node: node, depth: 0)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter views", text: $session.searchText)
                .textFieldStyle(.plain)
            if !session.searchText.isEmpty {
                Button { session.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: $session.hideSystemViews) {
                Image(systemName: "eye.slash")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Hide system views")
        }
        .padding(8)
    }
}

private struct NodeRow: View {
    let node: ViewNode
    let depth: Int
    @EnvironmentObject var session: InspectorSession
    @State private var hovering = false

    private var isExpanded: Bool { session.expandedNodeIDs.contains(node.id) }
    private var isSelected: Bool { session.selectedNodeID == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            rowContent
            if isExpanded {
                ForEach(node.children) { child in
                    NodeRow(node: child, depth: depth + 1)
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 4) {
            Button {
                toggleExpansion()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    .opacity(node.children.isEmpty ? 0 : 1)
            }
            .buttonStyle(.plain)

            Image(systemName: node.kind.symbolName)
                .foregroundStyle(node.kind.tintColor)
                .font(.caption)
                .frame(width: 16)

            Text(node.displayName)
                .font(.system(.body, design: node.kind.isSwiftUI ? .rounded : .default))
                .fontWeight(node.kind.isSwiftUI ? .medium : .regular)
                .lineLimit(1)

            if let subtitle = node.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if node.flags.contains(.hidden) {
                Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .padding(.leading, CGFloat(depth) * 14 + 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.25)
        } else if hovering {
            Color.primary.opacity(0.06)
        } else {
            Color.clear
        }
    }

    private func toggleExpansion() {
        if isExpanded { session.expandedNodeIDs.remove(node.id) }
        else { session.expandedNodeIDs.insert(node.id) }
    }

    private func select() {
        session.selectedNodeID = node.id
        Task { await session.highlightOnDevice(nodeID: node.id) }
    }
}
