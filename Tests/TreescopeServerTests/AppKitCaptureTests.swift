#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import AppKit
import SwiftUI
@testable import TreescopeServer
import TreescopeProtocol

final class AppKitCaptureTests: XCTestCase {

    @MainActor
    private func makeWindow(_ content: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Test"
        window.contentView = content
        return window
    }

    private func allNodes(_ root: ViewNode) -> [ViewNode] {
        var out: [ViewNode] = []
        root.forEachDepthFirst { out.append($0) }
        return out
    }

    @MainActor
    func testCaptureNSViewHierarchy() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let label = NSTextField(labelWithString: "Hello AppKit")
        label.frame = NSRect(x: 20, y: 250, width: 200, height: 24)
        content.addSubview(label)
        let button = NSButton(title: "Tap", target: nil, action: nil)
        button.frame = NSRect(x: 20, y: 200, width: 80, height: 30)
        content.addSubview(button)

        let window = makeWindow(content)
        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))

        XCTAssertEqual(node.kind, .nsWindow)
        let names = allNodes(node).map(\.displayName)
        XCTAssertTrue(names.contains("NSTextField"), "got \(names)")
        XCTAssertTrue(names.contains("NSButton"), "got \(names)")

        // The label's text is captured as a property.
        let labelNode = try XCTUnwrap(allNodes(node).first { $0.displayName == "NSTextField" })
        let stringAttr = labelNode.sections.flatMap(\.attributes).first { $0.title == "stringValue" }
        XCTAssertEqual(stringAttr?.value, .string("Hello AppKit"))
    }

    @MainActor
    func testCoordinatesAreTopLeftFlipped() throws {
        // A subview pinned near the top of a non-flipped NSView should report a
        // small y in the top-left space the viewer expects.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let topView = NSView(frame: NSRect(x: 10, y: 270, width: 100, height: 20)) // near top in AppKit coords
        content.addSubview(topView)
        let window = makeWindow(content)
        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))
        let sub = try XCTUnwrap(allNodes(node).first { abs($0.frame.width - 100) < 0.5 && abs($0.frame.height - 20) < 0.5 })
        // top-left y = contentHeight(300) - maxY(270+20=290) = 10
        XCTAssertEqual(sub.frame.y, 10, accuracy: 0.5)
        XCTAssertEqual(sub.frame.x, 10, accuracy: 0.5)
    }

    @MainActor
    func testCaptureSwiftUIUnderHostingView() throws {
        let hosting = NSHostingView(rootView: VStack {
            Text("Title")
            Text("Subtitle")
        })
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        content.addSubview(hosting)
        let window = makeWindow(content)

        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))
        let all = allNodes(node)

        // A hosting view node flagged as hosting SwiftUI.
        XCTAssertTrue(all.contains { $0.flags.contains(.hostsSwiftUI) }, "no hosting flag")
        // The reflected SwiftUI subtree contains a VStack and two Texts.
        let swiftUINodes = all.filter { $0.kind == .swiftUI }
        XCTAssertTrue(swiftUINodes.contains { $0.displayName == "VStack" }, "got \(swiftUINodes.map(\.displayName))")
        let texts = swiftUINodes.filter { $0.displayName == "Text" }
        XCTAssertEqual(texts.count, 2)
        let labels = Set(texts.compactMap(\.label))
        XCTAssertEqual(labels, ["Title", "Subtitle"])
    }

    @MainActor
    func testSnapshotRendersPNG() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.red.cgColor
        let window = makeWindow(content)
        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))
        let contentNode = try XCTUnwrap(node.children.first)
        let nodeID = try XCTUnwrap(contentNode.snapshotID)
        let image = engine.snapshotImage(nodeID: nodeID, scale: 1)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.format, .png)
        XCTAssertGreaterThan(image?.data.count ?? 0, 0)
    }

    @MainActor
    func testLiveEditAlpha() throws {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let window = makeWindow(content)
        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))
        let contentNode = try XCTUnwrap(node.children.first)
        let (ok, _) = engine.applyAttribute(nodeID: contentNode.id, keyPath: "alphaValue", value: .number(0.3))
        XCTAssertTrue(ok)
        XCTAssertEqual(content.alphaValue, 0.3, accuracy: 0.001)
    }

    @MainActor
    func testLiveEditCoercesWholeNumberInteger() throws {
        // A whole number arrives as `.integer`; numeric properties must still accept it.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let window = makeWindow(content)
        let engine = CaptureEngine()
        let node = try XCTUnwrap(engine.captureWindow(window, options: .default, path: "win0"))
        let contentNode = try XCTUnwrap(node.children.first)

        // View property (cornerRadius is backed by the layer).
        let (ok, msg) = engine.applyAttribute(nodeID: contentNode.id, keyPath: "cornerRadius", value: .integer(12))
        XCTAssertTrue(ok, "integer cornerRadius should be accepted; got \(String(describing: msg))")
        let radius = try XCTUnwrap(content.layer?.cornerRadius)
        XCTAssertEqual(radius, 12, accuracy: 0.001)

        let (ok2, _) = engine.applyAttribute(nodeID: contentNode.id, keyPath: "alphaValue", value: .integer(1))
        XCTAssertTrue(ok2)
        XCTAssertEqual(content.alphaValue, 1.0, accuracy: 0.001)

        // A genuinely unknown key path still fails, with a clearer message.
        let (bad, badMsg) = engine.applyAttribute(nodeID: contentNode.id, keyPath: "bogus", value: .integer(1))
        XCTAssertFalse(bad)
        XCTAssertEqual(badMsg, "cannot set 'bogus' here (unsupported key path or value type 1.0)")
    }
}
#endif
