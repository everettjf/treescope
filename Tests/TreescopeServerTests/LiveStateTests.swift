#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import AppKit
import SwiftUI
import Combine
@testable import TreescopeServer
import TreescopeProtocol

/// Verifies the genuinely-live introspection path: a hosting view's
/// `@ObservedObject` holds the model by reference, so reflecting it surfaces the
/// model's CURRENT `@Published` fields — and mutating the model then re-reflecting
/// shows the new values. (Value-typed `@State` only yields its declared value;
/// see `LiveProperty` for why — that's asserted too.)
final class LiveStateTests: XCTestCase {

    final class Model: ObservableObject { @Published var ticks: Int; init(_ t: Int) { ticks = t } }

    private struct Screen: View {
        @State var count = 41
        @ObservedObject var model: Model
        var body: some View {
            VStack {
                Text(verbatim: "Count \(count)")
                Text(verbatim: "Ticks \(model.ticks)")
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

    private func attribute(_ root: ViewNode, titled prefix: String) -> Attribute? {
        for node in allNodes(root) {
            for section in node.sections {
                if let a = section.attributes.first(where: { $0.title.hasPrefix(prefix) }) { return a }
            }
        }
        return nil
    }

    @MainActor
    func testStateValueShowsDeclaredValue() throws {
        let hosting = host(Screen(model: Model(7)))
        let node = try XCTUnwrap(reflect(hosting))
        // @State count surfaces as an attribute with its declared value.
        let count = try XCTUnwrap(attribute(node, titled: "count"))
        XCTAssertEqual(count.value, .integer(41))
        // It is NOT marked live (value-typed state is not graph-backed here).
        XCTAssertFalse(count.title.contains("(live)"), "value @State must not claim live: \(count.title)")
    }

    @MainActor
    func testObservedObjectFieldsAreLiveAcrossMutation() throws {
        let model = Model(7)
        let hosting = host(Screen(model: model))

        // The @ObservedObject model expands into nested fields, marked live.
        var modelAttr = try XCTUnwrap(attribute(reflect(hosting)!, titled: "model"))
        XCTAssertTrue(modelAttr.title.contains("(live)"), "model should be marked live: \(modelAttr.title)")
        func ticks(_ a: Attribute) -> AttributeValue? {
            if case .nested(let fields) = a.value { return fields.first { $0.title == "ticks" }?.value }
            return nil
        }
        XCTAssertEqual(ticks(modelAttr), .integer(7), "initial field: \(modelAttr.value)")

        // Mutate the live model, pump the runloop, re-reflect: the captured field
        // must reflect the NEW value — proving we read the shared live object.
        model.ticks = 99
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        modelAttr = try XCTUnwrap(attribute(reflect(hosting)!, titled: "model"))
        XCTAssertEqual(ticks(modelAttr), .integer(99), "live field not updated: \(modelAttr.value)")
    }
}
#endif
