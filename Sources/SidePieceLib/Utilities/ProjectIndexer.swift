//
//  ProjectIndexer.swift
//  SidePiece
//

import Foundation
import UniformTypeIdentifiers

public actor ProjectIndexer {
    public struct Entry: Sendable, Equatable {
        let id: UUID
        let relative: String
        let modified: Date
        let contentType: UTType
    }
    
    private var entries: [URL: [Entry]] = [:]
    
    public func add(_ entry: Entry, to url: URL) {
        var entries = self.entries[url, default: []]
        entries.append(entry)
        self.entries[url] = entries
    }
    
    public func top(_ count: Int, from url: URL) -> [Entry] {
        guard var entries = entries[url] else { return [] }
        entries.sort(by: { $0.modified > $1.modified })
        return Array(entries.prefix(count))
    }
    
    public func bottom(_ count: Int, from url: URL) -> [Entry] {
        guard var entries = entries[url] else { return [] }
        entries.sort(by: { $0.modified > $1.modified })
        return Array(entries.suffix(count))
    }
    
    public func search(_ term: String, from url: URL, limit: UInt) -> [Entry] {
        guard let entries = entries[url], !term.isEmpty else { return [] }
        
        let lowercasedTerm = term.lowercased()
        let termChars = Array(lowercasedTerm)
        
        var scored: [(entry: Entry, score: Int)] = []
        scored.reserveCapacity(entries.count)
        
        for entry in entries {
            let relative = entry.relative.lowercased()
            let score = Self.fuzzyScore(termChars, in: relative)
            if score > 0 {
                scored.append((entry, score))
            }
        }
        
        scored.sort { $0.score > $1.score }
        
        return Array(scored.prefix(Int(limit)).map(\.entry))
    }
    
    /// Fast fuzzy scoring: subsequence matching with bonuses for consecutive/boundary matches
    private static func fuzzyScore(_ termChars: [Character], in target: String) -> Int {
        let targetChars = Array(target)
        guard !targetChars.isEmpty else { return 0 }
        
        // Quick check: at least one character must exist
        var hasAnyMatch = false
        for char in termChars {
            if targetChars.contains(char) {
                hasAnyMatch = true
                break
            }
        }
        guard hasAnyMatch else { return 0 }
        
        var score = 1 // Base score for any match
        var termIndex = 0
        var consecutive = 0
        var lastMatchIndex = -2
        
        for (i, char) in targetChars.enumerated() {
            guard termIndex < termChars.count else { break }
            
            if char == termChars[termIndex] {
                score += 1
                
                // Consecutive match bonus
                if i == lastMatchIndex + 1 {
                    consecutive += 1
                    score += consecutive * 3
                } else {
                    consecutive = 0
                }
                
                // Start of string bonus
                if i == 0 { score += 15 }
                
                // Word boundary bonus (after / _ - . or space)
                if i > 0 {
                    let prev = targetChars[i - 1]
                    if prev == "/" || prev == "_" || prev == "-" || prev == "." || prev == " " {
                        score += 8
                    }
                }
                
                lastMatchIndex = i
                termIndex += 1
            }
        }
        
        // Full subsequence match bonus
        if termIndex == termChars.count {
            score += 25
            
            // Exact substring bonus (all chars consecutive in target)
            let termString = String(termChars)
            if target.contains(termString) {
                score += 50
                // Prefix match gets extra
                if target.hasPrefix(termString) {
                    score += 30
                }
            }
        }
        
        return score
    }
}
