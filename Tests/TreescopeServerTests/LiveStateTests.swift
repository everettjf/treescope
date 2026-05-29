#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import AppKit
import SwiftUI
@testable import TreescopeServer
import TreescopeProtocol

/// Verifies the AttributeGraph "live value" path: once a SwiftUI view is hosted,
/// reflecting it surfaces the CURRENT `@State`/`@ObservedObject` values (read via
/// the installed graph location), not just the initial Mirror seed.
final class LiveStateTests: XCTestCase {

    final class Model: ObservableObject { @Published var ticks: Int; init(_ t: Int) { ticks = t } }

    private struct Screen: View {
        @State var count = 41
        @ObservedObject var model: Model
        var body: some View {
            VStack {
                Text("Count \(count)")
                Text("Ticks \(model.ticks)")
            }
        }
    }

    @MainActor
    private func host<V: View>(_ view: V) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return hosting
    }

    @MainActor
    private func reflect(_ hosting: NSView) -> ViewNode? {
        guard let root = SwiftUIReflector.findRootView(in: hosting) else { return nil }
        return SwiftUIReflector().reflect(rootValue: root)
    }

    private func allNodes(_ root: ViewNode) -> [ViewNode] {
        var out: [ViewNode] = []; root.forEachDepthFirst { out.append($0) }; return out
    }

    private func texts(_ root: ViewNode) -> [String] {
        allNodes(root).filter { $0.displayName == "Text" }.compactMap(\.label)
    }

    private func attribute(_ root: ViewNode, titled prefix: String) -> Attribute? {
        for node in allNodes(root) {
            for section in node.sections {
                if let a = section.attributes.first(where: { $0.title.hasPrefix(prefix) }) { return a }
            }
        }
        return nil
    }

    @MainActor
    func testStateValueIsReadAndMarkedLive() throws {
        let hosting = host(Screen(model: Model(7)))
        let node = try XCTUnwrap(reflect(hosting))
        // The @State count is surfaced as an attribute, labelled live.
        let count = try XCTUnwrap(attribute(node, titled: "count"))
        XCTAssertEqual(count.value, .integer(41))
        XCTAssertTrue(count.title.contains("(live)"), "expected live marker, got \(count.title)")
    }

    @MainActor
    func testObservedObjectFieldsExpandAndAreLive() throws {
        let model = Model(7)
        let hosting = host(Screen(model: model))

        // Initially the body reflects the seed values.
        var node = try XCTUnwrap(reflect(hosting))
        XCTAssertTrue(texts(node).contains("Ticks 7"), "got \(texts(node))")

        // The model attribute expands into nested fields (ticks).
        let modelAttr = try XCTUnwrap(attribute(node, titled: "model"))
        if case .nested(let fields) = modelAttr.value {
            XCTAssertTrue(fields.contains { $0.title == "ticks" && $0.value == .integer(7) }, "got \(fields)")
        } else {
            XCTFail("expected nested model fields, got \(modelAttr.value)")
        }

        // Mutate the live model, pump the runloop, and re-reflect: the captured
        // tree must now show the NEW value (proving we read live, not the seed).
        model.ticks = 99
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        node = try XCTUnwrap(reflect(hosting))
        XCTAssertTrue(texts(node).contains("Ticks 99"), "live body not updated: \(texts(node))")
        let modelAttr2 = try XCTUnwrap(attribute(node, titled: "model"))
        if case .nested(let fields) = modelAttr2.value {
            XCTAssertTrue(fields.contains { $0.title == "ticks" && $0.value == .integer(99) },
                          "live field not updated: \(fields)")
        } else {
            XCTFail("expected nested model fields")
        }
    }
}
#endif
