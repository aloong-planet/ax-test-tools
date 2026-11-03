import Foundation
import Testing
import AXScenario

func data(_ steps: String, version: Int = 1, target: String = "/Applications/Fixture.app", extra: String = "") -> Data {
    Data("""
    {"version":\(version),"target":{"app":"\(target)","bundleID":"example.fixture"},"steps":\(steps)\(extra)}
    """.utf8)
}

@Test func rejectsUnsafeOrInvalidScenarios() {
    let invalid = [
        data("[]"), data("[]", version: 2),
        data("[{\"op\":\"read\",\"selector\":{},\"attribute\":\"AXEnabled\"}]"),
        data("[{\"op\":\"perform\",\"selector\":{\"AXRole\":\"AXButton\"},\"action\":\"AXRaise\"}]"),
        data("[{\"op\":\"read\",\"selector\":{\"AXRole\":\"AXTextField\"},\"attribute\":\"AXValue\"}]"),
        data("[{\"op\":\"read\",\"selector\":{\"AXRole\":\"AXButton\"},\"attribute\":\"AXEnabled\"}]", target: "relative.app"),
        data("[{\"op\":\"read\",\"selector\":{\"AXRole\":\"AXButton\"},\"attribute\":\"AXEnabled\"}]", extra: ",\"ignoreForeground\":true")
    ]
    for input in invalid { #expect(throws: (any Error).self) { try Scenario.parse(input) } }
}

@Test func acceptsProjectOwnedScenario() throws {
    let scenario = try Scenario.parse(data("""
    [{"op":"wait","selector":{"AXIdentifier":"submit","AXRole":"AXButton"},"attribute":"AXEnabled","value":true,"timeout":2}]
    """))
    #expect(scenario.steps.count == 1)
    #expect(scenario.steps[0].selector["AXIdentifier"] == "submit")
}
