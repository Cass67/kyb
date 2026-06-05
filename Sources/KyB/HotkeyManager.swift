import Carbon
import Foundation

struct HotkeyRegistrationReport {
    var registered: Int = 0
    var failures: [String] = []
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(mappings: [Mapping], action: @escaping (Mapping) -> Void) -> HotkeyRegistrationReport {
        unregisterAll()
        var report = HotkeyRegistrationReport()
        if let handlerError = installHandlerIfNeeded() {
            report.failures.append(handlerError)
        }

        for mapping in mappings where mapping.enabled && !mapping.text.isEmpty {
            let id = nextID
            nextID += 1
            let eventID = EventHotKeyID(signature: OSType(0x4B79_4248), id: id) // KyBH
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                mapping.combo.keyCode,
                mapping.combo.modifiers.carbonFlags,
                eventID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr {
                refs.append(ref)
                actions[id] = { action(mapping) }
                report.registered += 1
            } else {
                let message = "Failed hotkey \(mapping.combo.description), status \(status)"
                report.failures.append(message)
                NSLog("KyB: \(message)")
            }
        }
        return report
    }

    func unregisterAll() {
        for ref in refs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        refs.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() -> String? {
        guard !handlerInstalled else { return nil }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                DispatchQueue.main.async {
                    HotkeyManager.shared.actions[hotKeyID.id]?()
                }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        if status == noErr {
            handlerInstalled = true
            return nil
        }
        return "Failed installing hotkey handler, status \(status)"
    }
}
