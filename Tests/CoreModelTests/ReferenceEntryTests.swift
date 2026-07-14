import Foundation
import Testing

import CerebralCore

/// NIC-151: references gain an optional Chrome `profile` (`--profile-directory`).
/// The field must decode backward-compatibly (existing catalogs have no `profile`)
/// and encode without emitting a `profile` key when absent, so shipped and
/// user-minted `apps.json`/`urls.json` round-trip unchanged.

@Test("a reference without a profile decodes to nil")
func decodesAbsentProfileAsNil() throws {
    let json = Data(#"{"id":"docs","label":"Project Docs","target":"https://docs.example"}"#.utf8)
    let entry = try JSONDecoder().decode(ReferenceEntry.self, from: json)
    #expect(entry.profile == nil)
    #expect(entry == ReferenceEntry(id: "docs", label: "Project Docs", target: "https://docs.example"))
}

@Test("a reference with a profile decodes it")
func decodesProfile() throws {
    let json = Data(#"{"id":"work","label":"Work Mail","target":"https://mail.google.com","profile":"Profile 1"}"#.utf8)
    let entry = try JSONDecoder().decode(ReferenceEntry.self, from: json)
    #expect(entry.profile == "Profile 1")
}

@Test("encoding omits the profile key when absent")
func encodeOmitsNilProfile() throws {
    let entry = ReferenceEntry(id: "docs", label: "Project Docs", target: "https://docs.example")
    let data = try JSONEncoder().encode(entry)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("profile"))
}

@Test("encoding includes the profile key when present")
func encodeIncludesProfile() throws {
    let entry = ReferenceEntry(id: "work", label: "Work Mail", target: "https://mail.google.com", profile: "Profile 1")
    let decoded = try JSONDecoder().decode(ReferenceEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded == entry)
    #expect(decoded.profile == "Profile 1")
}
