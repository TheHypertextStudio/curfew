@testable import Curfew
import Testing

/// VoiceOver reads the Sunrise headline without a lone full stop, so a
/// one-word line such as "Morning." is read as a word, not an identifier.
@MainActor
struct SunriseGateHeadlineTests {
    @Test("A headline's final full stop is not spoken")
    func dropsTheFinalFullStop() {
        #expect(SunriseGateView.spokenHeadline("Morning.") == "Morning")
        #expect(SunriseGateView.spokenHeadline("Good morning, Sam.") == "Good morning, Sam")
    }

    @Test("A headline without a full stop is spoken as written")
    func keepsOtherHeadlines() {
        #expect(SunriseGateView.spokenHeadline("Morning") == "Morning")
        #expect(SunriseGateView.spokenHeadline("Ready?") == "Ready?")
    }
}
