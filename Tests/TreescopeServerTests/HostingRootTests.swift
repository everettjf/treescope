#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import AppKit
import SwiftUI
@testable import TreescopeServer
import TreescopeProtocol

/// A pure-SwiftUI-lifecycle macOS window root is the generic internal class
/// `AppKitWindowHostingView<…>`, whose *own* `Mirror` has no children — its
/// inherited `rootView` lives on a superclass mirror (`NSHostingViewBase`).
///
/// We can't spin up a real `App` lifecycle in a unit test, but a subclass of
/// `NSHostingView` reproduces the exact shape that broke `findRootView`: the
/// leaf class adds no stored properties, so `rootView` is only reachable by
/// traversing `Mirror.superclassMirror`. These tests pin that behavior.
final class HostingRootTests: XCTestCase {

    /// Mimics the internal window-root class: a hosting-view subclass with no
    /// stored properties of its own.
    final class WindowRootLike<V: View>: NSHostingView<V> {
        // Intentionally empty — like AppKitWindowHostingView, the rootView is
        // inherited and thus only on the superclass mirror.
        @MainActor required init(rootView: V) { super.init(rootView: rootView) }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
    }

    @MainActor
    func testLeafMirrorIsEmptyButRootViewIsFoundViaSuperclass() throws {
        let host = WindowRootLike(rootView: VStack { Text("Deep"); Text("Root") })
        host.layoutSubtreeIfNeeded()

        // Precondition: the leaf class's own Mirror really has no children
        // (otherwise this test isn't exercising the superclass path).
        XCTAssertTrue(Mirror(reflecting: host).children.isEmpty,
                      "subclass unexpectedly exposes stored properties; test no longer covers the bug")

        // The fix: findRootView still locates the declared rootView.
        let root = try XCTUnwrap(SwiftUIReflector.findRootView(in: host))
        let node = try XCTUnwrap(SwiftUIReflector().reflect(rootValue: root))

        var texts: [String] = []
        node.forEachDepthFirst { if $0.displayName == "Text", let l = $0.label { texts.append(l) } }
        XCTAssertEqual(Set(texts), ["Deep", "Root"])
        XCTAssertTrue({ var found = false; node.forEachDepthFirst { found = found || $0.displayName == "VStack" }; return found }(),
                      "declaration tree (VStack) not recovered")
    }

    @MainActor
    func testDirectHostingViewStillWorks() throws {
        // The non-subclassed path must keep working.
        let host = NSHostingView(rootView: HStack { Text("A"); Text("B") })
        host.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(SwiftUIReflector.findRootView(in: host))
        let node = try XCTUnwrap(SwiftUIReflector().reflect(rootValue: root))
        var texts: [String] = []
        node.forEachDepthFirst { if $0.displayName == "Text", let l = $0.label { texts.append(l) } }
        XCTAssertEqual(Set(texts), ["A", "B"])
    }
}
#endif
