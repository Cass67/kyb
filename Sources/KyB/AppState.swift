import AppKit
import ApplicationServices
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isUnlocked = false
    @Published var mappings: [Mapping] = []
    @Published var errorMessage: String?
    @Published var securityWarnings: [String] = []
    @Published var hotkeyStatus = "No hotkeys registered yet."
    @Published var needsAccessibility = !AXIsProcessTrusted()
    @Published var permissionMessage: String?
    @Published var diagnosticStatus = ""
    @Published var delayedTestStatus = ""
    @Published var eventLog: [String] = []
    @Published var launchAtLogin = false
    @Published var autoLockMinutes = 10 {
        didSet { scheduleAutoLock() }
    }

    private let store: SecureStore
    private let injector = TextInjector()
    private var session: VaultSession?
    private var autoLockTask: DispatchWorkItem?
    private var saveTask: DispatchWorkItem?

    init() {
        do {
            store = try SecureStore()
            refreshLaunchAtLogin()
        } catch {
            fatalError("Cannot create store: \(error)")
        }
    }

    var vaultExists: Bool {
        store.exists
    }

    var vaultPath: String {
        store.path
    }

    var autoLockLabel: String {
        autoLockMinutes == 0 ? "Off" : "\(autoLockMinutes)m"
    }

    var appBundlePath: String {
        Bundle.main.bundlePath
    }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var accessibilityStatusText: String {
        AXIsProcessTrusted() ? "trusted" : "not trusted"
    }

    var isRunningFromStablePath: Bool {
        let path = appBundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        permissionMessage = "Use macOS prompt to open Accessibility settings, then enable KyB. Quit/reopen if TCC does not refresh live."
        pollAccessibilityStatus()
        log("Requested Accessibility permission")
    }

    func refreshAccessibility() {
        needsAccessibility = !AXIsProcessTrusted()
        permissionMessage = needsAccessibility ? "KyB still lacks Accessibility. If already enabled, quit/reopen or reset KyB entry." : "Accessibility granted."
        diagnosticStatus = "AX: \(accessibilityStatusText) · bundle: \(bundleIdentifier) · path: \(appBundlePath)"
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func cleanResetAccessibilityAndReopen() {
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("kyb-reset-accessibility-\(UUID().uuidString).sh")
        let script = """
        #!/bin/zsh
        set -euo pipefail
        trap 'rm -f "$0"' EXIT
        sleep 0.8
        /usr/bin/tccutil reset Accessibility \(shellQuote(bundleIdentifier))
        /usr/bin/open \(shellQuote(appBundlePath))
        sleep 0.8
        /usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path]
            try process.run()
            log("Clean Accessibility reset launched; KyB will reopen")
            NSApplication.shared.terminate(nil)
        } catch {
            errorMessage = error.localizedDescription
            log("Clean Accessibility reset failed: \(error.localizedDescription)")
        }
    }

    private func pollAccessibilityStatus() {
        for delay in 1 ... 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                self?.refreshAccessibility()
            }
        }
    }

    func unlock(password: String) {
        errorMessage = nil
        securityWarnings = []
        guard password.count >= 8 else {
            errorMessage = "Password needs 8+ chars"
            return
        }
        do {
            if store.exists {
                let unlocked = try store.unlock(password: password)
                mappings = unlocked.mappings
                session = unlocked.session
            } else {
                mappings = [Mapping(name: "Example", combo: .init(keyCode: 97, modifiers: [.control, .option]), text: "Hello from KyB")]
                session = try store.create(password: password, mappings: mappings)
            }
            isUnlocked = true
            registerHotkeys()
            scheduleAutoLock()
            log("Vault unlocked")
        } catch {
            errorMessage = error.localizedDescription
            log("Unlock failed: \(error.localizedDescription)")
        }
    }

    func lock() {
        HotkeyManager.shared.unregisterAll()
        autoLockTask?.cancel()
        autoLockTask = nil
        session = nil
        mappings = []
        isUnlocked = false
        log("Vault locked")
    }

    func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.save() }
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    func save() {
        guard isUnlocked else { return }
        saveTask?.cancel()
        saveTask = nil
        securityWarnings = SnippetGuard.blockingWarnings(for: mappings)
        guard securityWarnings.isEmpty else {
            errorMessage = "Save blocked by secret guard"
            HotkeyManager.shared.unregisterAll()
            log("Save blocked by secret guard")
            return
        }
        guard let session else {
            errorMessage = SecureStoreError.missingSession.localizedDescription
            return
        }
        do {
            try store.save(mappings: mappings, session: session)
            registerHotkeys()
            scheduleAutoLock()
            errorMessage = nil
            log("Saved \(mappings.count) mapping(s)")
        } catch {
            errorMessage = error.localizedDescription
            log("Save failed: \(error.localizedDescription)")
        }
    }

    func addMapping() {
        mappings.append(Mapping(name: "New", combo: .init(keyCode: 97, modifiers: [.control, .option]), text: ""))
        save()
    }

    func delete(_ mapping: Mapping) {
        mappings.removeAll { $0.id == mapping.id }
        save()
    }

    func inject(_ mapping: Mapping) {
        let result = injector.inject(mapping.text, mode: mapping.injectionMode, typingDelayMs: mapping.typingDelayMs)
        log("\(mapping.name.isEmpty ? mapping.combo.description : mapping.name): \(result.method) · \(result.message)")
        scheduleAutoLock()
    }

    func testInjection() {
        let result = injector.inject("KyB test", mode: .accessibilityThenPaste)
        log("Test now: \(result.method) · \(result.message)")
    }

    func delayedTestInjection() {
        delayedTestStatus = "Focus target field now. Pasting in 3…"
        for second in 1 ... 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(second)) { [weak self] in
                let remaining = 3 - second
                self?.delayedTestStatus = remaining == 0 ? "Pasting now." : "Focus target field now. Pasting in \(remaining)…"
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) { [weak self] in
            guard let self else { return }
            let result = injector.inject("KyB delayed test", mode: .accessibilityThenPaste)
            delayedTestStatus = "Delayed test sent: \(result.method)."
            log("Delayed test: \(result.method) · \(result.message)")
        }
    }

    func exportVault() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "kyb-vault.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let source = URL(fileURLWithPath: vaultPath).standardizedFileURL
                let destination = url.standardizedFileURL
                guard source.path != destination.path else { throw SecureStoreError.unsafePath }
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                log("Exported encrypted vault to \(destination.lastPathComponent)")
            } catch {
                errorMessage = error.localizedDescription
                log("Export failed: \(error.localizedDescription)")
            }
        }
    }

    func importVault() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let source = url.standardizedFileURL
                let dest = URL(fileURLWithPath: vaultPath).standardizedFileURL
                guard source.path != dest.path else { throw SecureStoreError.unsafePath }
                try store.validateImportCandidate(source)
                lock()
                let backup = dest.deletingLastPathComponent().appendingPathComponent("vault.backup.json")
                if FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.removeItem(at: backup)
                }
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.copyItem(at: dest, to: backup)
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                log("Imported encrypted vault. Previous vault backed up. Unlock with imported vault password.")
            } catch {
                errorMessage = error.localizedDescription
                log("Import failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            refreshLaunchAtLogin()
            log("Launch at login \(launchAtLogin ? "enabled" : "disabled")")
        } catch {
            errorMessage = error.localizedDescription
            refreshLaunchAtLogin()
            log("Launch at login failed: \(error.localizedDescription)")
        }
    }

    private func registerHotkeys() {
        let report = HotkeyManager.shared.register(mappings: mappings) { [weak self] mapping in
            self?.inject(mapping)
        }
        if report.failures.isEmpty {
            hotkeyStatus = "Registered \(report.registered) hotkey(s)."
        } else {
            hotkeyStatus = "Registered \(report.registered), failures: \(report.failures.joined(separator: "; "))"
        }
        log(hotkeyStatus)
    }

    private func scheduleAutoLock() {
        autoLockTask?.cancel()
        guard isUnlocked, autoLockMinutes > 0 else { return }
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.lock() }
        }
        autoLockTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(autoLockMinutes * 60), execute: task)
    }

    private func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        eventLog.insert("\(ts)  \(message)", at: 0)
        if eventLog.count > 30 { eventLog.removeLast(eventLog.count - 30) }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
