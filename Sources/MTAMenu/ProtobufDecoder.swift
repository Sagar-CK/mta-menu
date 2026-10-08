import Foundation

/// Errors raised while reading protobuf wire-format bytes.
enum ProtobufError: Error, Equatable {
    case truncated
    case varintTooLong
    case unsupportedWireType(Int)
}

/// A minimal, dependency-free reader for the protobuf binary wire format.
///
/// GTFS-Realtime feeds are protobuf messages. Pulling in SwiftProtobuf would
/// require `protoc` at build time, so instead this reader understands just
/// enough of the wire format (https://protobuf.dev/programming-guides/encoding/)
/// to walk a message field by field. Callers know the schema (field numbers)
/// and pick out the fields they care about; unknown fields are skipped.
///
/// Usage:
/// ```swift
/// var reader = ProtobufReader(data)
/// while let field = try reader.nextField() {
///     switch field.number { case 2: ... default: break }
/// }
/// ```
struct ProtobufReader {
    /// A decoded field value, tagged by wire type.
    enum Value {
        case varint(UInt64)                 // wire type 0: int32/int64/uint/bool/enum
        case fixed64(UInt64)                // wire type 1: fixed64/sfixed64/double
        case lengthDelimited(ArraySlice<UInt8>) // wire type 2: string/bytes/embedded message
        case fixed32(UInt32)                // wire type 5: fixed32/sfixed32/float

        /// Interprets a length-delimited field as a UTF-8 string.
        var string: String? {
            if case let .lengthDelimited(bytes) = self { return String(decoding: bytes, as: UTF8.self) }
            return nil
        }

        /// Interprets a varint field as a signed 64-bit integer (protobuf `int64`).
        var int64: Int64? {
            if case let .varint(v) = self { return Int64(bitPattern: v) }
            return nil
        }

        /// Interprets a length-delimited field as the bytes of an embedded message.
        var message: ArraySlice<UInt8>? {
            if case let .lengthDelimited(bytes) = self { return bytes }
            return nil
        }
    }

    private let bytes: ArraySlice<UInt8>
    private var index: Int

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.index = bytes.startIndex
    }

    init(_ data: Data) {
        self.init([UInt8](data)[...])
    }

    var isAtEnd: Bool { index >= bytes.endIndex }

    /// Reads the next `(fieldNumber, value)` pair, or `nil` at end of message.
    mutating func nextField() throws -> (number: Int, value: Value)? {
        if isAtEnd { return nil }
        let key = try readVarint()
        let number = Int(key >> 3)
        let wireType = Int(key & 0x7)
        switch wireType {
        case 0:
            return (number, .varint(try readVarint()))
        case 1:
            return (number, .fixed64(try readFixed(byteCount: 8)))
        case 2:
            let length = Int(try readVarint())
            guard length >= 0, index + length <= bytes.endIndex else { throw ProtobufError.truncated }
            let slice = bytes[index..<(index + length)]
            index += length
            return (number, .lengthDelimited(slice))
        case 5:
            return (number, .fixed32(UInt32(truncatingIfNeeded: try readFixed(byteCount: 4))))
        default:
            // Wire types 3/4 (groups) are deprecated and never used by GTFS-RT.
            throw ProtobufError.unsupportedWireType(wireType)
        }
    }

    /// Reads a base-128 varint (little-endian, 7 bits per byte, MSB = continuation).
    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.endIndex else { throw ProtobufError.truncated }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw ProtobufError.varintTooLong }
        }
    }

    private mutating func readFixed(byteCount: Int) throws -> UInt64 {
        guard index + byteCount <= bytes.endIndex else { throw ProtobufError.truncated }
        var value: UInt64 = 0
        for offset in 0..<byteCount {
            value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
        }
        index += byteCount
        return value
    }
}
