import Foundation

/// Errors raised while encoding/decoding the wire stream.
public enum FrameError: Error, Equatable {
    case badMagic(UInt32)
    case frameTooLarge(Int)
    case truncated
}

/// Encodes/decodes length-prefixed frames over a byte stream.
///
/// Wire layout per frame (big-endian):
///   [ magic: UInt32 ][ length: UInt32 ][ payload: length bytes ]
///
/// JSON is used for the payload so both ends (always Swift) interop trivially
/// and frames stay debuggable.
public enum WireFrame {
    private static let headerSize = 8

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= ProtocolConstants.maxFrameBytes else {
            throw FrameError.frameTooLarge(payload.count)
        }
        var out = Data(capacity: headerSize + payload.count)
        out.appendBigEndian(ProtocolConstants.frameMagic)
        out.appendBigEndian(UInt32(payload.count))
        out.append(payload)
        return out
    }

    public static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder = .treescope) throws -> Data {
        try encode(encoder.encode(value))
    }
}

/// Buffers incoming bytes and yields complete frame payloads as they arrive.
/// Not thread-safe; drive it from a single queue (the connection's queue).
public final class FrameDecoder {
    private var buffer = Data()
    private let maxFrameBytes: Int

    public init(maxFrameBytes: Int = ProtocolConstants.maxFrameBytes) {
        self.maxFrameBytes = maxFrameBytes
    }

    /// Appends newly received bytes.
    public func append(_ data: Data) {
        buffer.append(data)
    }

    /// Pops the next complete payload, or nil if more bytes are needed.
    /// Throws on a corrupt stream (bad magic / oversized frame).
    public func next() throws -> Data? {
        guard buffer.count >= 8 else { return nil }

        let magic = buffer.readBigEndianUInt32(at: 0)
        guard magic == ProtocolConstants.frameMagic else {
            throw FrameError.badMagic(magic)
        }
        let length = Int(buffer.readBigEndianUInt32(at: 4))
        guard length <= maxFrameBytes else {
            throw FrameError.frameTooLarge(length)
        }
        let total = 8 + length
        guard buffer.count >= total else { return nil }

        let payload = buffer.subdata(in: 8 ..< total)
        buffer.removeSubrange(0 ..< total)
        return payload
    }

    /// Decodes and returns all currently-complete frames.
    public func drain<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .treescope) throws -> [T] {
        var results: [T] = []
        while let payload = try next() {
            results.append(try decoder.decode(T.self, from: payload))
        }
        return results
    }

    public var pendingByteCount: Int { buffer.count }
}

// MARK: - JSON coders tuned for the protocol

public extension JSONEncoder {
    static var treescope: JSONEncoder {
        let e = JSONEncoder()
        e.dataEncodingStrategy = .base64
        e.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
}

public extension JSONDecoder {
    static var treescope: JSONDecoder {
        let d = JSONDecoder()
        d.dataDecodingStrategy = .base64
        d.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}

// MARK: - Big-endian Data helpers

extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    /// Reads a big-endian UInt32 at a byte offset relative to startIndex.
    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        var value: UInt32 = 0
        value |= UInt32(self[start])     << 24
        value |= UInt32(self[start + 1]) << 16
        value |= UInt32(self[start + 2]) << 8
        value |= UInt32(self[start + 3])
        return value
    }
}
