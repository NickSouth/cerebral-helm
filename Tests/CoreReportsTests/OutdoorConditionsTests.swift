import Foundation
import Testing
@testable import CerebralCore

/// The judgement that moved out of the model.
///
/// Worth testing carefully precisely because it is a threshold someone picked: the numbers are not
/// derived from anything, so the only thing keeping them honest is that changing one breaks a named
/// case here rather than a brief nobody re-reads.

@Test("a clear winter day is unsuitable however bright it is")
func coldIsUnsuitable() {
    // The case this type exists for. Sunny, no rain, and the model suggested a round of golf on it
    // — every signal points outdoors except the only one that matters.
    #expect(
        OutdoorConditions.resolve(highF: 21, temperatureF: 10, precipitationChance: 0) == .unsuitable
    )
    #expect(
        OutdoorConditions.reason(highF: 21, temperatureF: 10, precipitationChance: 0)?
            .contains("cold") == true
    )
}

@Test("a warm dry day is good, and says nothing limits it")
func pleasantIsGood() {
    #expect(
        OutdoorConditions.resolve(highF: 79, temperatureF: 70, precipitationChance: 0) == .good
    )
    // No reason, because there is nothing to explain — a brief that hedges a perfect day is worse
    // than one that says nothing about the weather at all.
    #expect(OutdoorConditions.reason(highF: 79, temperatureF: 70, precipitationChance: 0) == nil)
}

@Test("the forecast high decides, not the reading at the moment it was asked")
func theDayDecidesNotTheMoment() {
    // 07:00 in spring: 44° now, 68° by afternoon. Judging on the current reading would call a
    // perfectly good day marginal and suppress the suggestion that makes the brief worth reading.
    #expect(OutdoorConditions.resolve(highF: 68, temperatureF: 44, precipitationChance: 5) == .good)
    // And with no forecast the current reading is all there is, so it stands in.
    #expect(
        OutdoorConditions.resolve(highF: nil, temperatureF: 34, precipitationChance: nil)
            == .unsuitable
    )
}

@Test("rain rules out a warm day, and a chance of it only qualifies one")
func rainIsWeighedSeparately() {
    #expect(
        OutdoorConditions.resolve(highF: 74, temperatureF: 70, precipitationChance: 80)
            == .unsuitable
    )
    #expect(
        OutdoorConditions.resolve(highF: 74, temperatureF: 70, precipitationChance: 35) == .marginal
    )
    #expect(
        OutdoorConditions.reason(highF: 74, temperatureF: 70, precipitationChance: 35)?
            .contains("rain") == true
    )
}

@Test("a cold bright day is marginal rather than suppressed")
func marginalIsItsOwnAnswer() {
    // Deliberately not folded into `unsuitable`. The season is short where he lives, and a 48°
    // clear Saturday is a real option — the reader decides, the brief only has to be honest that
    // it is not a warm one.
    #expect(OutdoorConditions.resolve(highF: 48, temperatureF: 41, precipitationChance: 0) == .marginal)
}

@Test("heat is treated the same way cold is")
func heatIsUnsuitableToo() {
    // Not a New England problem today, and cheap to be right about rather than discover later.
    #expect(OutdoorConditions.resolve(highF: 99, temperatureF: 96, precipitationChance: 0) == .unsuitable)
    #expect(
        OutdoorConditions.reason(highF: 99, temperatureF: 96, precipitationChance: 0)?
            .contains("hot") == true
    )
}

@Test("the thresholds are the constants, not numbers written twice")
func thresholdsAreNamed() {
    // Guards the shape rather than the value: a threshold that appears once can be tuned by the
    // owner in one edit, and this fails if resolve() stops reading it.
    let justBelow = OutdoorConditions.unsuitableBelowF - 1
    let justAbove = OutdoorConditions.unsuitableBelowF + 1
    #expect(OutdoorConditions.resolve(highF: justBelow, temperatureF: justBelow, precipitationChance: 0) == .unsuitable)
    #expect(OutdoorConditions.resolve(highF: justAbove, temperatureF: justAbove, precipitationChance: 0) != .unsuitable)
}
