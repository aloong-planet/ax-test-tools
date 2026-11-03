import Foundation
import Testing
import AXScenario

// Fake only the external macOS accessibility boundary; the real scenario executor is used.
// Real AX discovery/write/press and foreground notifications require an authorized client
// and an isolated native fixture. These unit tests do not prove macOS background support.
@MainActor final class Device: AccessibilityAccess {
    var now = 0.0
    var matches = [1]
    var values: [Int: Scalar] = [1: .bool(false)]
    var actionAvailable = true
    var foregroundChanged = false
    var becomeReady = false
    var actionChangesForeground = false
    var unavailableReads = 0
    var unavailableReadCode = "ax_read_-25204"
    func find(_ selector: [String: String]) throws -> [Int] {
        if unavailableReads > 0 {
            unavailableReads -= 1
            throw Failure(unavailableReadCode)
        }
        return matches
    }
    func read(_ element: Int, attribute: String) throws -> Scalar { values[element] ?? .bool(false) }
    func write(_ element: Int, attribute: String, value: Scalar) throws { values[element] = value }
    func perform(_ element: Int, action: String) throws {
        guard actionAvailable else { throw Failure("action_unsupported") }
        values[element] = .string("finished")
        if actionChangesForeground { foregroundChanged = true }
    }
    func checkEnvironment() throws { if foregroundChanged { throw Failure("foreground_changed") } }
    func pause() { now += 0.05; if becomeReady { values[1] = .bool(true) } }
}

func step(_ fields: String) throws -> Scenario.Step {
    try Scenario.parse(data("[{\"selector\":{\"AXIdentifier\":\"subject\"},\(fields)}]")).steps[0]
}

@Test @MainActor func writesAndObservesThroughPublicBoundary() throws {
    let device = Device()
    _ = try execute(step("\"op\":\"set\",\"attribute\":\"AXValue\",\"value\":\"fixture\""), using: device)
    _ = try execute(step("\"op\":\"assert\",\"attribute\":\"AXValue\",\"value\":\"fixture\""), using: device)
}

@Test @MainActor func waitsForActualExpectedAttribute() throws {
    let device = Device(); device.becomeReady = true
    _ = try execute(step("\"op\":\"wait\",\"attribute\":\"AXEnabled\",\"value\":true,\"timeout\":1"), using: device)
}

@Test @MainActor func rejectsWrongOutcomeAndAmbiguity() throws {
    let device = Device()
    let assertion = try step("\"op\":\"assert\",\"attribute\":\"AXEnabled\",\"value\":true")
    #expect(throws: Failure("assertion_failed")) { try execute(assertion, using: device) }
    device.matches = [1, 2]
    #expect(throws: Failure("ambiguous_match")) { try execute(assertion, using: device) }
    device.matches = []
    #expect(throws: Failure("element_not_found")) { try execute(assertion, using: device) }
}

@Test @MainActor func stopsOnForegroundChangeAndUnsupportedAction() throws {
    let device = Device()
    let action = try step("\"op\":\"perform\",\"action\":\"AXPress\"")
    device.foregroundChanged = true
    #expect(throws: Failure("foreground_changed")) { try execute(action, using: device) }
    device.foregroundChanged = false; device.actionAvailable = false
    #expect(throws: Failure("action_unsupported")) { try execute(action, using: device) }
}

@Test @MainActor func actionRequiresIndependentOutcomeAssertion() throws {
    let device = Device()
    _ = try execute(step("\"op\":\"perform\",\"action\":\"AXPress\""), using: device)
    _ = try execute(step("\"op\":\"assert\",\"attribute\":\"AXValue\",\"value\":\"finished\""), using: device)
}

@Test @MainActor func timesOutWithoutExpectedOutcome() throws {
    let device = Device()
    let waiting = try step("\"op\":\"wait\",\"attribute\":\"AXEnabled\",\"value\":true,\"timeout\":0.1")
    #expect(throws: Failure("wait_timeout")) { try execute(waiting, using: device) }
    device.matches = []
    #expect(throws: Failure("wait_timeout")) { try execute(waiting, using: device) }
}

@Test @MainActor func actionCannotPassAfterChangingForeground() throws {
    let device = Device(); device.actionChangesForeground = true
    #expect(throws: Failure("foreground_changed")) {
        try execute(step("\"op\":\"perform\",\"action\":\"AXPress\""), using: device)
    }
}

// -25204 is AX cannotComplete. -25202 is invalidUIElement, seen on the wait right after pressing a
// preview's Close button.
@Test(arguments: ["ax_read_-25204", "ax_read_-25202"])
@MainActor func waitsThroughTransientAXReadFailureWithoutRetryingActions(code: String) throws {
    let device = Device(); device.unavailableReadCode = code; device.unavailableReads = 1
    _ = try execute(step("\"op\":\"wait\",\"timeout\":0.1"), using: device)
    device.unavailableReads = 1
    #expect(throws: Failure(code)) {
        try execute(step("\"op\":\"perform\",\"action\":\"AXPress\""), using: device)
    }
    device.unavailableReads = 1
    #expect(throws: Failure(code)) {
        try execute(step("\"op\":\"set\",\"attribute\":\"AXValue\",\"value\":\"fixture\""), using: device)
    }
    device.unavailableReads = 1
    #expect(throws: Failure(code)) {
        try execute(step("\"op\":\"assert\",\"attribute\":\"AXEnabled\",\"value\":false"), using: device)
    }
    device.unavailableReads = 100
    #expect(throws: Failure("wait_timeout")) {
        try execute(step("\"op\":\"wait\",\"timeout\":0.1"), using: device)
    }
}

@Test @MainActor func otherReadFailuresStillEndAWait() throws {
    let device = Device(); device.unavailableReadCode = "ax_read_-25211"; device.unavailableReads = 1
    #expect(throws: Failure("ax_read_-25211")) {
        try execute(step("\"op\":\"wait\",\"timeout\":0.1"), using: device)
    }
}
