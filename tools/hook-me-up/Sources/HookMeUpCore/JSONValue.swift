import Foundation

/// Any JSON value, decoded losslessly enough to echo a hook's `tool_input` back as
/// `updatedInput`. Numbers are `Double`: integers beyond 2^53 lose precision (none of
/// Claude Code's tool inputs carry such numbers).
public enum JSONValue: Codable, Equatable, Sendable {
    /// A string.
    case string(String)
    /// A number.
    case number(Double)
    /// true or false.
    case bool(Bool)
    /// null.
    case null
    /// An array.
    case array([JSONValue])
    /// An object.
    case object([String: JSONValue])

    /// Decodes any JSON value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            // Bool is tried before Double so `true` never becomes 1 (and 1 never `true`).
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    /// Encodes the value as JSON.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Member of an object; nil for a missing key or when this is not an object.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    /// Pretty-printed JSON with sorted keys (the installer's stable settings output).
    public func pretty() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// The string, if this is one.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The elements, if this is an array.
    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The members, if this is an object.
    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The boolean, if this is one.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    /// A string value from a literal.
    public init(stringLiteral value: String) { self = .string(value) }
}
