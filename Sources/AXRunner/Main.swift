import AppKit
import ApplicationServices
import AXScenario

struct StepResult: Codable {
    let index: Int
    let operation: String
    let metadata: Scalar?
}
struct Report: Codable {
    var exitCode: Int32 = 1
    var status = "failed"
    var reason = "unknown"
    var stage = "arguments"
    var steps: [StepResult] = []
    var cleanup: String? = nil
}

@main @MainActor struct Main {
    static let help = """
    AXRunner — local background Accessibility test client (macOS 14+)
      AXRunner --help | -h
      AXRunner --preflight [--result /absolute/new-report.json]
      AXRunner --check /absolute/scenario.json [--result /absolute/new-report.json]
      AXRunner --scenario /absolute/scenario.json --result /absolute/new-report.json
    For the installed app identity use Scripts/run.sh (LaunchServices, nonactivating).
    Result files must not already exist. Check JSON exitCode, not open's exit status.
    Only run trusted scenarios with isolated apps and fake data. No automatic permissions.
    """
    static func main() {
        var report = Report(), output: URL?
        var owned: NSRunningApplication?
        var foreground: ForegroundGuard?
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            if args.isEmpty || args == ["--help"] || args == ["-h"] { print(help); exit(0) }
            var options: [String: String] = [:]
            var preflight = false
            while !args.isEmpty {
                let key = args.removeFirst()
                if key == "--preflight", !preflight { preflight = true; continue }
                guard ["--scenario", "--result", "--check"].contains(key), options[key] == nil,
                      !args.isEmpty else { throw Failure("invalid_arguments") }
                options[key] = args.removeFirst()
            }
            if let path = options["--result"] {
                guard path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path),
                      (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
                else { throw Failure("result_must_be_new_absolute_path") }
                output = URL(fileURLWithPath: path)
            }
            let modes = (preflight ? 1 : 0) + (options["--check"] != nil ? 1 : 0) + (options["--scenario"] != nil ? 1 : 0)
            guard modes == 1 else { throw Failure("choose_one_mode") }
            if preflight {
                report.stage = "permission"
                guard AXIsProcessTrusted() else { throw Failure("accessibility_permission_required") }
            } else {
                report.stage = "schema"
                let path = options["--check"] ?? options["--scenario"]!
                guard path.hasPrefix("/") else { throw Failure("scenario_requires_absolute_path") }
                let scenario = try Scenario.parse(Data(contentsOf: URL(fileURLWithPath: path)))
                if options["--scenario"] != nil {
                    guard output != nil else { throw Failure("result_required") }
                    report.stage = "permission"
                    guard AXIsProcessTrusted() else { throw Failure("accessibility_permission_required") }
                    report.stage = "target"
                    let url = URL(fileURLWithPath: scenario.target.app).resolvingSymlinksInPath()
                    guard let bundle = Bundle(url: url), bundle.bundleIdentifier == scenario.target.bundleID,
                          bundle.executableURL != nil else { throw Failure("target_identity_mismatch") }
                    guard NSRunningApplication.runningApplications(withBundleIdentifier: scenario.target.bundleID).isEmpty else { throw Failure("target_already_running") }
                    _ = NSApplication.shared.setActivationPolicy(.accessory)
                    foreground = try ForegroundGuard()
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    configuration.createsNewApplicationInstance = true
                    configuration.arguments = scenario.target.arguments ?? []
                    let existingPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                    var launched: NSRunningApplication?
                    var finished = false, launchError = false
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                        let pid = app?.processIdentifier
                        let failed = error != nil
                        DispatchQueue.main.async {
                            launched = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
                            launchError = failed
                            finished = true
                        }
                    }
                    let limit = ProcessInfo.processInfo.systemUptime + 10
                    while !finished && ProcessInfo.processInfo.systemUptime < limit {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    }
                    guard finished, !launchError, let app = launched else {
                        report.cleanup = "launch_ownership_unresolved_check_target_manually"
                        throw Failure("launch_failed_or_timed_out")
                    }
                    guard app.bundleIdentifier == scenario.target.bundleID,
                          app.bundleURL?.resolvingSymlinksInPath() == url,
                          !existingPIDs.contains(app.processIdentifier) else {
                        report.cleanup = "unowned_process_not_terminated"
                        throw Failure("launched_identity_mismatch")
                    }
                    owned = app
                    let backend = SystemAX(target: app, foreground: foreground!)
                    for (index, step) in scenario.steps.enumerated() {
                        report.stage = "step_\(index + 1)"
                        let value = try execute(step, using: backend)
                        report.steps.append(StepResult(index: index + 1, operation: step.op, metadata: value))
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    try backend.checkEnvironment()
                }
            }
            report.exitCode = 0; report.status = "passed"; report.reason = "ok"
        } catch {
            report.reason = (error as? Failure)?.code ?? "invalid_input_or_io"
            if report.reason == "accessibility_permission_required" { report.exitCode = 77; report.status = "blocked" }
        }
        if let target = owned, !target.isTerminated {
            _ = target.terminate()
            let limit = ProcessInfo.processInfo.systemUptime + 3
            while !target.isTerminated && ProcessInfo.processInfo.systemUptime < limit {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            report.cleanup = target.isTerminated ? "terminated_owned_target" : "target_refused_termination"
            if !target.isTerminated { report.exitCode = 3; report.status = "failed" }
        }
        if let foreground {
            if (try? foreground.check()) == nil { report.exitCode = 2; report.status = "failed"; report.reason = "foreground_changed" }
            foreground.stop()
        }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(report)
            if let output { try encoded.write(to: output, options: .withoutOverwriting) }
            print(String(decoding: encoded, as: UTF8.self))
        } catch { print("result_write_failed"); exit(74) }
        exit(report.exitCode)
    }
}
