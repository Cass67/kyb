# KyB

KyB is a local-only macOS menu-bar app for mapping global keyboard shortcuts to text snippets.

Unlock your encrypted vault, press a shortcut like `⌃⌥F6`, and KyB inserts the mapped text into the focused field. It is built for local use: no sync, no network service, no cloud account.

## What it does

- Global hotkeys for snippets.
- Local encrypted vault protected by a master password, suitable for sensitive snippets you choose to store.
- Masked snippet text by default, with `Show text` / `Hide text` controls.
- Multiple insertion modes:
  - Auto best effort
  - Aggressive auto (may duplicate)
  - AX focused-field insert with paste fallback
  - AX focused-field insert only
  - Paste + restore clipboard
  - Paste + clear clipboard
  - Type characters without clipboard
- Per-snippet typing delay.
- Quick `Insert` button per snippet.
- Status/log panel for hotkey registration and injection diagnostics.
- Launch-at-login toggle.
- Encrypted vault import/export.

## Install

Use the installer script. It builds KyB, installs it to a stable path, resets stale Accessibility state, and opens the app.

```bash
./scripts/install-app.sh
```

Default install path:

```text
~/Applications/KyB.app
```

After install, grant Accessibility permission:

```text
System Settings → Privacy & Security → Accessibility → KyB
```

Do **not** grant Accessibility to `.build-app/KyB.app`. That bundle is temporary and gets replaced on rebuild.

## First run

1. Run `./scripts/install-app.sh`.
2. In KyB, click `Request` if macOS has not prompted yet.
3. Enable KyB in Accessibility settings.
4. Click `Recheck`; status should show `AX: trusted`.
5. Create or unlock the vault with a master password.
6. Add a mapping, choose a shortcut, choose an insertion mode, and save.

If permission gets stuck, click `Clean Reset` in KyB. It resets KyB’s Accessibility approval, reopens KyB, and opens Accessibility settings.

Terminal reset:

```bash
./scripts/reset-accessibility.sh
```

## Usage tips

- Prefer shortcut combos like `⌃⌥F6` over bare function keys. macOS or another app may steal plain `F6`.
- Use `Auto best effort` for best general behavior.
- Use `Aggressive auto` only when output matters more than avoiding duplicates.
- Use `AX insert only` or `Type characters` if clipboard exposure matters.
- Use `Test in 3s`, then focus a target field, to verify injection outside KyB’s UI.
- Password prompts and secure fields may still block hotkeys or insertion. That is macOS Secure Input behavior.

## Security model

KyB protects snippets **at rest**. While unlocked, snippets are decrypted in process memory so KyB can insert them.

Current hardening:

- Vault stored at:

  ```text
  ~/Library/Application Support/KyB/vault.json
  ```

- Vault file is AES-GCM encrypted.
- New vaults use PBKDF2-HMAC-SHA256 with 600,000 iterations and a 32-byte salt.
- Legacy vaults using 210,000 iterations still open.
- Master password is not stored on disk.
- Derived vault key is kept only while unlocked.
- Vault directory/file permissions are hardened (`0700` dir, `0600` file).
- Vault symlink paths are rejected.
- Import validates vault structure before replacing the current vault.
- Import backs up the existing vault to `vault.backup.json`.
- Export copies encrypted vault bytes only; plaintext mappings are never exported.
- Sensitive-snippet guard warns on passwords, tokens, API keys, private keys, or long high-entropy strings, but does not block saving.
- Install script uses a stable app path and resets stale Accessibility/TCC state.

Important limits:

- If the Mac is compromised while KyB is unlocked, snippets may be readable from memory.
- Clipboard-based insertion exposes snippet text briefly to the system clipboard.
- Clipboard managers may capture pasted text. For passwords/sensitive snippets, use `AX insert only` or `Type characters` where possible.
- macOS secure input/password dialogs may block KyB entirely.
- Unsigned/ad-hoc-signed local builds are more brittle than Developer ID signed + notarized apps.

## Build/check

Quick compile check:

```bash
swiftc Sources/KyB/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework Carbon \
  -framework CryptoKit \
  -framework ServiceManagement \
  -o /tmp/KyB
```

Build app bundle:

```bash
./scripts/build-app.sh
```

Install app bundle:

```bash
./scripts/install-app.sh
```

## Project layout

```text
Sources/KyB/
  KyBApp.swift          App entry point
  AppState.swift        App state, vault operations, permissions, logging
  Models.swift          Mapping, hotkey, injection models
  SecureStore.swift     Encrypted vault read/write + validation
  HotkeyManager.swift   Carbon global hotkey registration
  HotkeyRecorder.swift  UI control for recording shortcuts
  TextInjector.swift    AX, paste, and typed-character insertion
  SnippetGuard.swift    Secret-like snippet detection
  Views.swift           SwiftUI menu-bar UI
scripts/
  build-app.sh          Build app bundle
  install-app.sh        Install to ~/Applications and reset Accessibility
  reset-accessibility.sh Reset TCC + reinstall/open KyB
```

## Why no fancy DMG?

KyB currently works best as a local unsigned tool installed by script. The script can reset stale Accessibility/TCC state, install to a stable path, strip quarantine, and open KyB.

A drag-to-Applications DMG looks nicer, but without a Developer ID certificate and notarization it adds friction and cannot reliably clean up Accessibility permissions.

## License

Local tool. Add license before distribution.
