import Testing
import Foundation
@testable import ReviewKit

// MARK: - ReviewPolicyTests

@Suite("ReviewPolicy")
struct ReviewPolicyTests {

    // MARK: Helpers

    private func makePolicy(
        maxPerYear: Int = 3,
        minDays: Int = 90
    ) -> ReviewPolicy {
        ReviewPolicy(configuration: ReviewConfiguration(
            maximumPromptsPerYear: maxPerYear,
            minimumDaysBetweenPrompts: minDays
        ))
    }

    private func date(daysAgo: Int, from base: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: base)!
    }

    // MARK: Fresh store

    @Test("Eligible with no prior prompts")
    func eligibleWithNoPriorPrompts() {
        let policy = makePolicy()
        var store = MockReviewStore()
        store.promptDates = []

        #expect(policy.isEligible(store: store))
    }

    // MARK: Yearly limit

    @Test("Blocked after reaching yearly limit")
    func blockedAfterYearlyLimit() {
        let policy = makePolicy(maxPerYear: 3, minDays: 0)
        var store = MockReviewStore()
        // Three prompts within the last year
        store.promptDates = [
            date(daysAgo: 10),
            date(daysAgo: 100),
            date(daysAgo: 200)
        ]

        #expect(!policy.isEligible(store: store))
    }

    @Test("Eligible when all previous prompts are older than 365 days")
    func eligibleWhenAllPromptsExpired() {
        let policy = makePolicy(maxPerYear: 3, minDays: 0)
        var store = MockReviewStore()
        store.promptDates = [
            date(daysAgo: 400),
            date(daysAgo: 500),
            date(daysAgo: 600)
        ]

        #expect(policy.isEligible(store: store))
    }

    @Test("Eligible when only old prompts fill the limit (rolling window)")
    func eligibleWhenOnlyOldPromptsFilledLimit() {
        let policy = makePolicy(maxPerYear: 3, minDays: 0)
        var store = MockReviewStore()
        // Two within the last year, one outside — still under cap of 3
        store.promptDates = [
            date(daysAgo: 366),  // outside rolling window
            date(daysAgo: 100),
            date(daysAgo: 200)
        ]

        #expect(policy.isEligible(store: store))
    }

    @Test("maximumPromptsPerYear is clamped to 3")
    func maxPromptsClampedToThree() {
        let config = ReviewConfiguration(maximumPromptsPerYear: 10, minimumDaysBetweenPrompts: 0)
        #expect(config.maximumPromptsPerYear == 3)
    }

    @Test("maximumPromptsPerYear is clamped to 1 minimum")
    func maxPromptsClampedToOne() {
        let config = ReviewConfiguration(maximumPromptsPerYear: 0, minimumDaysBetweenPrompts: 0)
        #expect(config.maximumPromptsPerYear == 1)
    }

    // MARK: Minimum gap

    @Test("Blocked when minimum gap not yet elapsed")
    func blockedWhenGapNotElapsed() {
        let policy = makePolicy(maxPerYear: 3, minDays: 90)
        var store = MockReviewStore()
        store.promptDates = [date(daysAgo: 50)]  // only 50 days ago, need 90

        #expect(!policy.isEligible(store: store))
    }

    @Test("Eligible exactly at minimum gap boundary")
    func eligibleExactlyAtGapBoundary() {
        let policy = makePolicy(maxPerYear: 3, minDays: 90)
        var store = MockReviewStore()
        store.promptDates = [date(daysAgo: 90)]  // exactly 90 days ago

        #expect(policy.isEligible(store: store))
    }

    @Test("Eligible after minimum gap elapsed")
    func eligibleAfterGapElapsed() {
        let policy = makePolicy(maxPerYear: 3, minDays: 90)
        var store = MockReviewStore()
        store.promptDates = [date(daysAgo: 120)]

        #expect(policy.isEligible(store: store))
    }

    @Test("Eligible when minimumDaysBetweenPrompts is zero")
    func eligibleWithZeroGap() {
        let policy = makePolicy(maxPerYear: 3, minDays: 0)
        var store = MockReviewStore()
        store.promptDates = [date(daysAgo: 0)]  // prompted today

        #expect(policy.isEligible(store: store))
    }

    // MARK: Combined conditions

    @Test("Both gap and yearly limit must pass")
    func bothConditionsMustPass() {
        // Gap satisfied (120 days), but yearly limit hit
        let policy = makePolicy(maxPerYear: 1, minDays: 90)
        var store = MockReviewStore()
        store.promptDates = [date(daysAgo: 120)]

        #expect(!policy.isEligible(store: store))
    }
}
