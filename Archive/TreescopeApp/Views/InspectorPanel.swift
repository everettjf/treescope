import SwiftUI
import TreescopeViewerCore
import TreescopeProtocol

struct InspectorPanel: View {
    @EnvironmentObject var session: InspectorSession

    var body: some View {
        if let node = session.selectedNode {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(node)
                    identitySection(node)
                    ForEach(node.sections) { section in
                        AttributeSectionView(nodeID: node.id, section: section)
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right").font(.title).foregroundStyle(.secondary)
                Text("Select a view").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ node: ViewNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind.symbolName)
                .font(.title2)
                .foregroundStyle(node.kind.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName).font(.headline)
                Text(node.className)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    private func identitySection(_ node: ViewNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            badgeRow(node)
            LabeledRow(title: "Frame", value: AttributeValue.rect(node.frame).displayString)
            LabeledRow(title: "Bounds", value: AttributeValue.rect(node.bounds).displayString)
            LabeledRow(title: "Opacity", value: String(format: "%.2f", node.opacity))
            if !node.children.isEmpty {
                LabeledRow(title: "Children", value: "\(node.children.count)")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func badgeRow(_ node: ViewNode) -> some View {
        HStack(spacing: 6) {
            Badge(text: node.kind.rawValue, color: node.kind.tintColor)
            if node.flags.contains(.hostsSwiftUI) { Badge(text: "SwiftUI", color: .orange) }
            if node.flags.contains(.hidden) { Badge(text: "hidden", color: .gray) }
            if node.flags.contains(.systemView) { Badge(text: "system", color: .gray) }
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct LabeledRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct AttributeSectionView: View {
    let nodeID: String
    let section: AttributeSection
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 4) {
                ForEach(section.attributes) { attr in
                    AttributeRow(nodeID: nodeID, attribute: attr)
                }
            }
            .padding(.top, 4)
        } label: {
            Text(section.title).font(.subheadline.weight(.semibold))
        }
    }
}

private struct AttributeRow: View {
    let nodeID: String
    let attribute: Attribute
    @EnvironmentObject var session: InspectorSession

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(attribute.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Spacer(minLength: 0)
            valueView
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var valueView: some View {
        switch attribute.value {
        case .bool(let b):
            if attribute.editable {
                Toggle("", isOn: Binding(
                    get: { b },
                    set: { newValue in commit(.bool(newValue)) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            } else {
                Image(systemName: b ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(b ? .green : .secondary)
            }
        case .color(let c):
            ColorSwatch(color: c, editable: attribute.editable) { newColor in
                commit(.color(newColor))
            }
        case .number, .integer, .string, .enumeration:
            if attribute.editable {
                EditableTextValue(value: attribute.value) { newValue in commit(newValue) }
            } else {
                valueText
            }
        case .nested(let attrs):
            NestedValue(attributes: attrs)
        default:
            valueText
        }
    }

    private var valueText: some View {
        Text(attribute.value.displayString)
            .font(.callout.monospaced())
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            .lineLimit(3)
    }

    private func commit(_ value: AttributeValue) {
        guard let keyPath = attribute.keyPath else { return }
        Task { await session.setAttribute(nodeID: nodeID, keyPath: keyPath, value: value) }
    }
}

private struct EditableTextValue: View {
    let value: AttributeValue
    let onCommit: (AttributeValue) -> Void
    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 140)
            .onSubmit { commit() }
            .onAppear { text = value.displayString }
    }

    private func commit() {
        switch value {
        case .number: if let d = Double(text) { onCommit(.number(d)) }
        case .integer: if let i = Int(text) { onCommit(.integer(i)) }
        case .enumeration: onCommit(.enumeration(text))
        default: onCommit(.string(text))
        }
    }
}

private struct ColorSwatch: View {
    let color: RGBAColor
    let editable: Bool
    let onChange: (RGBAColor) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if editable {
                ColorPicker("", selection: Binding(
                    get: { color.swiftUIColor },
                    set: { onChange(ColorBridge.rgba(from: $0)) }))
                    .labelsHidden()
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.swiftUIColor)
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4)))
            }
            Text(color.hexString).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}

private struct NestedValue: View {
    let attributes: [Attribute]
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(attributes) { attr in
                HStack {
                    Text(attr.title).font(.caption).foregroundStyle(.secondary)
                    Text(attr.value.displayString).font(.caption.monospaced())
                }
            }
        }
    }
}
