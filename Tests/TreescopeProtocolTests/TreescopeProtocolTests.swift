import XCTest
@testable import TreescopeProtocol

final class GeometryTests: XCTestCase {
    func testRectGeometry() {
        let r = Rect(x: 10, y: 20, width: 100, height: 40)
        XCTAssertEqual(r.maxX, 110)
        XCTAssertEqual(r.maxY, 60)
        XCTAssertEqual(r.center, Point(x: 60, y: 40))
        XCTAssertTrue(r.contains(Point(x: 50, y: 30)))
        XCTAssertFalse(r.contains(Point(x: 5, y: 5)))
    }

    func testRectOffset() {
        let r = Rect(x: 5, y: 5, width: 10, height: 10)
        XCTAssertEqual(r.offset(by: Point(x: 100, y: 200)),
                       Rect(x: 105, y: 205, width: 10, height: 10))
    }

    func testColorHex() {
        XCTAssertEqual(RGBAColor(red: 1, green: 0, blue: 0, alpha: 1).hexString, "#FF0000")
        XCTAssertEqual(RGBAColor(red: 0, green: 1, blue: 0, alpha: 0.5).hexString, "#00FF0080")
    }

    func testTransformIdentity() {
        XCTAssertTrue(Transform3D.identity.isIdentity)
        XCTAssertFalse(Transform3D(m: Array(repeating: 2, count: 16)).isIdentity)
    }
}

final class AttributeTests: XCTestCase {
    func testDisplayStrings() {
        XCTAssertEqual(AttributeValue.bool(true).displayString, "true")
        XCTAssertEqual(AttributeValue.integer(42).displayString, "42")
        XCTAssertEqual(AttributeValue.number(3.0).displayString, "3.0")
        XCTAssertEqual(AttributeValue.size(Size(width: 10, height: 20)).displayString, "10.0 × 20.0")
        XCTAssertEqual(AttributeValue.null.displayString, "nil")
        XCTAssertEqual(AttributeValue.enumeration(".center").displayString, ".center")
    }

    func testNestedRoundTrip() throws {
        let value = AttributeValue.nested([
            Attribute(title: "x", value: .number(1)),
            Attribute(title: "color", value: .color(RGBAColor(red: 1, green: 1, blue: 1, alpha: 1))),
        ])
        let data = try JSONEncoder.treescope.encode(value)
        let back = try JSONDecoder.treescope.decode(AttributeValue.self, from: data)
        XCTAssertEqual(value, back)
    }

    func testCoerceIntegerToNumber() {
        // A whole number sent for a number-typed property arrives as .integer.
        XCTAssertEqual(AttributeValue.integer(12).coercingIntegerToNumber, .number(12))
        XCTAssertEqual(AttributeValue.integer(-3).coercingIntegerToNumber, .number(-3))
        // Other cases pass through unchanged.
        XCTAssertEqual(AttributeValue.number(3.5).coercingIntegerToNumber, .number(3.5))
        XCTAssertEqual(AttributeValue.bool(true).coercingIntegerToNumber, .bool(true))
        XCTAssertEqual(AttributeValue.string("x").coercingIntegerToNumber, .string("x"))
    }

    func testSectionBuildDropsEmpty() {
        let sections = [AttributeSection].build([
            ("A", [Attribute(title: "x", value: .bool(true))]),
            ("Empty", []),
        ])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "A")
    }
}

final class ViewNodeTests: XCTestCase {
    private func sampleTree() -> ViewNode {
        ViewNode(id: "root", kind: .window, className: "UIWindow", displayName: "Window",
                 frame: .zero, bounds: .zero,
                 children: [
                    ViewNode(id: "a", kind: .uiView, className: "UIView", displayName: "View",
                             frame: .zero, bounds: .zero, children: [
                                ViewNode(id: "a1", kind: .swiftUI, className: "Text", displayName: "Text",
                                         frame: .zero, bounds: .zero),
                             ]),
                    ViewNode(id: "b", kind: .uiView, className: "UILabel", displayName: "Label",
                             frame: .zero, bounds: .zero),
                 ])
    }

    func testSubtreeCount() {
        XCTAssertEqual(sampleTree().subtreeCount, 4)
    }

    func testFindByID() {
        XCTAssertEqual(sampleTree().node(withID: "a1")?.displayName, "Text")
        XCTAssertNil(sampleTree().node(withID: "nope"))
    }

    func testPathTo() {
        XCTAssertEqual(sampleTree().path(toID: "a1"), ["root", "a", "a1"])
        XCTAssertNil(sampleTree().path(toID: "missing"))
    }

    func testDepthFirstOrder() {
        var ids: [String] = []
        sampleTree().forEachDepthFirst { ids.append($0.id) }
        XCTAssertEqual(ids, ["root", "a", "a1", "b"])
    }

    func testFlags() {
        var flags: ViewFlags = [.hidden, .hostsSwiftUI]
        XCTAssertTrue(flags.contains(.hidden))
        XCTAssertFalse(flags.contains(.systemView))
        flags.insert(.systemView)
        XCTAssertTrue(flags.contains(.systemView))
    }
}

final class MessageCodableTests: XCTestCase {
    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder.treescope.encode(value)
        return try JSONDecoder.treescope.decode(T.self, from: data)
    }

    func testClientEnvelopeRoundTrip() throws {
        let messages: [ClientMessage] = [
            .handshake(ClientInfo(name: "Test", version: "1.0")),
            .fetchHierarchy(.default),
            .fetchSnapshot(nodeID: "abc", scale: 2),
            .setAttribute(nodeID: "abc", keyPath: "alpha", value: .number(0.5)),
            .highlight(nodeID: "abc"),
            .highlight(nodeID: nil),
            .ping,
        ]
        for (i, m) in messages.enumerated() {
            let env = ClientEnvelope(id: UInt64(i), message: m)
            let data = try JSONEncoder.treescope.encode(env)
            let back = try JSONDecoder.treescope.decode(ClientEnvelope.self, from: data)
            XCTAssertEqual(back.id, UInt64(i))
        }
    }

    func testHierarchySnapshotRoundTrip() throws {
        let device = DeviceInfo(appName: "Demo", bundleID: "com.x.demo", processName: "Demo",
                                osName: "macOS", osVersion: "26.0", deviceModel: "Mac",
                                deviceName: "Test Mac", screenSize: Size(width: 1440, height: 900),
                                screenScale: 2, isSimulator: false)
        let node = ViewNode(id: "r", kind: .nsView, className: "NSView", displayName: "NSView",
                            frame: Rect(x: 0, y: 0, width: 100, height: 100),
                            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
                            sections: [AttributeSection(title: "Layout",
                                attributes: [Attribute(title: "frame",
                                    value: .rect(Rect(x: 0, y: 0, width: 100, height: 100)))])])
        let snap = HierarchySnapshot(device: device, roots: [node], timestamp: 123, serverVersion: "0.1.0")
        let env = ServerEnvelope(id: 7, message: .hierarchy(snap))
        let data = try JSONEncoder.treescope.encode(env)
        let back = try JSONDecoder.treescope.decode(ServerEnvelope.self, from: data)
        XCTAssertEqual(back.id, 7)
        if case .hierarchy(let s) = back.message {
            XCTAssertEqual(s.totalNodeCount, 1)
            XCTAssertEqual(s.device.appName, "Demo")
        } else {
            XCTFail("expected hierarchy")
        }
    }

    func testSnapshotImageRoundTrip() throws {
        let img = SnapshotImage(nodeID: "n", format: .png, scale: 2,
                                pixelSize: Size(width: 20, height: 20),
                                data: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let env = ServerEnvelope(id: 1, message: .snapshot(img))
        let data = try JSONEncoder.treescope.encode(env)
        let back = try JSONDecoder.treescope.decode(ServerEnvelope.self, from: data)
        if case .snapshot(let s) = back.message {
            XCTAssertEqual(s.data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        } else {
            XCTFail("expected snapshot")
        }
    }
}

final class FramingTests: XCTestCase {
    func testSingleFrameRoundTrip() throws {
        let env = ClientEnvelope(id: 1, message: .ping)
        let frame = try WireFrame.encode(env)
        let decoder = FrameDecoder()
        decoder.append(frame)
        let payloads = try decoder.drain(ClientEnvelope.self)
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.id, 1)
    }

    func testMultipleFramesInOneChunk() throws {
        var blob = Data()
        for i in 0..<5 {
            blob.append(try WireFrame.encode(ClientEnvelope(id: UInt64(i), message: .ping)))
        }
        let decoder = FrameDecoder()
        decoder.append(blob)
        let result = try decoder.drain(ClientEnvelope.self)
        XCTAssertEqual(result.map(\.id), [0, 1, 2, 3, 4])
    }

    func testFrameSplitAcrossChunks() throws {
        let frame = try WireFrame.encode(ClientEnvelope(id: 99, message: .ping))
        let decoder = FrameDecoder()
        // Feed one byte at a time; only the final byte should complete the frame.
        for i in 0..<frame.count {
            decoder.append(frame.subdata(in: i ..< i + 1))
            let got = try decoder.next()
            if i < frame.count - 1 {
                XCTAssertNil(got, "frame completed too early at byte \(i)")
            } else {
                XCTAssertNotNil(got)
            }
        }
    }

    func testPartialHeaderWaits() throws {
        let decoder = FrameDecoder()
        decoder.append(Data([0x54, 0x53])) // partial magic
        XCTAssertNil(try decoder.next())
        XCTAssertEqual(decoder.pendingByteCount, 2)
    }

    func testBadMagicThrows() {
        let decoder = FrameDecoder()
        var junk = Data()
        junk.appendBigEndian(0xDEAD_BEEF)
        junk.appendBigEndian(4)
        junk.append(Data([0, 0, 0, 0]))
        decoder.append(junk)
        XCTAssertThrowsError(try decoder.next()) { error in
            XCTAssertEqual(error as? FrameError, .badMagic(0xDEAD_BEEF))
        }
    }

    func testOversizeFrameThrows() {
        let decoder = FrameDecoder(maxFrameBytes: 8)
        var data = Data()
        data.appendBigEndian(ProtocolConstants.frameMagic)
        data.appendBigEndian(1000)
        decoder.append(data)
        XCTAssertThrowsError(try decoder.next()) { error in
            XCTAssertEqual(error as? FrameError, .frameTooLarge(1000))
        }
    }

    func testRemainderPreservedAfterFrame() throws {
        let frame = try WireFrame.encode(ClientEnvelope(id: 3, message: .ping))
        let decoder = FrameDecoder()
        decoder.append(frame + Data([0x54, 0x53])) // one full frame + partial next header
        let first = try decoder.next()
        XCTAssertNotNil(first)
        XCTAssertNil(try decoder.next())
        XCTAssertEqual(decoder.pendingByteCount, 2)
    }
}
