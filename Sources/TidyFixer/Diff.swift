import Foundation
import SwiftUI

enum DiffKind { case same, added, removed }

struct DiffSegment: Equatable {
    var text: String
    var kind: DiffKind
}

/// Word-level diff. Quote style, whitespace, and invisible characters are not counted as changes.
enum TextDiff {
    /// Drops invisible format characters (U+200B, U+2060, U+FEFF), which copied text often carries.
    static func stripInvisible(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.properties.generalCategory != .format }))
    }

    private static func key(_ word: String) -> String {
        word.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    /// Each word with the whitespace after it, so line breaks survive.
    private static func words(_ s: String) -> [(word: String, space: String)] {
        var result: [(String, String)] = []
        var word = ""
        var space = ""
        for ch in stripInvisible(s) {
            if ch.isWhitespace {
                space.append(ch)
            } else {
                if !space.isEmpty, !word.isEmpty { result.append((word, space)); word = ""; space = "" }
                space = ""
                word.append(ch)
            }
        }
        if !word.isEmpty { result.append((word, space)) }
        return result
    }

    static func segments(old: String, new: String) -> [DiffSegment] {
        let a = words(old)
        let b = words(new)
        let diff = b.map { key($0.word) }.difference(from: a.map { key($0.word) })
        var removed = Set<Int>()
        var added = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var out: [DiffSegment] = []
        func push(_ text: String, _ kind: DiffKind) {
            if let last = out.last, last.kind == kind {
                out[out.count - 1].text += text
            } else {
                out.append(DiffSegment(text: text, kind: kind))
            }
        }
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                push(a[i].word + (a[i].space.contains("\n") ? a[i].space : " "), .removed)
                i += 1
            } else if j < b.count, added.contains(j) {
                push(b[j].word + b[j].space, .added)
                j += 1
            } else if j < b.count {
                push(b[j].word + b[j].space, .same)
                i += 1
                j += 1
            } else {
                i += 1
            }
        }
        return out
    }

    static func attributed(old: String, new: String) -> AttributedString {
        var result = AttributedString()
        for seg in segments(old: old, new: new) {
            var piece = AttributedString(seg.text)
            switch seg.kind {
            case .same: break
            case .added:
                piece.foregroundColor = .green
                piece.backgroundColor = Color.green.opacity(0.18)
            case .removed:
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
                piece.backgroundColor = Color.red.opacity(0.15)
            }
            result += piece
        }
        return result
    }
}
