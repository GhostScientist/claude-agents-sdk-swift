import Foundation

/// JSON Schema representation for tool parameters
public struct JSONSchema: Sendable, Codable, Hashable {
    public let type: SchemaType
    public let description: String?
    public let properties: [String: PropertySchema]?
    public let required: [String]?
    public let items: PropertySchema?
    public let enumValues: [String]?
    public let defaultValue: AnyCodable?

    public enum SchemaType: String, Sendable, Codable, Hashable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
        case null
    }

    private enum CodingKeys: String, CodingKey {
        case type, description, properties, required, items
        case enumValues = "enum"
        case defaultValue = "default"
    }

    public init(
        type: SchemaType,
        description: String? = nil,
        properties: [String: PropertySchema]? = nil,
        required: [String]? = nil,
        items: PropertySchema? = nil,
        enumValues: [String]? = nil,
        defaultValue: AnyCodable? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
        self.enumValues = enumValues
        self.defaultValue = defaultValue
    }

    /// Create an object schema with properties
    public static func object(
        properties: [String: PropertySchema],
        required: [String]? = nil,
        description: String? = nil
    ) -> JSONSchema {
        JSONSchema(
            type: .object,
            description: description,
            properties: properties,
            required: required
        )
    }

    /// Create an array schema
    public static func array(items: PropertySchema, description: String? = nil) -> JSONSchema {
        JSONSchema(type: .array, description: description, items: items)
    }

    /// Create a simple string schema
    public static func string(description: String? = nil) -> JSONSchema {
        JSONSchema(type: .string, description: description)
    }
}

/// Schema for individual properties within an object
public struct PropertySchema: Sendable, Codable, Hashable {
    public let type: JSONSchema.SchemaType
    public let description: String?
    public let enumValues: [String]?
    public let defaultValue: AnyCodable?
    public let items: Box<PropertySchema>?

    private enum CodingKeys: String, CodingKey {
        case type, description, items
        case enumValues = "enum"
        case defaultValue = "default"
    }

    public init(
        type: JSONSchema.SchemaType,
        description: String? = nil,
        enumValues: [String]? = nil,
        defaultValue: AnyCodable? = nil,
        items: PropertySchema? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.defaultValue = defaultValue
        self.items = items.map { Box($0) }
    }

    // Convenience initializers
    public static func string(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: .string, description: description)
    }

    public static func number(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: .number, description: description)
    }

    public static func integer(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: .integer, description: description)
    }

    public static func boolean(_ description: String? = nil) -> PropertySchema {
        PropertySchema(type: .boolean, description: description)
    }

    public static func array(items: PropertySchema, description: String? = nil) -> PropertySchema {
        PropertySchema(type: .array, description: description, items: items)
    }

    public static func `enum`(_ values: [String], description: String? = nil) -> PropertySchema {
        PropertySchema(type: .string, description: description, enumValues: values)
    }
}

/// Box wrapper for recursive types
public final class Box<T: Sendable & Codable & Hashable>: Sendable, Codable, Hashable {
    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    public static func == (lhs: Box<T>, rhs: Box<T>) -> Bool {
        lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }

    public init(from decoder: Decoder) throws {
        value = try T(from: decoder)
    }
}

/// Type-erased codable value for default values
public struct AnyCodable: Sendable, Codable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
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
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
