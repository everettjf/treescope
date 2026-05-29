#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import SwiftUI
@testable import TreescopeServer
import TreescopeProtocol

/// SwiftUI's pure-`App`/`WindowGroup` root unwraps to a transparent thunk
/// wrapper (`AnyView` → `LazyView`) whose content is a closure Mirror can't see
/// into. The reflector must evaluate `body` on such wrappers to materialize the
/// declared tree. These tests pin that, using `AnyView` (which wraps content the
/// same opaque way) as a stand-in we can build in a unit test.
final class LazyContentTests: XCTestCase {

    private struct Leaf: View {
        var body: some View {
            VStack {
                Text("Alpha")
                Text("Beta")
            }
        }
    }

    private func allNodes(_ root: ViewNode) -> [ViewNode] {
        var out: [ViewNode] = []; root.forEachDepthFirst { out.append($0) }; return out
    }

    func testAnyViewWrappedContentIsRecovered() throws {
        // AnyView hides its content behind type erasure, like the App root.
        let node = try XCTUnwrap(SwiftUIReflector().reflect(rootValue: AnyView(Leaf())))
        let texts = allNodes(node).filter { $0.displayName == "Text" }.compactMap(\.label).sorted()
        XCTAssertEqual(texts, ["Alpha", "Beta"])
    }

    func testDeeplyNestedAnyViewChain() throws {
        // Multiple erasure layers (AnyView(AnyView(…))) must still resolve.
        let v = AnyView(AnyView(VStack { Text("Deep"); AnyView(Text("Erased")) }))
        let node = try XCTUnwrap(SwiftUIReflector().reflect(rootValue: v))
        let texts = Set(allNodes(node).filter { $0.displayName == "Text" }.compactMap(\.label))
        XCTAssertEqual(texts, ["Deep", "Erased"])
    }
}
#endif
