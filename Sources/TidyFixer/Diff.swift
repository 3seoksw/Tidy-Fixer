import Foundation
import SwiftUI

enum DiffKind { case same, added, removed }

struct DiffSegment: Equatable {
    var text: String
    var kind: DiffKind
}

/// Word-level diff. Quote style and whitespace differences are not counted as changes.
enum TextDiff {
    private static let tokenPattern = try! NSRegularExpression(pattern: #"\S+|\s+"#)

    static func tokens(_ s: String) -> [String] {
        tokenPattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        }
    }

    private static func key(_ token: String) -> String {
        if token.first?.isWhitespace == true { return " " }
        return token.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    static func segments(old: String, new: String) -> [DiffSegment] {
        let a = tokens(old)
        let b = tokens(new)
        let diff = b.map(key).difference(from: a.map(key))
        var removed = Set<Int>()
        var added = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var out: [DiffSegment] = []
        var i = 0
        var j = 0
        func push(_ text: String, _ kind: DiffKind) {
            if let last = out.last, last.kind == kind {
                out[out.count - 1].text += text
            } else {
                out.append(DiffSegment(text: text, kind: kind))
            }
        }
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                // Keep spaces between removed words, but never start a removed run with one.
                if a[i].first?.isWhitespace != true || out.last?.kind == .removed {
                    push(a[i].first?.isWhitespace == true ? " " : a[i], .removed)
                }
                i += 1
            } else if j < b.count, added.contains(j) {
                push(b[j], .added)
                j += 1
            } else if j < b.count {
                push(b[j], .same)
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
        var previous = DiffKind.same
        for seg in segments(old: old, new: new) {
            if previous == .removed, seg.kind == .added { result += AttributedString(" ") }
            previous = seg.kind
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
