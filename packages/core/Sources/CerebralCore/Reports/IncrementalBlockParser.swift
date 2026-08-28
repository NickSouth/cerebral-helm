import Foundation
import CerebralContracts

/// Reads finished blocks out of a JSON document that is still arriving (NIC-253).
///
/// A model emits `{"blocks":[ … ]}` a few characters at a time. Waiting for the closing brace means
/// nine seconds of nothing; this pulls each array element out the moment it closes, so the reader
/// watches the brief arrive instead of watching a spinner. Nine seconds of silence and nine seconds
/// of visible arrival feel nothing alike.
///
/// **A partial element is never emitted.** The unit is one complete, decodable block: half of
/// `{"blockKind":"line","text":"Your investor ca` is not a shorter block, it is a lie about what the
/// model said. So this counts structure and hands over only closed objects.
///
/// Deliberately a scanner rather than a JSON parser. `JSONDecoder` needs a complete document by
/// construction, and the whole point here is to act before there is one.
public struct IncrementalBlockParser {
    /// Everything seen so far, as characters.
    ///
    /// Characters rather than `String.Index` offsets because appending to a Swift `String` can
    /// invalidate indices held across the append — the scan position would silently rot mid-stream.
    private var characters: [Character] = []
    private var cursor = 0

    /// Whether the `blocks` array has opened. Everything before it — a code fence, a preamble, the
    /// envelope's own braces — is skipped rather than parsed.
    private var insideArray = false
    private var sawBlocksKey = false
    /// Whether the array has closed. Anything after it is not a block.
    private var arrayClosed = false

    /// Object nesting depth relative to the array. An element is complete when this returns to zero.
    private var depth = 0
    private var elementStart: Int?

    // String state has to be tracked because a brace inside a string is not structure: a block whose
    // text is "Ship it {today}" would otherwise close an element early and emit a fragment.
    private var inString = false
    private var escaped = false

    public init() {}

    /// Feeds one delta and returns whatever blocks became complete because of it.
    ///
    /// Returns an empty array most of the time — a delta is usually a few characters in the middle
    /// of a string — and one or more blocks when an element closes.
    public mutating func consume(_ delta: String) -> [Block] {
        characters.append(contentsOf: delta)
        return drain()
    }

    /// Whether the document ended without its blocks array closing.
    ///
    /// The direct evidence of truncation, and better than any heuristic over the text: a stream that
    /// stopped mid-array did not finish, whatever its token count says.
    public var sawArrayClose: Bool { arrayClosed }

    /// Whether anything that looks like a blocks array was ever found. False means the model replied
    /// with something else entirely — prose, an apology, a different shape.
    public var sawBlocksArray: Bool { insideArray || arrayClosed }

    private mutating func drain() -> [Block] {
        var completed: [Block] = []

        while cursor < characters.count {
            let character = characters[cursor]
            defer { cursor += 1 }

            if escaped {
                escaped = false
                continue
            }
            if inString {
                if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    // Checked as the string CLOSES, not as it opens: at the opening quote the key
                    // has not been read yet. Matched on the raw text rather than by parsing,
                    // because at this point there is no document to parse — only a prefix of one.
                    if !insideArray, !sawBlocksKey, isBlocksKey(closingAt: cursor) {
                        sawBlocksKey = true
                    }
                }
                continue
            }
            if character == "\"" {
                inString = true
                continue
            }

            guard insideArray else {
                // The array opens at the first `[` after the key. Anything earlier — a fence, a
                // preamble, the envelope's opening brace — is not it.
                if character == "[", sawBlocksKey { insideArray = true }
                continue
            }
            guard !arrayClosed else { continue }

            switch character {
            case "{":
                if depth == 0 { elementStart = cursor }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let start = elementStart {
                    if let block = decode(from: start, through: cursor) { completed.append(block) }
                    elementStart = nil
                }
            case "]":
                // Only at depth zero: a `]` inside an element belongs to that element's own array.
                if depth == 0 { arrayClosed = true }
            default:
                break
            }
        }

        return completed
    }

    /// Whether the string closing at `index` was the key `blocks`.
    ///
    /// Read backwards over the raw characters, which is enough: this only needs to know which `[` to
    /// treat as the array, and no other key in this document is named `blocks`.
    private func isBlocksKey(closingAt index: Int) -> Bool {
        let key = Array("\"blocks\"")
        guard index >= key.count - 1 else { return false }
        return Array(characters[(index - key.count + 1)...index]) == key
    }

    private func decode(from start: Int, through end: Int) -> Block? {
        let json = String(characters[start...end])
        // A block that will not decode is DROPPED rather than failing the stream: one malformed
        // element must not cost the reader the rest of a brief that is otherwise fine. The buffered
        // validation at the end still judges the document as a whole, so nothing invalid survives to
        // be rendered as final — this only governs what is shown while it is still arriving.
        return try? JSONDecoder().decode(Block.self, from: Data(json.utf8))
    }
}
