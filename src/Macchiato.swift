import AppKit
import CryptoKit
import Darwin

final class MacchiatoApp: NSObject, NSApplicationDelegate {
    private let serviceLabel = "local.codex.macchiato.caffeinate"
    private let closedLidLabel = "local.codex.macchiato.closedlid"
    private let legacyServiceLabel = "local.codex.caffeinatebar.caffeinate"
    private let legacyClosedLidLabel = "local.codex.caffeinatebar.closedlid"
    private let helperVersion = "1.5"
    private let displaySettingKey = "keepDisplayAwake"
    private var statusItem: NSStatusItem!

    private var serviceTarget: String { "gui/\(getuid())/\(serviceLabel)" }
    private var legacyServiceTarget: String { "gui/\(getuid())/\(legacyServiceLabel)" }
    private var userTarget: String { "gui/\(getuid())" }
    private var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(serviceLabel).plist")
    }
    private var closedLidURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(closedLidLabel).plist")
    }
    private var helperURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/MacchiatoHelper")
    }
    private var grantURL: URL {
        URL(fileURLWithPath: "/etc/sudoers.d/local-codex-macchiato")
    }
    private var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyServiceLabel).plist")
    }
    private var legacyClosedLidURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(legacyClosedLidLabel).plist")
    }
    private var legacyHelperURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/local.codex.caffeinatebar.helper")
    }
    private var legacyGrantURL: URL {
        URL(fileURLWithPath: "/etc/sudoers.d/local-codex-caffeinatebar")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPreference()
        UserDefaults.standard.register(defaults: [displaySettingKey: false])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            NSApp.terminate(nil)
            return
        }
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshStatus),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        migrateLegacyDisplayAgent()
        if needsLegacyHelperCleanup {
            _ = ensureHelperInstalled()
        }
        if FileManager.default.fileExists(atPath: agentURL.path), !isServiceLoaded() {
            let result = launchctl(["bootstrap", userTarget, agentURL.path])
            if result.status != 0 {
                showError("Could not restore caffeinate: \(result.message)")
            }
        }
        updateButton()
    }

    private func migrateLegacyPreference() {
        guard UserDefaults.standard.object(forKey: displaySettingKey) == nil,
              let oldValue = UserDefaults(suiteName: "local.codex.caffeinatebar")?
                .object(forKey: displaySettingKey) as? Bool else { return }
        UserDefaults.standard.set(oldValue, forKey: displaySettingKey)
    }

    private func migrateLegacyDisplayAgent() {
        let legacyLoaded = launchctl(["print", legacyServiceTarget]).status == 0
        guard legacyLoaded || FileManager.default.fileExists(atPath: legacyAgentURL.path) else { return }
        if legacyLoaded && isClosedLidSleepDisabled() &&
            UserDefaults.standard.bool(forKey: displaySettingKey) && !installDisplayAgent() {
            return
        }
        if legacyLoaded {
            let result = launchctl(["bootout", legacyServiceTarget])
            guard result.status == 0 else {
                showError("Could not stop the previous display job: \(result.message)")
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
                try FileManager.default.removeItem(at: legacyAgentURL)
            }
        } catch {
            showError("Could not remove the previous display job: \(error.localizedDescription)")
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        updateButton()
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showOptions(for: event, button: sender)
        } else {
            toggleCaffeinate()
        }
    }

    @objc private func refreshStatus() {
        updateButton()
    }

    @objc private func toggleCaffeinate() {
        if ownsClosedLidMode && isClosedLidSleepDisabled() {
            stopCaffeinate()
        } else {
            startCaffeinate()
        }
        updateButton()
    }

    private func startCaffeinate() {
        guard ensureHelperInstalled() else { return }
        let result = runHelper("on")
        guard result.status == 0, isClosedLidSleepDisabled() else {
            showError("Could not enable closed-lid wake: \(result.message)")
            return
        }

        // disablesleep already blocks idle sleep. Only keep a user process
        // when the optional display-awake setting is selected.
        if UserDefaults.standard.bool(forKey: displaySettingKey) {
            if !installDisplayAgent() { return }
        } else {
            stopDisplayAgent()
        }
    }

    private func stopCaffeinate() {
        let result: (status: Int32, message: String)
        if FileManager.default.fileExists(atPath: helperURL.path) ||
            FileManager.default.fileExists(atPath: grantURL.path) {
            result = runHelper("off")
        } else if FileManager.default.fileExists(atPath: legacyHelperURL.path) &&
            FileManager.default.fileExists(atPath: legacyGrantURL.path) {
            result = runCommand("/usr/bin/sudo", ["-n", legacyHelperURL.path, "off"])
        } else {
            // Recover gracefully if an earlier version enabled the setting
            // before the one-time helper was installed.
            let remove = "set -e; " +
                "/usr/bin/pmset -a disablesleep 0; " +
                "/bin/launchctl bootout system/\(closedLidLabel) >/dev/null 2>&1 || true; " +
                "/bin/launchctl bootout system/\(legacyClosedLidLabel) >/dev/null 2>&1 || true; " +
                "/bin/rm -f \(shellQuote(closedLidURL.path)) \(shellQuote(legacyClosedLidURL.path))"
            result = runAsAdministrator(remove)
        }
        guard result.status == 0, !isClosedLidSleepDisabled() else {
            showError("Could not restore normal sleep: \(result.message)")
            return
        }
        stopDisplayAgent()
    }

    private func helperInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: helperURL.path),
              FileManager.default.fileExists(atPath: grantURL.path) else { return false }
        let result = runCommand(helperURL.path, ["--version"])
        return result.status == 0 && result.message == helperVersion
    }

    private var needsLegacyHelperCleanup: Bool {
        [legacyHelperURL, legacyGrantURL, legacyClosedLidURL].contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func ensureHelperInstalled() -> Bool {
        if helperInstalled() && !needsLegacyHelperCleanup { return true }
        guard let bundledHelper = Bundle.main.url(forResource: "MacchiatoHelper", withExtension: nil),
              let data = try? Data(contentsOf: bundledHelper) else {
            showError("The one-click helper is missing from the app.")
            return false
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let rule = "#\(getuid()) ALL=(root) NOPASSWD: \(helperURL.path) on, \(helperURL.path) off"
        let preserveLegacyWake = FileManager.default.fileExists(atPath: legacyClosedLidURL.path) &&
            isClosedLidSleepDisabled()
        let install = "set -e; " +
            "/bin/mkdir -p /Library/PrivilegedHelperTools; " +
            "helper_tmp=$(/usr/bin/mktemp /Library/PrivilegedHelperTools/.macchiato.XXXXXX); " +
            "/bin/cp \(shellQuote(bundledHelper.path)) \"$helper_tmp\"; " +
            "/bin/echo \(shellQuote(digest + "  "))\"$helper_tmp\" | /usr/bin/shasum -a 256 -c -; " +
            "/usr/bin/codesign --verify --strict \"$helper_tmp\"; " +
            "/usr/sbin/chown root:wheel \"$helper_tmp\"; /bin/chmod 755 \"$helper_tmp\"; " +
            "/bin/mv -f \"$helper_tmp\" \(shellQuote(helperURL.path)); " +
            "grant_tmp=$(/usr/bin/mktemp /etc/sudoers.d/.macchiato.XXXXXX); " +
            "/bin/echo \(shellQuote(rule)) > \"$grant_tmp\"; " +
            "/usr/sbin/chown root:wheel \"$grant_tmp\"; /bin/chmod 440 \"$grant_tmp\"; " +
            "/usr/sbin/visudo -cf \"$grant_tmp\"; " +
            "/bin/mv -f \"$grant_tmp\" \(shellQuote(grantURL.path)); " +
            (preserveLegacyWake ? "\(shellQuote(helperURL.path)) on; " : "") +
            "/bin/launchctl bootout system/\(legacyClosedLidLabel) >/dev/null 2>&1 || true; " +
            "/bin/rm -f \(shellQuote(legacyClosedLidURL.path)) " +
            "\(shellQuote(legacyHelperURL.path)) \(shellQuote(legacyGrantURL.path))"
        let result = runAsAdministrator(install)
        guard result.status == 0, helperInstalled() else {
            showError("Could not install the one-click helper: \(result.message)")
            return false
        }
        return true
    }

    private func runHelper(_ action: String) -> (status: Int32, message: String) {
        runCommand("/usr/bin/sudo", ["-n", helperURL.path, action])
    }

    private func installDisplayAgent() -> Bool {
        do {
            if isServiceLoaded() {
                let stopped = launchctl(["bootout", serviceTarget])
                guard stopped.status == 0 else {
                    showError("Could not update display wake: \(stopped.message)")
                    return false
                }
            }
            try writeAgent()
        } catch {
            showError("Could not save display wake: \(error.localizedDescription)")
            return false
        }
        let started = launchctl(["bootstrap", userTarget, agentURL.path])
        if started.status != 0 || !isServiceLoaded() {
            showError("Could not start display wake: \(started.message)")
            return false
        }
        return true
    }

    @discardableResult private func stopDisplayAgent() -> Bool {
        if isServiceLoaded() {
            let stopped = launchctl(["bootout", serviceTarget])
            if stopped.status != 0 {
                showError("Could not stop display wake: \(stopped.message)")
                return false
            }
        }
        if launchctl(["print", legacyServiceTarget]).status == 0 {
            let stopped = launchctl(["bootout", legacyServiceTarget])
            if stopped.status != 0 {
                showError("Could not stop the previous display job: \(stopped.message)")
                return false
            }
        }
        do {
            if FileManager.default.fileExists(atPath: agentURL.path) {
                try FileManager.default.removeItem(at: agentURL)
            }
            if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
                try FileManager.default.removeItem(at: legacyAgentURL)
            }
        } catch {
            showError("Display wake stopped, but its saved service could not be removed: \(error.localizedDescription)")
            return false
        }
        return true
    }

    private func writeAgent() throws {
        try FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "Label": serviceLabel,
            "ProgramArguments": ["/usr/bin/caffeinate", "-d"],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
    }

    private func isServiceLoaded() -> Bool {
        launchctl(["print", serviceTarget]).status == 0
    }

    private var ownsClosedLidMode: Bool {
        FileManager.default.fileExists(atPath: closedLidURL.path) ||
            FileManager.default.fileExists(atPath: legacyClosedLidURL.path)
    }

    private func isClosedLidSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            process.waitUntilExit()
            return process.terminationStatus == 0 && output.split(separator: "\n").contains { line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
            }
        } catch {
            return false
        }
    }

    private func runAsAdministrator(_ command: String) -> (status: Int32, message: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "with timeout of 600 seconds\n" +
            "do shell script \"\(escaped)\" with administrator privileges\n" +
            "end timeout"
        guard let script = NSAppleScript(source: source) else {
            return (-1, "Could not create the administrator request")
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            return (-1, error[NSAppleScript.errorMessage] as? String ?? "Administrator request failed")
        }
        return (0, "Done")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func launchctl(_ arguments: [String]) -> (status: Int32, message: String) {
        runCommand("/bin/launchctl", arguments)
    }

    private func runCommand(_ path: String, _ arguments: [String]) -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (process.terminationStatus, output.isEmpty ? "\(name) exit code \(process.terminationStatus)" : output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let active = isClosedLidSleepDisabled()
        let legacyOnly = !active && (isServiceLoaded() ||
            launchctl(["print", legacyServiceTarget]).status == 0)
        button.image = cupImage(steaming: active)
        button.imagePosition = .imageOnly
        button.contentTintColor = active ? .systemOrange : nil
        button.toolTip = active
            ? ownsClosedLidMode
                ? "Sleep is disabled, including with the lid closed. Click to turn it off."
                : "Sleep was disabled outside this app. Click to manage it here."
            : legacyOnly
                ? "Idle wake is on. Click to add closed-lid wake."
                : "Sleep prevention is off. Click to turn it on, including with the lid closed."
        button.setAccessibilityLabel(active ? "Macchiato on, including lid closed" : "Macchiato off")
        button.setAccessibilityHelp("Click to toggle. Right-click for options.")
    }

    private func cupImage(steaming: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 26), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Draw the handle first so the cup body covers the attachment.
            let handle = NSBezierPath()
            handle.lineWidth = 2.4
            handle.lineCapStyle = .round
            handle.move(to: NSPoint(x: 18.2, y: 14.6))
            handle.curve(
                to: NSPoint(x: 18.0, y: 8.2),
                controlPoint1: NSPoint(x: 26.0, y: 17.2),
                controlPoint2: NSPoint(x: 26.0, y: 6.8)
            )
            handle.stroke()

            let cup = NSBezierPath()
            cup.move(to: NSPoint(x: 3.5, y: 16.5))
            cup.line(to: NSPoint(x: 19.2, y: 16.5))
            cup.line(to: NSPoint(x: 18.1, y: 9.0))
            cup.curve(
                to: NSPoint(x: 14.6, y: 5.2),
                controlPoint1: NSPoint(x: 17.8, y: 6.7),
                controlPoint2: NSPoint(x: 16.9, y: 5.2)
            )
            cup.line(to: NSPoint(x: 8.3, y: 5.2))
            cup.curve(
                to: NSPoint(x: 4.7, y: 9.0),
                controlPoint1: NSPoint(x: 6.0, y: 5.2),
                controlPoint2: NSPoint(x: 5.0, y: 6.7)
            )
            cup.close()
            cup.fill()

            if steaming {
                for x in [9.0, 15.0] {
                    let steam = NSBezierPath()
                    steam.lineWidth = 1.8
                    steam.lineCapStyle = .round
                    steam.move(to: NSPoint(x: x, y: 19.0))
                    steam.curve(
                        to: NSPoint(x: x + 0.4, y: 24.0),
                        controlPoint1: NSPoint(x: x - 2.1, y: 21.0),
                        controlPoint2: NSPoint(x: x + 2.2, y: 22.0)
                    )
                    steam.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = steaming ? "Steaming cup, Macchiato on" : "Cup, Macchiato off"
        return image
    }

    private func showOptions(for event: NSEvent, button: NSStatusBarButton) {
        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: ownsClosedLidMode && isClosedLidSleepDisabled()
                ? "Turn Macchiato Off"
                : "Turn Macchiato On (Including Lid Closed)",
            action: #selector(toggleCaffeinate),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let displayItem = NSMenuItem(
            title: "Keep Display Awake Too",
            action: #selector(toggleDisplaySetting),
            keyEquivalent: ""
        )
        displayItem.target = self
        displayItem.state = UserDefaults.standard.bool(forKey: displaySettingKey) ? .on : .off
        menu.addItem(displayItem)

        menu.addItem(.separator())
        if helperInstalled() || needsLegacyHelperCleanup {
            let removeItem = NSMenuItem(
                title: "Remove One-Click Permission…",
                action: #selector(removeHelper),
                keyEquivalent: ""
            )
            removeItem.target = self
            menu.addItem(removeItem)
        }
        let quitItem = NSMenuItem(
            title: "Quit App (Keep Current State)",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func toggleDisplaySetting() {
        let newValue = !UserDefaults.standard.bool(forKey: displaySettingKey)
        guard isClosedLidSleepDisabled() else {
            UserDefaults.standard.set(newValue, forKey: displaySettingKey)
            return
        }
        if newValue {
            if installDisplayAgent() {
                UserDefaults.standard.set(newValue, forKey: displaySettingKey)
            }
        } else {
            if stopDisplayAgent() {
                UserDefaults.standard.set(newValue, forKey: displaySettingKey)
            }
        }
        updateButton()
    }

    @objc private func removeHelper() {
        let remove = "set -e; " +
            "/usr/bin/pmset -a disablesleep 0; " +
            "/bin/launchctl bootout system/\(closedLidLabel) >/dev/null 2>&1 || true; " +
            "/bin/launchctl bootout system/\(legacyClosedLidLabel) >/dev/null 2>&1 || true; " +
            "/bin/rm -f \(shellQuote(closedLidURL.path)) \(shellQuote(legacyClosedLidURL.path)) " +
            "\(shellQuote(grantURL.path)) \(shellQuote(helperURL.path)) " +
            "\(shellQuote(legacyGrantURL.path)) \(shellQuote(legacyHelperURL.path))"
        let result = runAsAdministrator(remove)
        guard result.status == 0 else {
            showError("Could not remove one-click permission: \(result.message)")
            return
        }
        stopDisplayAgent()
        updateButton()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Macchiato"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = MacchiatoApp()
app.delegate = delegate
app.run()
