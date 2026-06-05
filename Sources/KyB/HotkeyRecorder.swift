import AppKit
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context _: Context) -> RecorderView {
        let view = RecorderView()
        view.onCombo = { combo = $0 }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context _: Context) {
        nsView.combo = combo
    }
}

final class RecorderView: NSView {
    var combo: KeyCombo = .init(keyCode: 97, modifiers: [.control, .option]) {
        didSet { needsDisplay = true }
    }

    var onCombo: ((KeyCombo) -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with _: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = carbonModifiers(from: event.modifierFlags)
        let newCombo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: flags)
        combo = newCombo
        onCombo?(newCombo)
        recording = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        let text = recording ? "Press combo…" : combo.description
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: max(8, (bounds.width - size.width) / 2), y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> ModifierFlags {
        var result: ModifierFlags = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }
}
