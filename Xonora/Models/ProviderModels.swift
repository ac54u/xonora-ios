import Foundation

// MARK: - Flexible JSON Value

enum ConfigValue: Codable, Hashable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case stringArray([String])

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .stringArray(let v): return v.joined(separator: ", ")
        }
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        if case .double(let v) = self { return Int(v) }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var arrayValue: [String]? {
        if case .stringArray(let v) = self { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let dbl = try? container.decode(Double.self) {
            self = .double(dbl)
        } else if let arr = try? container.decode([String].self) {
            self = .stringArray(arr)
        } else {
            throw DecodingError.typeMismatch(ConfigValue.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported ConfigValue type"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .stringArray(let v): try container.encode(v)
        }
    }
}

// MARK: - Provider Manifest

struct ProviderManifest: Codable, Identifiable {
    let type: String
    let domain: String
    let name: String
    let description: String
    let multiInstance: Bool
    let builtin: Bool
    let allowDisable: Bool
    let stage: String
    let icon: String?
    let documentation: String?
    let dependsOn: String?
    let requirements: [String]
    let credits: [String]

    var id: String { domain }
    var isStable: Bool { stage == "stable" }
    var isBeta: Bool { stage == "beta" }

    enum CodingKeys: String, CodingKey {
        case type, domain, name, description
        case multiInstance = "multi_instance"
        case builtin
        case allowDisable = "allow_disable"
        case stage, icon, documentation
        case dependsOn = "depends_on"
        case requirements, credits
    }
}

// MARK: - Provider Config (list item)

struct ProviderConfig: Codable, Identifiable {
    let type: String
    let domain: String
    let instanceId: String
    let enabled: Bool
    let name: String?
    let defaultName: String?
    let lastError: String?
    let status: String?

    var id: String { instanceId }
    var displayName: String { name ?? defaultName ?? domain }

    enum CodingKeys: String, CodingKey {
        case type, domain, enabled, name, status
        case instanceId = "instance_id"
        case defaultName = "default_name"
        case lastError = "last_error"
    }
}

// MARK: - Provider Instance (runtime state)

struct ProviderInstance: Codable, Identifiable {
    let type: String
    let domain: String
    let name: String
    let instanceId: String
    let available: Bool
    let icon: String?

    var id: String { instanceId }

    enum CodingKeys: String, CodingKey {
        case type, domain, name, available, icon
        case instanceId = "instance_id"
    }
}

// MARK: - Config Entry (dynamic form field)

struct ConfigEntry: Codable, Identifiable {
    let key: String
    let type: String
    let label: String
    let value: ConfigValue?
    let defaultValue: ConfigValue?
    let required: Bool?
    let options: [ConfigValueOption]?
    let range: ConfigRange?
    let description: String?
    let helpLink: String?
    let advanced: Bool?
    let hidden: Bool?
    let readOnly: Bool?
    let dependsOn: String?
    let dependsOnValue: ConfigValue?
    let dependsOnValueNot: ConfigValue?
    let category: String?
    let action: String?
    let actionLabel: String?
    let multiValue: Bool?
    let requiresReload: Bool?
    let immediateApply: Bool?

    var id: String { key }
    var isSecure: Bool { type == "secure_string" }

    enum CodingKeys: String, CodingKey {
        case key, type, label, value
        case defaultValue = "default_value"
        case required, options, range, description
        case helpLink = "help_link"
        case advanced, hidden
        case readOnly = "read_only"
        case dependsOn = "depends_on"
        case dependsOnValue = "depends_on_value"
        case dependsOnValueNot = "depends_on_value_not"
        case category, action
        case actionLabel = "action_label"
        case multiValue = "multi_value"
        case requiresReload = "requires_reload"
        case immediateApply = "immediate_apply"
    }
}

// MARK: - Config Entry Helpers

struct ConfigValueOption: Codable, Hashable {
    let title: String
    let value: ConfigValue
}

struct ConfigRange: Codable, Hashable {
    let min: Int
    let max: Int

    enum CodingKeys: String, CodingKey {
        case min, max
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        min = try container.decode(Int.self)
        max = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(min)
        try container.encode(max)
    }
}

// MARK: - Error Response

struct ProviderErrorResponse: Codable {
    let code: Int?
    let message: String?
}
