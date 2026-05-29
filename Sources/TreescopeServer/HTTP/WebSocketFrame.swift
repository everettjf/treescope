import Foundation
import CryptoKit
import TreescopeProtocol

/// Minimal RFC 6455 WebSocket framing: handshake key derivation, an incremental
/// frame decoder for client → server traffic (always masked), and a server →
/// client frame encoder (never masked). Enough for the Treescope JSON protocol;
/// supports fragmentation and 64-bit payload lengths, ignores extensions.
public enum WebSocket {

    /// The GUID concatenated to `Sec-WebSocket-Key` per the spec.
    private static let magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    /// Computes the `Sec-WebSocket-Accept` value for a client key.
    public static func acceptKey(for clientKey: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((clientKey + magicGUID).utf8))
        return Data(digest).base64EncodedString()
    }

    /// A decoded application-level message.
    public enum Message {
        case text(String)
        case binary(Data)
        case ping(Data)
        case pong(Data)
        case close(code: UInt16?)
    }

    enum WSError: Error { case tooLarge, malformed }

    private struct Frame { let fin: Bool; let opcode: UInt8; let payload: Data }

    /// Incremental decoder. Feed bytes with `append`, pull messages with `next`.
    public final class Decoder {
        private var buffer = [UInt8]()
        private var fragmentOpcode: UInt8?
        private var fragmentData = Data()

        public init() {}

        public func append(_ data: Data) { buffer.append(contentsOf: data) }

        /// Returns the next complete message, or nil when more bytes are needed.
        public func next() throws -> Message? {
            while true {
                guard let frame = try parseFrame() else { return nil }
                switch frame.opcode {
                case 0x0: // continuation
                    fragmentData.append(frame.payload)
                    if frame.fin {
                        let op = fragmentOpcode ?? 0x1
                        let data = fragmentData
                        fragmentOpcode = nil
                        fragmentData = Data()
                        return assemble(opcode: op, data: data)
                    }
                case 0x1, 0x2: // text / binary
                    if frame.fin {
                        return assemble(opcode: frame.opcode, data: frame.payload)
                    } else {
                        fragmentOpcode = frame.opcode
                        fragmentData = frame.payload
                    }
                case 0x8: // close
                    var code: UInt16?
                    if frame.payload.count >= 2 {
                        let b = [UInt8](frame.payload)
                        code = (UInt16(b[0]) << 8) | UInt16(b[1])
                    }
                    return .close(code: code)
                case 0x9: return .ping(frame.payload)
                case 0xA: return .pong(frame.payload)
                default: throw WSError.malformed
                }
                // Non-final data frame or buffered fragment: keep parsing.
            }
        }

        private func assemble(opcode: UInt8, data: Data) -> Message {
            if opcode == 0x2 { return .binary(data) }
            return .text(String(decoding: data, as: UTF8.self))
        }

        private func parseFrame() throws -> Frame? {
            guard buffer.count >= 2 else { return nil }
            let b0 = buffer[0]
            let b1 = buffer[1]
            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var length = UInt64(b1 & 0x7F)
            var headerLen = 2

            if length == 126 {
                guard buffer.count >= 4 else { return nil }
                length = (UInt64(buffer[2]) << 8) | UInt64(buffer[3])
                headerLen = 4
            } else if length == 127 {
                guard buffer.count >= 10 else { return nil }
                length = 0
                for i in 2..<10 { length = (length << 8) | UInt64(buffer[i]) }
                headerLen = 10
            }

            guard length <= UInt64(ProtocolConstants.maxFrameBytes) else { throw WSError.tooLarge }

            let maskLen = masked ? 4 : 0
            let total = headerLen + maskLen + Int(length)
            guard buffer.count >= total else { return nil }

            var cursor = headerLen
            var mask = [UInt8](repeating: 0, count: 4)
            if masked {
                mask = Array(buffer[cursor..<cursor + 4])
                cursor += 4
            }

            var payload = [UInt8](repeating: 0, count: Int(length))
            for i in 0..<Int(length) {
                let byte = buffer[cursor + i]
                payload[i] = masked ? byte ^ mask[i % 4] : byte
            }

            buffer.removeFirst(total)
            return Frame(fin: fin, opcode: opcode, payload: Data(payload))
        }
    }

    // MARK: Encoding (server → client, unmasked, single frame)

    public static func encodeText(_ string: String) -> Data {
        encodeFrame(opcode: 0x1, payload: Data(string.utf8))
    }

    public static func encodePong(_ payload: Data) -> Data {
        encodeFrame(opcode: 0xA, payload: payload)
    }

    public static func encodeClose() -> Data {
        encodeFrame(opcode: 0x8, payload: Data())
    }

    private static func encodeFrame(opcode: UInt8, payload: Data) -> Data {
        var header = [UInt8]()
        header.append(0x80 | opcode) // FIN + opcode
        let len = payload.count
        if len < 126 {
            header.append(UInt8(len))
        } else if len <= 0xFFFF {
            header.append(126)
            header.append(UInt8((len >> 8) & 0xFF))
            header.append(UInt8(len & 0xFF))
        } else {
            header.append(127)
            var value = UInt64(len)
            var bytes = [UInt8](repeating: 0, count: 8)
            for i in (0..<8).reversed() { bytes[i] = UInt8(value & 0xFF); value >>= 8 }
            header.append(contentsOf: bytes)
        }
        var data = Data(header)
        data.append(payload)
        return data
    }
}
