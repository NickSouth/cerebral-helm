import Foundation

/// Whether today's weather supports being outside — decided here, not by the model.
///
/// **Why this is not the model's judgement.** Asked in isolation, the composer model answers
/// "is 10°F good golf weather?" correctly five times out of five. Asked to answer it *while*
/// composing a brief, it fails: with an explicit instruction to check the temperature it suggested
/// a round of golf on a 10°F day roughly one time in three, and with that instruction removed it
/// did so three times in three. Reasoning mode gets it right and takes two to three minutes, which
/// is not a dashboard. The knowledge is there; it does not survive the load of the other work.
///
/// So the fact is computed, and the model reads it — the same shape as ``SprintPace``, which is
/// derived host-side for the same reason and has never been wrong. What the model still owns is
/// everything worth having it for: whether to raise it at all, what to suggest instead, how to say
/// it to a person.
///
/// **The thresholds are a judgement, and an owner-tunable one.** They are stated as constants
/// rather than buried in a comparison so that changing "too cold" is an edit to one number with a
/// test attached. They are deliberately about the DAY rather than the moment: at 07:00 the current
/// temperature is the least useful number weather has, so the forecast high decides where one
/// exists and the current reading only stands in for it when the provider gave none.
public enum OutdoorConditions: String, Sendable, Equatable {
    /// Pleasant. Nothing about the weather argues against being outside.
    case good
    /// Doable, but nobody would call it nice. Worth naming rather than suppressing — a short
    /// season makes a cold bright day worth taking, and that is the reader's call, not ours.
    case marginal
    /// Argues against an outdoor plan. A suggestion drawn from `profile` should go indoors.
    case unsuitable

    /// Below this forecast high, outdoors is off the table.
    public static let unsuitableBelowF = 40.0
    /// Below this, outdoors is possible but unpleasant.
    public static let marginalBelowF = 55.0
    /// Above this, heat is doing the same job cold does at the other end.
    public static let unsuitableAboveF = 95.0
    /// At or above this chance of precipitation, an outdoor plan is a bad bet.
    public static let unsuitableRainChance = 60
    /// At or above this, it is a gamble rather than a plan.
    public static let marginalRainChance = 30

    /// Resolves conditions from a reading.
    ///
    /// Temperature and precipitation only — never the `condition` phrase. That string is the
    /// provider's own vocabulary ("Light rain", "Mostly Cloudy", and whatever the next provider
    /// calls them), so matching on it would make this correct for exactly one integration. The two
    /// numbers mean the same thing everywhere.
    public static func resolve(
        highF: Double?,
        temperatureF: Double,
        precipitationChance: Int?
    ) -> OutdoorConditions {
        let degrees = highF ?? temperatureF
        if degrees < unsuitableBelowF || degrees > unsuitableAboveF { return .unsuitable }
        if let chance = precipitationChance, chance >= unsuitableRainChance { return .unsuitable }
        if degrees < marginalBelowF { return .marginal }
        if let chance = precipitationChance, chance >= marginalRainChance { return .marginal }
        return .good
    }

    /// A short phrase naming what limits the day, or `nil` when nothing does.
    ///
    /// Supplied because a bare enum made the model infer the reason and then say it in its own
    /// words; given the phrase it says the useful thing instead ("outdoor conditions are unsuitable
    /// for golf despite the sunshine"). Six tokens for prose that lands.
    public static func reason(
        highF: Double?,
        temperatureF: Double,
        precipitationChance: Int?
    ) -> String? {
        let degrees = highF ?? temperatureF
        if degrees < unsuitableBelowF { return "too cold to be outside for long" }
        if degrees > unsuitableAboveF { return "too hot to be outside for long" }
        if let chance = precipitationChance, chance >= unsuitableRainChance { return "likely wet" }
        if degrees < marginalBelowF { return "cold, though bright enough to be worth it" }
        if let chance = precipitationChance, chance >= marginalRainChance { return "might rain" }
        return nil
    }
}
