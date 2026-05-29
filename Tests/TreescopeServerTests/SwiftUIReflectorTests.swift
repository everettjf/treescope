#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import TreescopeServer
import TreescopeProtocol

private struct Badge: View {
    let count: Int
    var body: some View {
        HStack {
            Text("Items")
            Text("\(count)")
        }
    }
}

private struct Counter: View {
    @State private var value = 3
    var body: some View {
        VStack(spacing: 8) {
            Text("Counter")
            Badge(count: value)
        }
        .padding()
    }
}

final class SwiftUIReflectorTests: XCTestCase {

    private func reflect<V: View>(_ view: V) -> ViewNode? {
        SwiftUIReflector().reflect(rootValue: view)
    }

    private func allNodes(_ root: ViewNode) -> [ViewNode] {
        var out: [ViewNode] = []
        root.forEachDepthFirst { out.append($0) }
        return out
    }

    func testIsViewDetection() {
        XCTAssertTrue(SwiftUIReflector.isView(Text("hi")))
        XCTAssertFalse(SwiftUIReflector.isView(42))
        XCTAssertFalse(SwiftUIReflector.isView("plain string"))
    }

    func testReflectText() throws {
        let node = try XCTUnwrap(reflect(Text("Hello")))
        XCTAssertEqual(node.displayName, "Text")
        XCTAssertTrue(node.kind.isSwiftUI)
        let text = node.sections.flatMap(\.attributes).first { $0.title == "text" }
        XCTAssertEqual(text?.value, .string("Hello"))
    }

    func testReflectVStackChildren() throws {
        let view = VStack {
            Text("A")
            Text("B")
            Text("C")
        }
        let node = try XCTUnwrap(reflect(view))
        XCTAssertEqual(node.displayName, "VStack")
        let texts = allNodes(node).filter { $0.displayName == "Text" }
        XCTAssertEqual(texts.count, 3)
        let labels = texts.compactMap { $0.label }.sorted()
        XCTAssertEqual(labels, ["A", "B", "C"])
    }

    func testModifiersCaptured() throws {
        let view = Text("x").padding().opacity(0.5)
        let node = try XCTUnwrap(reflect(view))
        XCTAssertEqual(node.displayName, "Text")
        let modifierSection = node.sections.first { $0.title == "Modifiers" }
        let names = (modifierSection?.attributes.map(\.title) ?? []).sorted()
        XCTAssertTrue(names.contains("padding"), "got: \(names)")
        XCTAssertTrue(names.contains("opacity"), "got: \(names)")
    }

    func testCustomCompositeDescendsBody() throws {
        let node = try XCTUnwrap(reflect(Badge(count: 7)))
        XCTAssertEqual(node.displayName, "Badge")
        // Stored property captured as attribute.
        let countAttr = node.sections.flatMap(\.attributes).first { $0.title == "count" }
        XCTAssertEqual(countAttr?.value, .integer(7))
        // Body descended: an HStack with two Texts.
        let names = allNodes(node).map(\.displayName)
        XCTAssertTrue(names.contains("HStack"), "got: \(names)")
        XCTAssertEqual(allNodes(node).filter { $0.displayName == "Text" }.count, 2)
    }

    func testNestedCustomViewsAndState() throws {
        let node = try XCTUnwrap(reflect(Counter()))
        let names = allNodes(node).map(\.displayName)
        XCTAssertEqual(node.displayName, "Counter")
        XCTAssertTrue(names.contains("VStack"))
        XCTAssertTrue(names.contains("Badge"))
        // @State value unwrapped to its initial value.
        let valueAttr = node.sections.flatMap(\.attributes).first { $0.title == "value" }
        XCTAssertEqual(valueAttr?.value, .integer(3))
    }

    func testConditionalContent() throws {
        let flag = true
        let view = VStack {
            if flag { Text("yes") } else { Image(systemName: "x") }
        }
        let node = try XCTUnwrap(reflect(view))
        let texts = allNodes(node).filter { $0.displayName == "Text" }
        XCTAssertEqual(texts.first?.label, "yes")
    }

    func testForEachOrGroup() throws {
        let view = VStack {
            ForEach(0..<3, id: \.self) { i in
                Text("row \(i)")
            }
        }
        let node = try XCTUnwrap(reflect(view))
        // We at least must not crash and must produce the VStack node.
        XCTAssertEqual(node.displayName, "VStack")
    }

    func testDoesNotExceedBudgetOrCrashOnDeepTree() throws {
        // A reasonably deep modifier chain shouldn't crash or explode.
        let view = Text("deep")
            .padding().padding().padding().padding().padding()
            .background(Color.red)
            .opacity(0.9)
            .frame(width: 100, height: 40)
        let node = try XCTUnwrap(reflect(view))
        XCTAssertEqual(node.displayName, "Text")
        let mods = node.sections.first { $0.title == "Modifiers" }?.attributes ?? []
        XCTAssertGreaterThanOrEqual(mods.count, 3)
    }
}
#endif
