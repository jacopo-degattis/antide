import Foundation

/// A type-erased `Codable` value supporting JSON primitives, arrays, and dictionaries.
public struct AnyCodable: Codable, Sendable, Equatable, Hashable {
    public let value: AnySendable

    public init(_ value: (any Sendable)?) {
        if let value = value {
            self.value = AnySendable(value)
        } else {
            self.value = AnySendable(NSNull())
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = AnySendable(NSNull())
        } else if let bool = try? container.decode(Bool.self) {
            self.value = AnySendable(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = AnySendable(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = AnySendable(double)
        } else if let string = try? container.decode(String.self) {
            self.value = AnySendable(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = AnySendable(array.map { $0.value.base })
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = AnySendable(dict.mapValues { $0.value.base })
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value.base {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [any Sendable]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: any Sendable]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable value cannot be encoded"
            )
            throw EncodingError.invalidValue(value.base, context)
        }
    }

    public var stringValue: String? {
        value.base as? String
    }

    public var intValue: Int? {
        value.base as? Int
    }

    public var boolValue: Bool? {
        value.base as? Bool
    }

    public var doubleValue: Double? {
        value.base as? Double
    }

    public var arrayValue: [AnyCodable]? {
        guard let list = value.base as? [any Sendable] else { return nil }
        return list.map { AnyCodable($0) }
    }

    public var dictionaryValue: [String: AnyCodable]? {
        guard let dict = value.base as? [String: any Sendable] else { return nil }
        return dict.mapValues { AnyCodable($0) }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value.base) == String(describing: rhs.value.base)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value.base))
    }
}

public struct AnySendable: @unchecked Sendable {
    public let base: any Sendable

    public init(_ base: any Sendable) {
        self.base = base
    }
}
