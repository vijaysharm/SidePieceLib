//
//  TextViewCommand.swift
//  SidePiece
//

import Foundation

public enum TextViewCommand: Equatable {
    case cancel
    case insertNewLine
    case insertTab
    case moveDown
    case moveUp
}

#if os(macOS)
import AppKit

extension TextViewCommand {
    public init?(selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            self = .insertNewLine
        case #selector(NSResponder.insertTab(_:)):
            self = .insertTab
        case #selector(NSResponder.moveDown(_:)):
            self = .moveDown
        case #selector(NSResponder.moveUp(_:)):
            self = .moveUp
        case #selector(NSResponder.cancelOperation(_:)):
            self = .cancel
        default:
            return nil
        }
    }
}
#endif
