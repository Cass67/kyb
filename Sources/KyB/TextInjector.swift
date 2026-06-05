import AppKit
import ApplicationServices
import CoreGraphics

struct InjectionResult {
    let method: String
    let success: Bool
    let message: String
}

final class TextInjector {
    func inject(_ text: String, mode: InjectionMode, typingDelayMs: Int = 2) -> InjectionResult {
        guard !text.isEmpty else {
            return InjectionResult(method: "none", success: true, message: "empty snippet")
        }
        switch mode {
        case .bestEffort:
            let ax = accessibilityInsert(text)
            if ax.success { return ax }
            paste(text, restoreClipboard: true)
            return InjectionResult(method: "auto", success: true, message: "AX failed: \(ax.message); used paste fallback")
        case .aggressiveBestEffort:
            let ax = accessibilityInsert(text)
            if ax.success { return ax }
            paste(text, restoreClipboard: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.typeCharacters(text, delayMs: typingDelayMs)
            }
            return InjectionResult(method: "aggressive", success: true, message: "AX failed: \(ax.message); sent paste, then typed fallback (may duplicate)")
        case .accessibilityThenPaste:
            let ax = accessibilityInsert(text)
            if ax.success { return ax }
            paste(text, restoreClipboard: true)
            return InjectionResult(method: "paste", success: true, message: "AX failed: \(ax.message); used paste fallback")
        case .accessibilityOnly:
            return accessibilityInsert(text)
        case .pasteAndRestoreClipboard:
            paste(text, restoreClipboard: true)
            return InjectionResult(method: "paste", success: true, message: "pasted, clipboard restored")
        case .pasteAndClearClipboard:
            paste(text, restoreClipboard: false)
            return InjectionResult(method: "paste", success: true, message: "pasted, clipboard cleared")
        case .typeCharacters:
            typeCharacters(text, delayMs: typingDelayMs)
            return InjectionResult(method: "type", success: true, message: "typed with \(typingDelayMs)ms delay")
        }
    }

    private func accessibilityInsert(_ text: String) -> InjectionResult {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedStatus == .success, let focused = focusedRef else {
            return InjectionResult(method: "ax", success: false, message: "no focused AX element (\(focusedStatus.rawValue))")
        }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return InjectionResult(method: "ax", success: false, message: "focused object is not AX element")
        }
        let element = focused as! AXUIElement

        var valueRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let current: String
        if valueStatus == .success {
            guard let stringValue = valueRef as? String else {
                return InjectionResult(method: "ax", success: false, message: "focused element value is not text")
            }
            current = stringValue
        } else {
            current = ""
        }

        var rangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        if rangeStatus == .success, let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue((rangeValue as! AXValue), .cfRange, &range) {
                let ns = current as NSString
                let safeLocation = max(0, min(range.location, ns.length))
                let safeLength = max(0, min(range.length, ns.length - safeLocation))
                let next = ns.replacingCharacters(in: NSRange(location: safeLocation, length: safeLength), with: text)
                let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, next as CFTypeRef)
                if setStatus == .success {
                    var cursor = CFRange(location: safeLocation + (text as NSString).length, length: 0)
                    if let cursorValue = AXValueCreate(.cfRange, &cursor) {
                        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, cursorValue)
                    }
                    return InjectionResult(method: "ax", success: true, message: "inserted into focused field")
                }
                return InjectionResult(method: "ax", success: false, message: "set AX value failed (\(setStatus.rawValue))")
            }
        }

        if valueStatus == .success {
            let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (current + text) as CFTypeRef)
            if setStatus == .success {
                return InjectionResult(method: "ax", success: true, message: "appended to focused field")
            }
            return InjectionResult(method: "ax", success: false, message: "append AX value failed (\(setStatus.rawValue))")
        }

        return InjectionResult(method: "ax", success: false, message: "focused element has no string value")
    }

    private func paste(_ text: String, restoreClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendKeyDown(keyCode: 9, flags: .maskCommand)
        sendKeyUp(keyCode: 9, flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pasteboard.clearContents()
            if restoreClipboard, let old {
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    private func typeCharacters(_ text: String, delayMs: Int) {
        for scalar in text.unicodeScalars {
            var value = UniChar(scalar.value)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(useconds_t(max(0, delayMs) * 1000))
        }
    }

    private func sendKeyDown(keyCode: CGKeyCode, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func sendKeyUp(keyCode: CGKeyCode, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}
