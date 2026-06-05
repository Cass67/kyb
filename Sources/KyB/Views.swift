import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView()
            Divider()
            if app.isUnlocked {
                MappingsView()
            } else {
                LoginView()
            }
        }
        .padding(16)
        .frame(width: 860, height: 720)
    }
}

struct HeaderView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KyB").font(.title2.bold())
                    Text(app.isUnlocked ? "Unlocked · Auto-lock \(app.autoLockLabel)" : app.vaultExists ? "Unlock local vault" : "Create local vault")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                Toggle("Launch at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                if app.isUnlocked {
                    Picker("Auto-lock", selection: $app.autoLockMinutes) {
                        Text("Off").tag(0)
                        Text("5m").tag(5)
                        Text("10m").tag(10)
                        Text("30m").tag(30)
                    }
                    .frame(width: 120)
                    Button("Lock") { app.lock() }
                }
            }
            if !app.isRunningFromStablePath {
                Text("Running from build dir. Install to ~/Applications or /Applications before granting Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Text("Accessibility: \(app.accessibilityStatusText)")
                    .font(.caption.bold())
                    .foregroundStyle(app.needsAccessibility ? .orange : .green)
                Spacer()
                Button("Request") { app.requestAccessibility() }
                Button("Open Settings") { app.openAccessibilitySettings() }
                Button("Clean Reset") { app.cleanResetAccessibilityAndReopen() }
                Button("Recheck") { app.refreshAccessibility() }
            }
            if let message = app.permissionMessage {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
            if !app.diagnosticStatus.isEmpty {
                Text(app.diagnosticStatus).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.vaultExists ? "Enter master password" : "Choose master password")
                .font(.headline)
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { app.unlock(password: password) }
            Button(app.vaultExists ? "Unlock" : "Create Vault") { app.unlock(password: password) }
                .keyboardShortcut(.defaultAction)
            if let error = app.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Text("Vault: \(app.vaultPath)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Password not stored. Vault key kept only while unlocked. Secret-like snippets are blocked.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("macOS secure fields may block hotkeys, paste, AX insert, or typed injection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
}

struct MappingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mappings").font(.headline)
                    Text(app.hotkeyStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack {
                        Button("Test now") { app.testInjection() }
                        Button("Test in 3s") { app.delayedTestInjection() }
                        Button("Add") { app.addMapping() }
                        Button("Save") { app.save() }
                    }
                    HStack {
                        Button("Import vault") { app.importVault() }
                        Button("Export vault") { app.exportVault() }
                    }
                }
            }
            if !app.delayedTestStatus.isEmpty {
                Text(app.delayedTestStatus).font(.caption).foregroundStyle(.orange)
            }
            if !app.securityWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(app.securityWarnings, id: \.self) { warning in
                        Text(warning).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            List {
                ForEach($app.mappings) { $mapping in
                    MappingRow(mapping: $mapping) { app.delete(mapping) }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
            }
            .frame(minHeight: 365)
            if let error = app.errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            Text("AX mode tries focused-field insert first. Paste fallback uses clipboard briefly. Type mode avoids clipboard; delay controls speed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LogView()
        }
    }
}

struct MappingRow: View {
    @EnvironmentObject var app: AppState
    @Binding var mapping: Mapping
    var onDelete: () -> Void
    @State private var showText = false

    var maskedText: String {
        mapping.text.isEmpty ? "Empty snippet" : String(repeating: "•", count: max(6, mapping.text.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Toggle("Enabled", isOn: $mapping.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                TextField("Name", text: $mapping.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                HotkeyRecorder(combo: $mapping.combo)
                    .frame(width: 140, height: 30)
                Spacer()
                Button("Insert") { app.inject(mapping) }
                    .keyboardShortcut(.return, modifiers: [])
                Button(showText ? "Hide text" : "Show text") { showText.toggle() }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(alignment: .center, spacing: 12) {
                LabeledContent("Mode") {
                    Picker("Mode", selection: $mapping.injectionMode) {
                        ForEach(InjectionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
                LabeledContent("Typing delay") {
                    Stepper("\(mapping.typingDelayMs) ms", value: $mapping.typingDelayMs, in: 0 ... 100)
                        .frame(width: 125)
                }
                Spacer()
            }
            .font(.caption)

            Group {
                if showText {
                    TextEditor(text: $mapping.text)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text(maskedText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(mapping.text.isEmpty ? .tertiary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
            }
            .frame(minHeight: 64)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.14)))
        .onChange(of: mapping) { app.scheduleSave() }
    }
}

struct LogView: View {
    @EnvironmentObject var app: AppState
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(app.eventLog, id: \.self) { line in
                        Text(line).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(height: 92)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        } label: {
            Text("Log")
                .font(.caption.bold())
        }
    }
}
