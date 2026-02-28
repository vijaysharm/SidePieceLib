//
//  Duration+Extension.swift
//  SidePieceLib
//

import Foundation

extension Duration {
    /***
     * Returns the TimeInterval (seconds) with Double precision
     */
    public var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) * 1e-18)
    }

    /***
     * Returns the duration in milliseconds, rounded to the nearest 64-bit integer
     */
    public var milliseconds: Int64 {
        return components.seconds * 1000 + Int64((Double(components.attoseconds) * 1e-15).rounded(.toNearestOrAwayFromZero))
    }
}
