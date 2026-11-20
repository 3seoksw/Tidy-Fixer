import AppKit
import SwiftUI

/// Multi-line input that grows with its text up to `maxHeight`, then scrolls.
/// Return submits, Shift+Return inserts a newline.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var focusTick: Int
    var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 900) * 0.35 }
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = MeasuringTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 13)
        tv.textColor = .labelColor
        tv.insertionPointColor = NSColor(red: 244 / 255, green: 89 / 255, blue: 203 / 255, alpha: 1)
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.delegate = context.coordinator
        tv.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measureSoon() }
        context.coordinator.textView = tv

        let sv = NSScrollView()
        sv.documentView = tv
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.measureSoon()
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: MeasuringTextView?
        var lastFocusTick = -1

        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            measure()
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                tv.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        private var measureQueued = false

        /// Measuring during a layout pass triggers a layout-recursion warning, so do it next turn.
        func measureSoon() {
            guard !measureQueued else { return }
            measureQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.measureQueued = false
                self?.measure()
            }
        }

        func measure() {
            guard let tv = textView, let container = tv.textContainer, let lm = tv.layoutManager
            else { return }
            lm.ensureLayout(for: container)
            let used = lm.usedRect(for: container).height
            let lineHeight = lm.defaultLineHeight(for: tv.font ?? .systemFont(ofSize: 13))
            let h = min(max(used, lineHeight).rounded(.up), parent.maxHeight)
            if abs(parent.height - h) > 0.5 {
                DispatchQueue.main.async { self.parent.height = h }
            }
        }
    }
}

final class MeasuringTextView: NSTextView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    /// Copied text often ends with a newline that would leave a blank last line. Newlines are
    /// dropped only where the paste meets the start or end of the field.
    override func paste(_ sender: Any?) {
        guard var text = NSPasteboard.general.string(forType: .string) else { return super.paste(sender) }
        let range = selectedRange()
        if range.upperBound == (string as NSString).length {
            while let last = text.last, last.isNewline { text.removeLast() }
        }
        if range.location == 0 {
            while let first = text.first, first.isNewline { text.removeFirst() }
        }
        insertText(text, replacementRange: range)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }
}
