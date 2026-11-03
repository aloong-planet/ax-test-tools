import Foundation

@MainActor
public protocol AccessibilityAccess {
    associatedtype Element
    var now: TimeInterval { get }
    func find(_ selector: [String: String]) throws -> [Element]
    func read(_ element: Element, attribute: String) throws -> Scalar
    func write(_ element: Element, attribute: String, value: Scalar) throws
    func perform(_ element: Element, action: String) throws
    func checkEnvironment() throws
    func pause()
}

/// Reads that can fail while the target's AX tree is changing: cannotComplete, and invalidUIElement,
/// seen on waits right after a press closes a preview.
private let transientReadFailures: Set<String> = ["ax_read_-25204", "ax_read_-25202"]

@MainActor
public func execute<B: AccessibilityAccess>(_ step: Scenario.Step, using backend: B) throws -> Scalar? {
    let deadline = backend.now + (step.op == "wait" ? (step.timeout ?? 3) : 0)
    repeat {
        try backend.checkEnvironment()
        do {
            let matches = try backend.find(step.selector)
            guard matches.count <= 1 else { throw Failure("ambiguous_match") }
            if let element = matches.first {
                switch step.op {
                case "query": return nil
                case "read": return try backend.read(element, attribute: step.attribute!)
                case "set":
                    try backend.checkEnvironment()
                    try backend.write(element, attribute: step.attribute!, value: step.value!)
                    try backend.checkEnvironment()
                    return nil
                case "perform":
                    try backend.checkEnvironment()
                    try backend.perform(element, action: step.action!)
                    try backend.checkEnvironment()
                    return nil
                case "assert", "wait":
                    if let attribute = step.attribute {
                        if try backend.read(element, attribute: attribute) == step.value { return nil }
                    } else { return nil }
                default: throw Failure("unknown_operation")
                }
            }
            if step.op != "wait" { throw Failure(matches.isEmpty ? "element_not_found" : "assertion_failed") }
        } catch let error as Failure where step.op == "wait" && transientReadFailures.contains(error.code) {
            // Only read-only waits may retry these; never repeat writes/actions.
        }
        if backend.now >= deadline { throw Failure("wait_timeout") }
        backend.pause()
    } while true
}
