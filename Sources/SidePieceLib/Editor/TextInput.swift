//
//  TextInput.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

// MARK: - Feature (Platform-agnostic)

@Reducer
public struct TextInputFeature: Sendable {
    public enum InputAction: Sendable, Equatable {
        case none
        case context(String, NSRange)
        case command(String, NSRange)
    }

    @ObservableState
    public struct State: Equatable {
        var minHeight: CGFloat
        var maxHeight: CGFloat
        var height: CGFloat
        var action: InputAction

        var text: String
        var attachments: [AttachmentModel]
        var cursorPosition: Int
        var placeholder: String
        var isFocused: Bool

        init(
            minHeight: CGFloat,
            maxHeight: CGFloat,
            height: CGFloat,
            action: InputAction = .none,
            placeholder: String = "",
            text: String = "",
            attachments: [AttachmentModel] = []
        ) {
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.height = height
            self.action = action
            self.text = text
            self.attachments = attachments
            self.cursorPosition = text.count
            self.placeholder = placeholder
            self.isFocused = false
        }

        init(
            maxLines: UInt = 10,
            action: InputAction = .none,
            lineHeight: CGFloat = AppFont.monoSpacedFont(size: 15).lineHeight,
            placeholder: String = "",
            text: String = "",
            attachments: [AttachmentModel] = []
        ) {
            let minHeight = lineHeight
            let maxHeight = lineHeight * CGFloat(maxLines)

            self.init(
                minHeight: minHeight,
                maxHeight: maxHeight,
                height: minHeight,
                action: action,
                placeholder: placeholder,
                text: text,
                attachments: attachments
            )
        }
    }

    public enum Action: Equatable {
        case delegate(DelegateAction)
        case `internal`(InternalAction)

        @CasePathable
        public enum DelegateAction: Equatable {
            public enum Event: Equatable {
                case keyboard(TextViewCommand)
                case action(InputAction)
            }
            case event(Event)
        }

        @CasePathable
        public enum InternalAction: Equatable {
            case textDidChange(String, [AttachmentModel], Int, CGFloat)
            case focusDidChange(Bool)
            case handleCommand(TextViewCommand, Set<TextViewModifier>)
            case actionDidChange(InputAction)
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .internal(.textDidChange(text, attachments, cursor, contentHeight)):
                state.text = text
                state.attachments = attachments
                state.cursorPosition = cursor
                state.height = min(max(contentHeight, state.minHeight), state.maxHeight)

                return reduce(into: &state, action: .internal(.actionDidChange(lookForCommand(
                    from: text,
                    attachments: attachments,
                    at: cursor
                ))))

            case let .internal(.focusDidChange(focused)):
                state.isFocused = focused
                return .none

            case let .internal(.actionDidChange(action)):
                state.action = action
                return .send(.delegate(.event(.action(action))))

            case let .internal(.handleCommand(command, _)):
                return .send(.delegate(.event(.keyboard(command))))

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - Command Detection

extension TextInputFeature {
    fileprivate func lookForCommand(
        from text: String,
        attachments: [AttachmentModel],
        at cursorPosition: Int
    ) -> TextInputFeature.InputAction {
        let clampedCursor = min(cursorPosition, text.count)
        let searchEnd = text.index(text.startIndex, offsetBy: clampedCursor)
        let searchRange = text.startIndex..<searchEnd

        guard let foundRange = text.range(
            of: "[@/][^\\s]*$",
            options: .regularExpression,
            range: searchRange
        ) else {
            return .none
        }

        // Check for attachment placeholders in the matched range
        let matchedString = text[foundRange]
        if matchedString.contains("\u{FFFC}") {
            return .none
        }

        let query = String(matchedString.dropFirst())
        let nsFoundRange = NSRange(foundRange, in: text)

        if matchedString.hasPrefix("@") {
            return .context(query, nsFoundRange)
        }
        // TODO: Commands not yet supported
//        else if matchedString.hasPrefix("/") {
//            return .command(query, nsFoundRange)
//        }

        return .none
    }
}

// MARK: - State Helpers

extension TextInputFeature.State {
    mutating func attach(_ model: AttachmentModel) {
        let insertionPoint: String.Index
        let replacementRange: Range<String.Index>

        switch action {
        case .none:
            let pos = min(cursorPosition, text.count)
            insertionPoint = text.index(text.startIndex, offsetBy: pos)
            replacementRange = insertionPoint..<insertionPoint
        case let .command(_, nsRange), let .context(_, nsRange):
            guard let range = Range(nsRange, in: text) else { return }
            insertionPoint = range.lowerBound
            replacementRange = range
        }

        // Count attachments before insertion point to find correct array index
        let prefix = text[text.startIndex..<insertionPoint]
        let attachmentIndex = prefix.filter { $0 == "\u{FFFC}" }.count

        // Replace text
        text.replaceSubrange(replacementRange, with: "\u{FFFC} ")

        // Insert attachment at the right position
        attachments.insert(model, at: min(attachmentIndex, attachments.count))

        // Update cursor to after the inserted attachment + space
        let newPos = text.distance(from: text.startIndex, to: insertionPoint) + 2
        cursorPosition = newPos
    }

    var content: [ContentPart] {
        var parts: [ContentPart] = []
        var attachmentIndex = 0
        var currentText = ""

        for char in text {
            if char == "\u{FFFC}", attachmentIndex < attachments.count {
                if !currentText.isEmpty {
                    parts.append(.text(currentText))
                    currentText = ""
                }
                let attachment = attachments[attachmentIndex]
                switch attachment.type {
                case let .file(url, contentType):
                    if contentType.isImageType {
                        parts.append(.image(FileSource(url: url, contentType: contentType)))
                    } else {
                        parts.append(.file(FileSource(url: url, contentType: contentType)))
                    }
                case .tool:
                    break
                }
                attachmentIndex += 1
            } else {
                currentText.append(char)
            }
        }

        if !currentText.isEmpty {
            parts.append(.text(currentText))
        }

        return parts
    }
}

// MARK: - Store Helpers

extension Store where State == TextInputFeature.State, Action == TextInputFeature.Action {
    func shouldConsumeCommand(
        _ command: TextViewCommand,
        modifiers: Set<TextViewModifier>
    ) -> Bool {
        switch state.action {
        case .none:
            switch command {
            case .insertNewLine:
                return !modifiers.contains(.shift)
            default:
                return false
            }
        case .context, .command:
            return true
        }
    }
}

// MARK: - macOS View

#if os(macOS)
import AppKit

private extension Store where State == TextInputFeature.State, Action == TextInputFeature.Action {
    func handle(
        command selector: Selector,
        modifiers: Set<TextViewModifier>
    ) -> Bool {
        guard let command = TextViewCommand(selector: selector) else {
            return false
        }
        guard shouldConsumeCommand(command, modifiers: modifiers) else {
            return false
        }
        send(.internal(.handleCommand(command, modifiers)))
        return true
    }
}

class TextInputView: NSScrollView, NSTextViewDelegate {
    static let inputFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let inputFontColor = NSColor.white
    static let inputLineSpacing: CGFloat = 4

    class TextView: NSTextView {
        private let store: StoreOf<TextInputFeature>

        init(store: StoreOf<TextInputFeature>, textContainer: NSTextContainer) {
            self.store = store
            super.init(frame: .zero, textContainer: textContainer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func paste(_ sender: Any?) {
            pasteAsPlainText(sender)
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndexForInsertion(at: point)

            handleAttachmentClose(at: point, charIndex: charIndex)
            super.mouseDown(with: event)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result { store.send(.internal(.focusDidChange(true))) }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { store.send(.internal(.focusDidChange(false))) }
            return result
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if store.isFocused, let window {
                window.makeFirstResponder(self)
            }
        }

        private func handleAttachmentClose(at point: CGPoint, charIndex: Int) {
            guard let attributedString = textContentStorage?.textStorage else { return }
            guard charIndex >= 0, charIndex < attributedString.length else { return }

            var location = charIndex
            var attachment = attributedString.attribute(
                .attachment,
                at: location,
                effectiveRange: nil
            ) as? VSInlineAttachment

            if attachment == nil, charIndex - 1 >= 0 {
                location = charIndex - 1
                attachment = attributedString.attribute(
                    .attachment,
                    at: location,
                    effectiveRange: nil
                ) as? VSInlineAttachment
            }

            guard let attachment else { return }

            let range = NSRange(location: location, length: 1)
            guard let tlm = textLayoutManager,
                  let tcs = textContentStorage,
                  let startLocation = tcs.location(
                      tcs.documentRange.location,
                      offsetBy: range.location
                  ),
                  let endLocation = tcs.location(startLocation, offsetBy: 1),
                  let textRange = NSTextRange(location: startLocation, end: endLocation)
            else { return }

            var attachmentRect: CGRect = .zero
            tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                attachmentRect = rect
                return false
            }

            let origin = textContainerOrigin
            let clickInContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            let relativePoint = CGPoint(
                x: clickInContainer.x - attachmentRect.origin.x,
                y: attachmentRect.height - (clickInContainer.y - attachmentRect.origin.y)
            )

            guard attachment.didTapCloseButton(at: relativePoint) else { return }

            let length = min(range.length + 1, attributedString.length - range.location)
            let removeRange = NSRange(location: range.location, length: length)
            attributedString.replaceCharacters(in: removeRange, with: "")
        }
    }

    @Bindable var store: StoreOf<TextInputFeature>
    let textView: TextView
    private let textContentStorage: NSTextContentStorage
    private let textLayoutManager: NSTextLayoutManager
    private var isUpdatingFromState = false

    init(store: StoreOf<TextInputFeature>) {
        self.store = store

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.containerSize = .greatestFiniteHeight

        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = textContainer

        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        self.textContentStorage = contentStorage
        self.textLayoutManager = layoutManager
        textView = TextView(store: store, textContainer: textContainer)

        super.init(frame: .zero)

        let font = Self.inputFont
        let fontColor = Self.inputFontColor
        let lineSpacing = Self.inputLineSpacing

        textView.delegate = self
        textView.allowsUndo = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = .clear
        textView.autoresizingMask = [.width]
        textView.maxSize = .greatestFiniteSize
        textView.minSize = .zero
        textView.insertionPointColor = fontColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: fontColor,
            .paragraphStyle: paragraph,
        ]
        textView.setValue(
            NSAttributedString(
                string: store.placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: font
                ]
            ),
            forKey: "placeholderAttributedString"
        )

        backgroundColor = .clear
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        documentView = textView

        NotificationCenter.default.addObserver(forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: nil, queue: .main, using: { _ in
            fatalError("willSwitchToNSLayoutManagerNotification")
        })

        NotificationCenter.default.addObserver(forName: NSTextView.didSwitchToNSLayoutManagerNotification, object: nil, queue: .main, using: { _ in
            fatalError("didSwitchToNSLayoutManagerNotification")
        })

        // Initialize with existing state content
        if !store.text.isEmpty {
            rebuildContent(text: store.text, attachments: store.attachments)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State <-> View Sync

    func rebuildContent(text: String, attachments: [AttachmentModel]) {
        guard let textStorage = textContentStorage.textStorage else { return }

        let font = Self.inputFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.inputLineSpacing

        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.inputFontColor,
            .paragraphStyle: paragraph,
        ]

        let attrString = NSMutableAttributedString(string: text, attributes: defaultAttrs)

        // Replace placeholder characters with actual attachment objects
        var attachmentIndex = 0
        let nsString = attrString.string as NSString
        for i in 0..<nsString.length {
            if nsString.character(at: i) == 0xFFFC, attachmentIndex < attachments.count {
                let model = attachments[attachmentIndex]
                let cell = VSInlineAttachment(data: model, font: font)
                attrString.addAttribute(
                    .attachment, value: cell,
                    range: NSRange(location: i, length: 1)
                )
                attachmentIndex += 1
            }
        }

        isUpdatingFromState = true
        textStorage.setAttributedString(attrString)
        isUpdatingFromState = false
    }

    private func extractCurrentAttachments() -> [AttachmentModel] {
        guard let textStorage = textContentStorage.textStorage else { return [] }
        var attachments: [AttachmentModel] = []
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, _ in
            guard let attachment = value as? VSInlineAttachment else { return }
            attachments.append(attachment.data)
        }
        return attachments
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isUpdatingFromState else { return }

        let text = textView.string
        let cursor = textView.selectedRange().location
        let contentHeight = textLayoutManager.usageBoundsForTextContainer.height
        let attachments = extractCurrentAttachments()

        store.send(.internal(.textDidChange(text, attachments, cursor, contentHeight)))
    }

    func textView(
        _ textView: NSTextView,
        doCommandBy selector: Selector
    ) -> Bool {
        store.handle(
            command: selector,
            modifiers: modifiers
        )
    }

    private var modifiers: Set<TextViewModifier> {
        guard let event = NSApp.currentEvent else { return [] }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var map = Set<TextViewModifier>()
        if modifiers.contains(.capsLock) { map.insert(.capsLock) }
        if modifiers.contains(.shift) { map.insert(.shift) }
        if modifiers.contains(.control) { map.insert(.control) }
        if modifiers.contains(.option) { map.insert(.option) }
        if modifiers.contains(.command) { map.insert(.command) }
        if modifiers.contains(.numericPad) { map.insert(.numericPad) }
        if modifiers.contains(.help) { map.insert(.help) }
        if modifiers.contains(.function) { map.insert(.function) }

        return map
    }
}

@MainActor
struct TextInputViewRepresentable: NSViewRepresentable {
    @Bindable var store: StoreOf<TextInputFeature>

    func makeNSView(context: Context) -> TextInputView {
        return TextInputView(store: store)
    }

    func updateNSView(
        _ nsView: TextInputView,
        context: Context
    ) {
        let font = TextInputView.inputFont
        let fontColor = TextInputView.inputFontColor
        let lineSpacing = TextInputView.inputLineSpacing

        nsView.textView.insertionPointColor = fontColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        nsView.textView.typingAttributes = [
            .font: font,
            .foregroundColor: fontColor,
            .paragraphStyle: paragraph,
        ]
        nsView.textView.setValue(
            NSAttributedString(
                string: store.placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: font
                ]
            ),
            forKey: "placeholderAttributedString"
        )

        // Sync state → view when text changed externally (e.g. attach() or clear)
        if nsView.textView.string != store.text {
            nsView.rebuildContent(text: store.text, attachments: store.attachments)
        }

        if store.isFocused,
           let window = nsView.textView.window,
           window.firstResponder !== nsView.textView {
            window.makeFirstResponder(nsView.textView)
        }
    }
}

extension NSSize {
    static var greatestFiniteSize: Self {
        NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    static var greatestFiniteHeight: Self {
        NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}
#endif

// MARK: - iOS View

#if os(iOS)
import UIKit

@MainActor
struct TextInputViewRepresentable: UIViewRepresentable {
    @Bindable var store: StoreOf<TextInputFeature>

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no

        if !store.text.isEmpty {
            textView.text = store.text
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.isUpdatingFromState = true
        defer { context.coordinator.isUpdatingFromState = false }

        if uiView.text != store.text {
            uiView.text = store.text
        }

        if store.isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let store: StoreOf<TextInputFeature>
        var isUpdatingFromState = false

        init(store: StoreOf<TextInputFeature>) {
            self.store = store
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromState else { return }

            let text = textView.text ?? ""
            let cursor = textView.selectedRange.location
            let contentHeight = textView.contentSize.height

            store.send(.internal(.textDidChange(text, [], cursor, contentHeight)))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingFromState else { return }

            let text = textView.text ?? ""
            let cursor = textView.selectedRange.location
            let contentHeight = textView.contentSize.height

            store.send(.internal(.textDidChange(text, [], cursor, contentHeight)))
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            store.send(.internal(.focusDidChange(true)))
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            store.send(.internal(.focusDidChange(false)))
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // Detect Return key (without shift) for submit
            if text == "\n" {
                let command = TextViewCommand.insertNewLine
                if store.shouldConsumeCommand(command, modifiers: []) {
                    store.send(.internal(.handleCommand(command, [])))
                    return false
                }
            }
            return true
        }
    }
}
#endif
