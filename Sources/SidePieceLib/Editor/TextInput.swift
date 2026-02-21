//
//  TextInput.swift
//  SidePiece
//

#if os(macOS)
import AppKit
import ComposableArchitecture
import SwiftUI

@Reducer
struct TextInputFeature {
    enum InputAction: Sendable, Equatable {
        case none
        case context(String, NSRange)
        case command(String, NSRange)
    }

    @ObservableState
    struct State: Equatable {
        var minHeight: CGFloat
        var maxHeight: CGFloat
        var height: CGFloat
        var action: InputAction
        
        var font: NSFont
        var fontForegroundColor: NSColor
        var lineSpacing: CGFloat
        var textContainer: NSTextContainer
        var textLayoutManager: NSTextLayoutManager
        var textContentStorage: NSTextContentStorage
        var placeholder: String
        var isFocused: Bool
        var cursorPosition: NSRange

        init(
            minHeight: CGFloat,
            maxHeight: CGFloat,
            height: CGFloat,
            action: InputAction = .none,
            font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
            fontForegroundColor: NSColor = .textColor,
            lineSpacing: CGFloat = 1.0,
            textContainer: NSTextContainer = NSTextContainer(),
            textLayoutManager: NSTextLayoutManager = NSTextLayoutManager(),
            textContentStorage: NSTextContentStorage = NSTextContentStorage(),
            placeholder: String = "",
            initialString: NSAttributedString? = nil
        ) {
            self.minHeight = minHeight
            self.maxHeight = maxHeight
            self.height = height
            self.action = action
            self.font = font
            self.fontForegroundColor = fontForegroundColor
            self.lineSpacing = lineSpacing
            self.textContainer = textContainer
            self.textLayoutManager = textLayoutManager
            self.textContentStorage = textContentStorage
            self.placeholder = placeholder
            self.isFocused = false
            self.cursorPosition = NSRange(location: 0, length: 0)
            self.textContainer.widthTracksTextView = true
            self.textContainer.heightTracksTextView = false
            self.textContainer.containerSize = .greatestFiniteHeight
            self.textLayoutManager.textContainer = self.textContainer
            self.textContentStorage.addTextLayoutManager(self.textLayoutManager)
            
            guard let initialString else { return }
            
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing

            let styledString = NSMutableAttributedString(attributedString: initialString)
            styledString.addAttributes([
                .font: font,
                .foregroundColor: fontForegroundColor,
                .paragraphStyle: paragraph,
            ], range: NSRange(location: 0, length: styledString.length))

            self.textContentStorage.textStorage?.setAttributedString(styledString)
        }
        
        init(
            maxLines: UInt = 10,
            action: InputAction = .none,
            font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize),
            fontForegroundColor: NSColor = .textColor,
            lineSpacing: CGFloat = 1.0,
            textContainer: NSTextContainer = NSTextContainer(),
            textLayoutManager: NSTextLayoutManager = NSTextLayoutManager(),
            textContentStorage: NSTextContentStorage = NSTextContentStorage(),
            placeholder: String = "",
            initialString: NSAttributedString? = nil
        ) {
            let fontHeight = font.ascender - font.descender + font.leading
            let height = fontHeight
            let minHeight = fontHeight
            let maxHeight = fontHeight * CGFloat(maxLines)
            
            self.init(
                minHeight: minHeight,
                maxHeight: maxHeight,
                height: height,
                action: action,
                font: font,
                fontForegroundColor: fontForegroundColor,
                lineSpacing: lineSpacing,
                textContainer: textContainer,
                textLayoutManager: textLayoutManager,
                textContentStorage: textContentStorage,
                placeholder: placeholder,
                initialString: initialString
            )
        }
    }
    
    enum Action: Equatable {
        case delegate(DelegateAction)
        case `internal`(InternalAction)
        
        @CasePathable
        enum DelegateAction: Equatable {
            enum Event: Equatable {
                case keyboard(TextViewCommand)
                case action(InputAction)
            }
            case event(Event)
        }
        
        @CasePathable
        enum InternalAction: Equatable {
            case textViewDidChange(NSRange)
            case mouseDown(CGPoint, CGPoint, Int)
            case focusDidChange(Bool)
            case handleCommand(TextViewCommand, Set<TextViewModifier>, NSRange)
            case actionDidChange(InputAction)
        }
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .internal(.textViewDidChange(selectedRange)):
                guard let attributedString = state.textContentStorage.textStorage else {
                    return .none
                }

                // Track cursor position for button-triggered attachments
                state.cursorPosition = selectedRange

                // Make sure the input field height is clamped
                let contentHeight = state.textLayoutManager.usageBoundsForTextContainer.height
                state.height = min(max(contentHeight, state.minHeight), state.maxHeight)

                return reduce(into: &state, action: .internal(.actionDidChange(lookForCommand(
                    from: attributedString,
                    in: selectedRange
                ))))

            case let .internal(.mouseDown(origin, point, index)):
                guard let attributedString = state.textContentStorage.textStorage else {
                    return .none
                }
                guard index < attributedString.length else {
                    return .none
                }
                
                guard index >= 0 else {
                    return .none
                }

                var location = index
                var attachment = attributedString.attribute(
                    .attachment,
                    at: location,
                    effectiveRange: nil
                ) as? VSInlineAttachment
                
                if attachment == nil && index - 1 >= 0 {
                    location = index - 1
                    attachment = attributedString.attribute(
                        .attachment,
                        at: location,
                        effectiveRange: nil
                    ) as? VSInlineAttachment
                }
                
                guard let attachment else {
                    return .none
                }

                let range = NSRange(location: location, length: 1)
                guard let startLocation = state.textContentStorage.location(
                    state.textContentStorage.documentRange.location,
                    offsetBy: range.location
                ) else {
                    return .none
                }
                
                guard let endLocation = state.textContentStorage.location(startLocation, offsetBy: 1) else {
                    return .none
                }
                
                guard let textRange = NSTextRange(location: startLocation, end: endLocation) else {
                    return .none
                }

                var attachmentRect: CGRect = .zero
                state.textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                    attachmentRect = rect
                    return false
                }
                
                // Convert click point to attachment-local coordinates
                let clickInContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)

                // The attachment rect is in flipped coordinates, convert click point
                let relativePoint = CGPoint(
                    x: clickInContainer.x - attachmentRect.origin.x,
                    y: attachmentRect.height - (clickInContainer.y - attachmentRect.origin.y) // Flip Y
                )

                guard attachment.didTapCloseButton(at: relativePoint) else {
                    return .none
                }
    
                // Remove the attachment (and any trailing space)
                let length = min(range.length + 1, attributedString.length - range.location)
                let removeRange = NSRange(location: range.location, length: length)
                attributedString.replaceCharacters(in: removeRange, with: "")

                return .none
                
            case let .internal(.focusDidChange(focused)):
                state.isFocused = focused
                return .none
                
            case let .internal(.actionDidChange(action)):
                state.action = action
                return .send(.delegate(.event(.action(action))))
                
            case let .internal(.handleCommand(command, _, _)):
                return .send(.delegate(.event(.keyboard(command))))
                
            case .internal:
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

extension TextInputFeature {
    private func lookForCommand(
        from attributedString: NSAttributedString,
        in selectedRange: NSRange
    ) -> TextInputFeature.InputAction {
        let string = attributedString.string
        guard let swiftSearchRange = Range(NSRange(location: 0, length: selectedRange.location), in: string) else {
            return .none
        }

        guard let foundRange = string.range(of: "[@/][^\\s]*$", options: .regularExpression, range: swiftSearchRange) else {
            return .none
        }

        // Check for attachments in the matched range
        let nsFoundRange = NSRange(foundRange, in: string)
        var hasAttachment = false
        attributedString.enumerateAttribute(.attachment, in: nsFoundRange, options: []) { value, _, stop in
            if value != nil {
                hasAttachment = true
                stop.pointee = true
            }
        }
        
        guard !hasAttachment else {
            return .none
        }
        
        let matchedString = string[foundRange]
        let query = String(matchedString.dropFirst())
        
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

extension TextInputFeature.State {
    mutating func attach(_ model: VSInlineAttachment.VSAttachmentModel) {
        guard let attributedString = textContentStorage.textStorage else {
            return
        }

        let cell = VSInlineAttachment(
            data: model,
            font: font
        )
        let finalString = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: cell)
        )
        finalString.append(NSAttributedString(string: " "))

        let insertionRange: NSRange = switch action {
        case .none:
            // Insert at cursor position (for button-triggered)
            NSRange(location: cursorPosition.location, length: 0)
        case let .command(_, nsFoundRange), let .context(_, nsFoundRange):
            // Replace @query text (for text-triggered)
            nsFoundRange
        }

        attributedString.replaceCharacters(
            in: insertionRange,
            with: finalString
        )
    }
    
    var content: [ContentPart] {
        return textContentStorage.textStorage?.content ?? []
    }
}

private extension NSAttributedString {
    var content: [ContentPart] {
        let fullRange = NSRange(location: 0, length: length)
        var attachmentRanges: [(range: NSRange, attachment: VSInlineAttachment)] = []
        
        enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard let attachment = value as? VSInlineAttachment else { return }
            attachmentRanges.append((range, attachment))
        }
        
        // Helper to extract text for a range
        func textPart(_ fullString: String, from start: Int, to end: Int) -> ContentPart? {
            guard end > start else { return nil }
            let range = NSRange(location: start, length: end - start)
            guard let swiftRange = Range(range, in: fullString) else { return nil }
            let text = String(fullString[swiftRange])
            guard !text.isEmpty else { return nil }
            return .text(text)
        }
        
        let fullString = string
        var currentIndex = 0
        var content: [ContentPart] = []

        for (range, attachment) in attachmentRanges {
            if let text = textPart(fullString, from: currentIndex, to: range.location) {
                content.append(text)
            }
            if case let .file(url, contentType) = attachment.data.type {
                if contentType.isImageType {
                    content.append(.image(FileSource(url: url, contentType: contentType)))
                } else {
                    content.append(.file(FileSource(url: url, contentType: contentType)))
                }
            }
            currentIndex = range.location + range.length
        }
        
        if let text = textPart(fullString, from: currentIndex, to: fullString.count) {
            content.append(text)
        }
        
        return content
    }
}

private extension Store where State == TextInputFeature.State, Action == TextInputFeature.Action {
    func handle(
        command selector: Selector,
        modifiers: Set<TextViewModifier>,
        in range: NSRange
    ) -> Bool {
        guard let command = TextViewCommand(selector: selector) else {
            return false
        }
        
        // TODO: I think this logic should be programmable
        switch state.action {
        case .none:
            switch command {
            case .insertNewLine:
                if !modifiers.contains(.shift) {
                    send(.internal(.handleCommand(command, modifiers, range)))
                    return true
                }
                return false
            default:
                return false
            }
        case .context, .command:
            send(.internal(.handleCommand(command, modifiers, range)))
            return true
        }
    }
}

class TextInputView: NSScrollView, NSTextViewDelegate {
    class TextView: NSTextView {
        private let store: StoreOf<TextInputFeature>
        
        init(store: StoreOf<TextInputFeature>) {
            self.store = store
            super.init(frame: .zero, textContainer: store.textContainer)
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
            let origin = textContainerOrigin
            
            store.send(.internal(.mouseDown(origin, point, charIndex)))
            super.mouseDown(with: event)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            // Add tracking area for mouse moved events
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
    }
    
    @Bindable var store: StoreOf<TextInputFeature>
    let textView: TextView
    
    init(store: StoreOf<TextInputFeature>) {
        self.store = store
        textView = TextView(store: store)

        super.init(frame: .zero)
        
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
        textView.insertionPointColor = store.fontForegroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = store.lineSpacing
        textView.typingAttributes = [
            .font: store.font,
            .foregroundColor: store.fontForegroundColor,
            .paragraphStyle: paragraph,
        ]
        textView.setValue(
            NSAttributedString(
                string: store.placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: store.font
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func textViewDidChangeSelection(_ notification: Notification) {
        let range = textView.selectedRange()
        store.send(.internal(.textViewDidChange(range)))
    }
    
    func textView(
        _ textView: NSTextView,
        doCommandBy selector: Selector
    ) -> Bool {
        store.handle(
            command: selector,
            modifiers: modifiers,
            in: textView.selectedRange()
        )
    }
    
    private var modifiers: Set<TextViewModifier> {
        guard let event = NSApp.currentEvent else { return [] }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        var map = Set<TextViewModifier>()
        if modifiers.contains(.capsLock) {
            map.insert(.capsLock)
        }
        if modifiers.contains(.shift) {
            map.insert(.shift)
        }
        if modifiers.contains(.control) {
            map.insert(.control)
        }
        if modifiers.contains(.option) {
            map.insert(.option)
        }
        if modifiers.contains(.command) {
            map.insert(.command)
        }
        if modifiers.contains(.numericPad) {
            map.insert(.numericPad)
        }
        if modifiers.contains(.help) {
            map.insert(.help)
        }
        if modifiers.contains(.function) {
            map.insert(.function)
        }
        
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
        nsView.textView.insertionPointColor = store.fontForegroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = store.lineSpacing
        nsView.textView.typingAttributes = [
            .font: store.font,
            .foregroundColor: store.fontForegroundColor,
            .paragraphStyle: paragraph,
        ]
        nsView.textView.setValue(
            NSAttributedString(
                string: store.placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: store.font
                ]
            ),
            forKey: "placeholderAttributedString"
        )

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
