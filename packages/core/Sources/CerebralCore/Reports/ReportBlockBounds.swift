import Foundation
import CerebralContracts

/// The bounds `report-document.schema.json` states, restated here because `Codable` does not
/// enforce them.
///
/// Decoding a model's JSON into the generated `Block` gives leaf types and enum vocabularies for
/// free — a `count` block emitting `value: 0` where a string is required, measured on 6 of 6 runs
/// of one snapshot, is a decode error rather than a rendered document. What decoding does **not**
/// check is length: `maxItems` and `maxLength` are validation keywords with no Swift counterpart,
/// and they are precisely the ones that matter, because a composition that ran to 123 blocks and
/// 15,655 tokens was schema-legal in every other respect.
///
/// These numbers are a hand-mirror of the schema and would drift silently, so
/// `scripts/contracts-report.test.mjs` parses this file and asserts every constant still matches
/// the schema it claims to mirror. Keep the `public static let <name> = <integer>` shape: that
/// gate reads these lines literally.
public enum ReportBlockBounds {
    // MARK: - Mirrored from packages/contracts/schemas/reports/report-document.schema.json

    public static let blocks = 64
    public static let listItems = 64
    public static let reportActions = 8
    public static let scoreboardSides = 2
    public static let leaderboardRows = 256
    public static let leaderboardPreviewMinimum = 1
    public static let leaderboardPreviewMaximum = 100
    public static let text = 2048
    public static let label = 128
    public static let value = 128
    public static let reportID = 128
    public static let schemaVersion = 16
    public static let actionName = 128
    public static let listItemText = 512
    public static let listItemMeta = 128
    public static let listItemColor = 32
    public static let sideAbbreviation = 64
    public static let sideName = 64
    public static let sideScore = 64
    public static let sideColor = 64
    public static let sideRecord = 64
    public static let rowPosition = 64
    public static let rowName = 64
    public static let rowScore = 64
    public static let rowThru = 64

    // MARK: - Checking

    /// Why a decoded document still fails its contract. Separate from a decode failure because the
    /// two say different things about the model: a decode error means it emitted the wrong *type*,
    /// a bound violation means it emitted too *much*.
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        /// A JSON Pointer into the document, so a message can name the offending place exactly the
        /// way the schema validator downstream would.
        public let path: String
        public let detail: String

        public init(path: String, detail: String) {
            self.path = path
            self.detail = detail
        }

        public var description: String { "\(path) \(detail)" }
    }

    /// Every bound `blocks` violates, in document order. Empty means the blocks are within
    /// contract.
    ///
    /// Reports all of them rather than the first: a retry quotes these back to the model, and one
    /// violation at a time would spend a whole extra completion per fault.
    public static func violations(in blocks: [Block]) -> [Violation] {
        var found: [Violation] = []

        if blocks.count > self.blocks {
            found.append(Violation(
                path: "/blocks",
                detail: "has \(blocks.count) blocks, more than the \(self.blocks) allowed"
            ))
        }

        for (index, block) in blocks.enumerated() {
            let base = "/blocks/\(index)"
            append(&found, at: "\(base)/text", block.text, limit: text)
            append(&found, at: "\(base)/label", block.label, limit: label)
            append(&found, at: "\(base)/value", block.value, limit: value)

            if let items = block.listItems {
                append(&found, at: "\(base)/listItems", items.count, limit: listItems)
                for (itemIndex, item) in items.enumerated() {
                    let itemBase = "\(base)/listItems/\(itemIndex)"
                    append(&found, at: "\(itemBase)/text", item.text, limit: listItemText)
                    append(&found, at: "\(itemBase)/meta", item.meta, limit: listItemMeta)
                    append(&found, at: "\(itemBase)/color", item.color, limit: listItemColor)
                    if item.text.isEmpty {
                        found.append(Violation(path: "\(itemBase)/text", detail: "is empty"))
                    }
                    appendAction(&found, at: "\(itemBase)/reportAction", item.reportAction?.action)
                }
            }

            if let sides = block.scoreboardSides {
                append(&found, at: "\(base)/scoreboardSides", sides.count, limit: scoreboardSides)
                for (sideIndex, side) in sides.enumerated() {
                    let sideBase = "\(base)/scoreboardSides/\(sideIndex)"
                    append(&found, at: "\(sideBase)/sideAbbreviation", side.sideAbbreviation, limit: sideAbbreviation)
                    append(&found, at: "\(sideBase)/sideName", side.sideName, limit: sideName)
                    append(&found, at: "\(sideBase)/sideScore", side.sideScore, limit: sideScore)
                    append(&found, at: "\(sideBase)/sideColor", side.sideColor, limit: sideColor)
                    append(&found, at: "\(sideBase)/sideRecord", side.sideRecord, limit: sideRecord)
                }
            }

            if let rows = block.leaderboardRows {
                append(&found, at: "\(base)/leaderboardRows", rows.count, limit: leaderboardRows)
                for (rowIndex, row) in rows.enumerated() {
                    let rowBase = "\(base)/leaderboardRows/\(rowIndex)"
                    append(&found, at: "\(rowBase)/rowPosition", row.rowPosition, limit: rowPosition)
                    append(&found, at: "\(rowBase)/rowName", row.rowName, limit: rowName)
                    append(&found, at: "\(rowBase)/rowScore", row.rowScore, limit: rowScore)
                    append(&found, at: "\(rowBase)/rowThru", row.rowThru, limit: rowThru)
                }
            }

            if let preview = block.leaderboardPreview,
               preview < leaderboardPreviewMinimum || preview > leaderboardPreviewMaximum {
                found.append(Violation(
                    path: "\(base)/leaderboardPreview",
                    detail: "is \(preview), outside \(leaderboardPreviewMinimum)…\(leaderboardPreviewMaximum)"
                ))
            }

            if let actions = block.reportActions {
                append(&found, at: "\(base)/reportActions", actions.count, limit: reportActions)
                for (actionIndex, action) in actions.enumerated() {
                    appendAction(&found, at: "\(base)/reportActions/\(actionIndex)", action.action)
                }
            }
            appendAction(&found, at: "\(base)/reportAction", block.reportAction?.action)
        }

        return found
    }

    private static func append(_ found: inout [Violation], at path: String, _ value: String?, limit: Int) {
        guard let value, value.count > limit else { return }
        found.append(Violation(path: path, detail: "is \(value.count) characters, over the \(limit) allowed"))
    }

    private static func append(_ found: inout [Violation], at path: String, _ count: Int, limit: Int) {
        guard count > limit else { return }
        found.append(Violation(path: path, detail: "has \(count) entries, more than the \(limit) allowed"))
    }

    /// An action reference names a registered quick action and is never a URL, so its shape is
    /// checked here rather than left to the renderer. A name that does not fit the pattern cannot
    /// resolve to anything and would render as inert text — which is safe, but silently so.
    private static func appendAction(_ found: inout [Violation], at path: String, _ action: String?) {
        guard let action else { return }
        if action.count > actionName {
            found.append(Violation(
                path: "\(path)/action",
                detail: "is \(action.count) characters, over the \(actionName) allowed"
            ))
            return
        }
        // ASCII explicitly, matching the schema's `^[a-z][a-z0-9-]*$`. Swift's `isLowercase` and
        // `isNumber` are Unicode-wide — they accept "é" and "٣" — so using them here would admit a
        // name this check calls valid and the schema validator downstream rejects. A bound that is
        // laxer than the contract it mirrors is worse than no bound: it moves the failure later.
        guard let first = action.first, ("a"..."z").contains(first) else {
            found.append(Violation(path: "\(path)/action", detail: "must start with a lowercase letter"))
            return
        }
        let allowed = action.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        if !allowed {
            found.append(Violation(
                path: "\(path)/action",
                detail: "must be lowercase letters, digits and hyphens"
            ))
        }
    }
}
