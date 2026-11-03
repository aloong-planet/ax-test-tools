import AppKit
import ApplicationServices
import AXScenario

@MainActor final class ForegroundGuard {
    let baseline: pid_t
    private var observer: NSObjectProtocol?
    private(set) var changed = false
    init() throws {
        baseline = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        guard baseline > 0, baseline != ProcessInfo.processInfo.processIdentifier else { throw Failure("foreground_unavailable") }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let self, let pid, pid != self.baseline { self.changed = true }
            }
        }
    }
    func check() throws {
        guard !changed, NSWorkspace.shared.frontmostApplication?.processIdentifier == baseline else { throw Failure("foreground_changed") }
    }
    func stop() { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}

@MainActor final class SystemAX: AccessibilityAccess {
    let application: AXUIElement
    let target: NSRunningApplication
    let foreground: ForegroundGuard
    let deadline: TimeInterval
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    init(target: NSRunningApplication, foreground: ForegroundGuard) {
        self.target = target; self.foreground = foreground
        application = AXUIElementCreateApplication(target.processIdentifier)
        deadline = ProcessInfo.processInfo.systemUptime + 120
    }
    func checkEnvironment() throws {
        try foreground.check()
        guard !target.isTerminated else { throw Failure("target_exited") }
        guard now < deadline else { throw Failure("run_timeout") }
    }
    func pause() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    private func raw(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        try checkEnvironment()
        AXUIElementSetMessagingTimeout(element, 1)
        var value: CFTypeRef?
        let code = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if code == .attributeUnsupported || code == .noValue { return nil }
        guard code == .success else { throw Failure("ax_read_\(code.rawValue)") }
        return value
    }
    func find(_ selector: [String: String]) throws -> [AXUIElement] {
        let queryDeadline = now + 5
        var nodes = [application], index = 0, matches: [AXUIElement] = []
        while index < nodes.count {
            guard now < queryDeadline else { throw Failure("query_timeout") }
            guard nodes.count <= 1000 else { throw Failure("tree_limit_exceeded") }
            let element = nodes[index]; index += 1
            var match = true
            for (key, expected) in selector {
                if try raw(element, key) as? String != expected { match = false; break }
            }
            if match { matches.append(element) }
            var children = try raw(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            if CFEqual(element, application) { children += try raw(element, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
            for child in children where !nodes.contains(where: { CFEqual($0, child) }) { nodes.append(child) }
        }
        return matches
    }
    func read(_ element: AXUIElement, attribute: String) throws -> Scalar {
        guard let value = try raw(element, attribute) else { throw Failure("attribute_unavailable") }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool((value as! NSNumber).boolValue) }
        if let text = value as? String { return .string(text) }
        if let number = value as? NSNumber { return .number(number.doubleValue) }
        throw Failure("unsupported_attribute_type")
    }
    func write(_ element: AXUIElement, attribute: String, value: Scalar) throws {
        try checkEnvironment()
        var settable = DarwinBoolean(false)
        let query = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        guard query == .success, settable.boolValue else { throw Failure("attribute_not_settable") }
        let raw: CFTypeRef
        switch value {
        case .string(let value): raw = value as CFString
        case .bool(let value): raw = NSNumber(value: value)
        case .number(let value): raw = NSNumber(value: value)
        }
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, raw)
        guard result == .success else { throw Failure("ax_write_\(result.rawValue)") }
    }
    func perform(_ element: AXUIElement, action: String) throws {
        try checkEnvironment()
        guard try read(element, attribute: kAXEnabledAttribute) == .bool(true) else { throw Failure("element_disabled") }
        var actions: CFArray?
        let query = AXUIElementCopyActionNames(element, &actions)
        guard query == .success, (actions as? [String] ?? []).contains(action) else { throw Failure("action_unsupported") }
        let result = AXUIElementPerformAction(element, action as CFString)
        guard result == .success else { throw Failure("ax_action_\(result.rawValue)") }
    }
}
