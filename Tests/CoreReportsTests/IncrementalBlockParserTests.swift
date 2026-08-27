import Foundation
import Testing
import CerebralContracts
@testable import CerebralCore

/// NIC-253: pulling finished blocks out of a document that is still arriving.
///
/// Everything here is about **not emitting a fragment**. A delta boundary can fall anywhere — mid
/// string, mid escape, mid number, between a brace and its key — and half a block is not a shorter
/// block, it is a lie about what the model said. So the cases below split the same document in every
/// awkward place and assert the same result.

private func blocks(_ deltas: [String]) -> (blocks: [Block], parser: IncrementalBlockParser) {
    var parser = IncrementalBlockParser()
    var all: [Block] = []
    for delta in deltas { all += parser.consume(delta) }
    return (all, parser)
}

/// Every possible split of `text` into two deltas, so a boundary lands on each character in turn.
private func everySplit(_ text: String) -> [[String]] {
    let characters = Array(text)
    return (0...characters.count).map { at in
        [String(characters[..<at]), String(characters[at...])]
    }
}

private let document = """
{"blocks":[{"blockKind":"line","text":"Your investor call is at 9:30."},\
{"blockKind":"count","value":"3","label":"unread"}]}
"""

// MARK: - Arrival

@Test("a block is emitted the moment it closes, not when the document does")
func blocksArriveAsTheyClose() {
    var parser = IncrementalBlockParser()

    let first = parser.consume("{\"blocks\":[{\"blockKind\":\"line\",\"text\":\"One.\"}")
    #expect(first.count == 1)
    #expect(first.first?.text == "One.")
    // The document is nowhere near finished — that is the whole point.
    #expect(!parser.sawArrayClose)

    let second = parser.consume(",{\"blockKind\":\"line\",\"text\":\"Two.\"}]}")
    #expect(second.count == 1)
    #expect(parser.sawArrayClose)
}

@Test("one character at a time produces exactly the same blocks as one delta")
func characterByCharacterMatchesWholesale() {
    let wholesale = blocks([document]).blocks
    let dribbled = blocks(document.map(String.init)).blocks

    #expect(wholesale.count == 2)
    #expect(dribbled.count == wholesale.count)
    #expect(dribbled.map(\.text) == wholesale.map(\.text))
    #expect(dribbled.map(\.value) == wholesale.map(\.value))
}

@Test("a boundary at every position in the document yields the same two blocks")
func everyBoundaryYieldsTheSameResult() {
    for split in everySplit(document) {
        let result = blocks(split)
        #expect(result.blocks.count == 2, "split at \(split[0].count) produced \(result.blocks.count)")
        #expect(result.parser.sawArrayClose)
    }
}

// MARK: - Structure that only looks like structure

@Test("a brace inside a string does not close an element early")
func bracesInsideStringsAreText() {
    // A block whose text contains `{` or `}` would otherwise emit a fragment the moment the reader
    // wrote one — and "Ship it {today}" is an ordinary thing to write.
    let result = blocks(["{\"blocks\":[{\"blockKind\":\"line\",\"text\":\"Ship it {today} [maybe]\"}]}"])

    #expect(result.blocks.count == 1)
    #expect(result.blocks.first?.text == "Ship it {today} [maybe]")
}

@Test("an escaped quote does not end the string it is inside")
func escapedQuotesAreText() {
    let result = blocks([#"{"blocks":[{"blockKind":"line","text":"She said \"go\" and left"}]}"#])

    #expect(result.blocks.count == 1)
    #expect(result.blocks.first?.text == #"She said "go" and left"#)
}

@Test("a delta boundary falling inside an escape sequence is survived")
func splitInsideAnEscapeIsSurvived() {
    // The nastiest boundary there is: the backslash arrives in one delta and the character it
    // escapes in the next, so a parser that forgot its escape state would treat the quote as the end
    // of the string and lose everything after it.
    let text = #"{"blocks":[{"blockKind":"line","text":"She said \"go\""}]}"#
    for split in everySplit(text) {
        #expect(blocks(split).blocks.count == 1, "split at \(split[0].count) lost the block")
    }
}

@Test("a nested array inside a block does not close the blocks array")
func nestedArraysDoNotCloseTheDocument() {
    // A `list` block carries `listItems`, so `]` at depth one is routine and must not be read as the
    // end of the document.
    let result = blocks(["""
    {"blocks":[{"blockKind":"list","listItems":[{"text":"One"},{"text":"Two"}]},\
    {"blockKind":"line","text":"After."}]}
    """])

    #expect(result.blocks.count == 2)
    #expect(result.blocks.first?.listItems?.count == 2)
    #expect(result.blocks.last?.text == "After.")
}

// MARK: - What is not a block

@Test("a code fence and any preamble are skipped rather than parsed")
func fencesAndPreambleAreSkipped() {
    // A model told to reply with JSON and nothing else still writes a fence sometimes — verified in
    // the eval harness, not assumed.
    let result = blocks(["```json\n{\"blocks\":[{\"blockKind\":\"line\",\"text\":\"One.\"}]}\n```"])

    #expect(result.blocks.count == 1)
}

@Test("a reply with no blocks array emits nothing and says so")
func proseEmitsNothing() {
    // The model answered with something else entirely — prose, an apology, a different shape.
    let result = blocks(["I'm sorry, I can't help with that."])

    #expect(result.blocks.isEmpty)
    #expect(!result.parser.sawBlocksArray)
    #expect(!result.parser.sawArrayClose)
}

@Test("a stream that stops mid-array reports that it never closed")
func truncationIsVisible() {
    // Direct evidence of truncation, and better than any heuristic over the text: a stream that
    // stopped mid-array did not finish, whatever its token count says.
    let result = blocks(["{\"blocks\":[{\"blockKind\":\"line\",\"text\":\"Your calendar is cle"])

    #expect(result.blocks.isEmpty)
    #expect(result.parser.sawBlocksArray)
    #expect(!result.parser.sawArrayClose)
}

@Test("a malformed element is dropped without costing the blocks around it")
func oneBadElementDoesNotStopTheStream() {
    // What is SHOWN while a document arrives degrades to a shorter document; the buffered validation
    // at the end still judges the whole thing, so nothing invalid survives as final.
    let result = blocks(["""
    {"blocks":[{"blockKind":"line","text":"Good."},{"blockKind":"count","value":0},\
    {"blockKind":"line","text":"Also good."}]}
    """])

    #expect(result.blocks.count == 2)
    #expect(result.blocks.map(\.text) == ["Good.", "Also good."])
}

@Test("an empty array closes without emitting anything")
func emptyArrayIsClosedAndEmpty() {
    let result = blocks(["{\"blocks\":[]}"])

    #expect(result.blocks.isEmpty)
    #expect(result.parser.sawArrayClose)
    #expect(result.parser.sawBlocksArray)
}
