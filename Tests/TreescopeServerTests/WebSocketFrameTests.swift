import XCTest
@testable import TreescopeServer
import TreescopeProtocol

final class WebSocketFrameTests: XCTestCase {

    func testAcceptKeyMatchesRFCExample() {
        // The canonical example from RFC 6455 §1.3.
        XCTAssertEqual(WebSocket.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ=="),
                       "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    /// Masks a payload the way a browser client would, producing a single frame.
    private func clientFrame(_ text: String, mask: [UInt8] = [0x12, 0x34, 0x56, 0x78]) -> Data {
        let payload = Array(text.utf8)
        var frame: [UInt8] = [0x81] // FIN + text
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len) | 0x80) // masked
        } else {
            frame.append(126 | 0x80)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        }
        frame.append(contentsOf: mask)
        for (i, b) in payload.enumerated() { frame.append(b ^ mask[i % 4]) }
        return Data(frame)
    }

    func testDecodeMaskedTextFrame() throws {
        let decoder = WebSocket.Decoder()
        decoder.append(clientFrame("hello world"))
        guard case .text(let s)? = try decoder.next() else { return XCTFail("expected text") }
        XCTAssertEqual(s, "hello world")
    }

    func testDecodeFrameSplitAcrossChunks() throws {
        let frame = clientFrame("split me up")
        let decoder = WebSocket.Decoder()
        for i in 0..<frame.count {
            decoder.append(frame.subdata(in: i ..< i + 1))
            let msg = try decoder.next()
            if i < frame.count - 1 {
                XCTAssertNil(msg, "completed too early at byte \(i)")
            } else if case .text(let s)? = msg {
                XCTAssertEqual(s, "split me up")
            } else {
                XCTFail("expected text at final byte")
            }
        }
    }

    func testDecodeTwoFramesInOneChunk() throws {
        var blob = clientFrame("first")
        blob.append(clientFrame("second"))
        let decoder = WebSocket.Decoder()
        decoder.append(blob)
        guard case .text(let a)? = try decoder.next() else { return XCTFail("a") }
        guard case .text(let b)? = try decoder.next() else { return XCTFail("b") }
        XCTAssertEqual([a, b], ["first", "second"])
        XCTAssertNil(try decoder.next())
    }

    func testDecodeExtendedLengthFrame() throws {
        // A 300-byte payload uses the 16-bit extended length path.
        let text = String(repeating: "x", count: 300)
        let decoder = WebSocket.Decoder()
        decoder.append(clientFrame(text))
        guard case .text(let s)? = try decoder.next() else { return XCTFail("expected text") }
        XCTAssertEqual(s.count, 300)
    }

    func testEncodeTextRoundTripsThroughDecoderShape() {
        // Server frames are unmasked; verify header bytes for a short payload.
        let data = WebSocket.encodeText("hi")
        let bytes = [UInt8](data)
        XCTAssertEqual(bytes[0], 0x81)       // FIN + text
        XCTAssertEqual(bytes[1], 2)          // length 2, unmasked
        XCTAssertEqual(Array(bytes[2...]), Array("hi".utf8))
    }

    func testCloseFrame() throws {
        // A masked close frame (opcode 0x8) with no payload.
        let decoder = WebSocket.Decoder()
        decoder.append(Data([0x88, 0x80, 0x00, 0x00, 0x00, 0x00]))
        guard case .close? = try decoder.next() else { return XCTFail("expected close") }
    }
}
