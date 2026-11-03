import Foundation

public struct Scenario: Decodable, Sendable {
    public let version: Int
    public let target: Target
    public let steps: [Step]
    public struct Target: Decodable, Sendable {
        public let app: String
        public let bundleID: String
        public let arguments: [String]?
    }
    public struct Step: Decodable, Sendable {
        public let op: String
        public let selector: [String: String]
        public let attribute: String?
        public let value: Scalar?
        public let action: String?
        public let timeout: Double?
    }
    public static func parse(_ data: Data) throws -> Scenario {
        guard data.count <= 1_048_576,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "target", "steps"]),
              let target = object["target"] as? [String: Any],
              Set(target.keys).isSubset(of: ["app", "bundleID", "arguments"]),
              let steps = object["steps"] as? [[String: Any]],
              steps.allSatisfy({ Set($0.keys).isSubset(of: ["op", "selector", "attribute", "value", "action", "timeout"]) })
        else { throw Failure("invalid_schema") }
        let scenario = try JSONDecoder().decode(Scenario.self, from: data)
        guard scenario.version == 1, (1...100).contains(scenario.steps.count),
              scenario.target.app.hasPrefix("/"), scenario.target.app.hasSuffix(".app"),
              !scenario.target.bundleID.isEmpty else { throw Failure("invalid_target_or_version") }
        let selectors: Set<String> = ["AXIdentifier", "AXRole", "AXSubrole", "AXTitle", "AXDescription"]
        let safeReads: Set<String> = ["AXRole", "AXSubrole", "AXEnabled"]
        for step in scenario.steps {
            guard !step.selector.isEmpty, Set(step.selector.keys).isSubset(of: selectors),
                  step.selector.values.allSatisfy({ !$0.isEmpty }),
                  (0...10).contains(step.timeout ?? 3) else { throw Failure("invalid_selector_or_timeout") }
            switch step.op {
            case "query":
                guard step.attribute == nil, step.value == nil, step.action == nil, step.timeout == nil else { throw Failure("invalid_query") }
            case "read":
                guard let attribute = step.attribute, safeReads.contains(attribute), step.value == nil,
                      step.action == nil, step.timeout == nil else { throw Failure("unsafe_read") }
            case "assert", "wait":
                guard step.action == nil else { throw Failure("invalid_assertion") }
                if let attribute = step.attribute {
                    guard selectors.union(["AXValue", "AXEnabled"]).contains(attribute), step.value != nil else { throw Failure("invalid_assertion") }
                } else if step.value != nil { throw Failure("invalid_assertion") }
                if step.op == "assert", step.timeout != nil { throw Failure("invalid_assertion") }
            case "set":
                guard step.attribute == "AXValue", step.value != nil, step.action == nil, step.timeout == nil else { throw Failure("unsafe_write") }
            case "perform":
                guard step.action == "AXPress", step.attribute == nil, step.value == nil, step.timeout == nil else { throw Failure("unsafe_action") }
            default: throw Failure("unknown_operation")
            }
        }
        return scenario
    }
}

public struct Failure: Error, Equatable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

public enum Scalar: Codable, Equatable, Sendable {
    case string(String), bool(Bool), number(Double)
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else { self = .number(try box.decode(Double.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        }
    }
}
