//
//  KeyboardClient.swift
//  SidePiece
//

import AppKit
import Dependencies
import DependenciesMacros
import SwiftUI

@DependencyClient
public struct KeyboardClient: Sendable {
    var start: @Sendable (@Sendable @escaping (KeyboardShortcut) -> Bool) -> AsyncStream<KeyboardShortcut> = { _ in .finished }
}

extension KeyboardClient: DependencyKey {
    private final class MonitorReference: @unchecked Sendable {
        public let monitor: Any
        
        init(monitor: Any) {
            self.monitor = monitor
        }
    }
    
    public static let liveValue = KeyboardClient(
        start: { canConsume in
            let (stream, continuation) = AsyncStream.makeStream(of: KeyboardShortcut.self)
            
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let key = KeyboardShortcut(event: event) else { return event }
                guard canConsume(key) else { return event }
                continuation.yield(key)
                return nil
            }
            guard let monitor else { return .finished }

            let lock = MonitorReference(monitor: monitor)
            continuation.onTermination = { _ in
                NSEvent.removeMonitor(lock.monitor)
            }
            return stream
        }
    )
}

extension DependencyValues {
    public var keyboardClient: KeyboardClient {
        get { self[KeyboardClient.self] }
        set { self[KeyboardClient.self] = newValue }
    }
}

public struct KeyboardShortcut: Equatable, Sendable {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    
    public init(key: KeyEquivalent, modifiers: EventModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
    
    public init?(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }
        
        self.key = KeyEquivalent(Character(scalar))
        self.modifiers = EventModifiers(event.modifierFlags)
    }
}

// MARK: - KeyEquivalent Constants

extension KeyEquivalent {
    public static let `return` = KeyEquivalent("\r")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let tab = KeyEquivalent("\u{19}")
    public static let space = KeyEquivalent(" ")
    public static let delete = KeyEquivalent("\u{7F}")
    public static let backspace = KeyEquivalent("\u{08}")
    public static let comma = KeyEquivalent(",")
    
    // Arrow keys
    public static let upArrow = KeyEquivalent(Character(Unicode.Scalar(NSUpArrowFunctionKey)!))
    public static let downArrow = KeyEquivalent(Character(Unicode.Scalar(NSDownArrowFunctionKey)!))
    public static let leftArrow = KeyEquivalent(Character(Unicode.Scalar(NSLeftArrowFunctionKey)!))
    public static let rightArrow = KeyEquivalent(Character(Unicode.Scalar(NSRightArrowFunctionKey)!))
}

// MARK: - KeyboardShortcut Constants

extension KeyboardShortcut {
    // Command shortcuts
    public static let commandReturn = KeyboardShortcut(key: .return, modifiers: .command)
    public static let commandN = KeyboardShortcut(key: "n", modifiers: .command)
    public static let commandK = KeyboardShortcut(key: "k", modifiers: .command)
    public static let commandL = KeyboardShortcut(key: "l", modifiers: .command)
    public static let commandW = KeyboardShortcut(key: "w", modifiers: .command)
    public static let commandSlash = KeyboardShortcut(key: "/", modifiers: .command)
    
    // Standalone keys
    public static let escape = KeyboardShortcut(key: .escape)
    public static let `return` = KeyboardShortcut(key: .return)
    public static let tab = KeyboardShortcut(key: .tab)
    
    // Arrow keys
    public static let upArrow = KeyboardShortcut(key: .upArrow)
    public static let downArrow = KeyboardShortcut(key: .downArrow)
    
    // Command+Shift shortcuts
    public static let commandShiftN = KeyboardShortcut(key: "n", modifiers: [.command, .shift])
}

extension EventModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}
