import Testing
import Foundation
@testable import ReviewKit

// MARK: - ReviewTriggerTests

@Suite("ReviewTrigger")
struct ReviewTriggerTests {

    // MARK: EventCountTrigger

    @Test("EventCountTrigger does not fire below threshold")
    func eventCountBelowThreshold() {
        let trigger = EventCountTrigger(eventName: "done", threshold: 5)
        var store = MockReviewStore()
        store.eventCounts = ["done": 4]

        #expect(!trigger.shouldRequestReview(after: ReviewEvent("done"), store: store))
    }

    @Test("EventCountTrigger fires at threshold")
    func eventCountAtThreshold() {
        let trigger = EventCountTrigger(eventName: "done", threshold: 5)
        var store = MockReviewStore()
        store.eventCounts = ["done": 5]

        #expect(trigger.shouldRequestReview(after: ReviewEvent("done"), store: store))
    }

    @Test("EventCountTrigger fires above threshold")
    func eventCountAboveThreshold() {
        let trigger = EventCountTrigger(eventName: "done", threshold: 5)
        var store = MockReviewStore()
        store.eventCounts = ["done": 10]

        #expect(trigger.shouldRequestReview(after: ReviewEvent("done"), store: store))
    }

    @Test("EventCountTrigger ignores different event names")
    func eventCountIgnoresDifferentEvent() {
        let trigger = EventCountTrigger(eventName: "done", threshold: 1)
        var store = MockReviewStore()
        store.eventCounts = ["done": 5]

        // Signal a *different* event name
        #expect(!trigger.shouldRequestReview(after: ReviewEvent("other"), store: store))
    }

    @Test("EventCountTrigger ignores nil event")
    func eventCountIgnoresNilEvent() {
        let trigger = EventCountTrigger(eventName: "done", threshold: 1)
        var store = MockReviewStore()
        store.eventCounts = ["done": 5]

        #expect(!trigger.shouldRequestReview(after: nil, store: store))
    }

    // MARK: SessionCountTrigger

    @Test("SessionCountTrigger does not fire below threshold")
    func sessionCountBelowThreshold() {
        let trigger = SessionCountTrigger(threshold: 10)
        var store = MockReviewStore()
        store.sessionCount = 9

        #expect(!trigger.shouldRequestReview(after: nil, store: store))
    }

    @Test("SessionCountTrigger fires at threshold")
    func sessionCountAtThreshold() {
        let trigger = SessionCountTrigger(threshold: 10)
        var store = MockReviewStore()
        store.sessionCount = 10

        #expect(trigger.shouldRequestReview(after: nil, store: store))
    }

    @Test("SessionCountTrigger fires above threshold")
    func sessionCountAboveThreshold() {
        let trigger = SessionCountTrigger(threshold: 10)
        var store = MockReviewStore()
        store.sessionCount = 100

        #expect(trigger.shouldRequestReview(after: nil, store: store))
    }

    // MARK: CompositeTrigger

    @Test("CompositeTrigger returns false when no children fire")
    func compositeNoChildrenFire() {
        let composite = CompositeTrigger([
            EventCountTrigger(eventName: "done", threshold: 5),
            SessionCountTrigger(threshold: 10)
        ])
        var store = MockReviewStore()
        store.eventCounts = ["done": 1]
        store.sessionCount = 2

        #expect(!composite.shouldRequestReview(after: ReviewEvent("done"), store: store))
    }

    @Test("CompositeTrigger fires when first child fires")
    func compositeFirstChildFires() {
        let composite = CompositeTrigger([
            EventCountTrigger(eventName: "done", threshold: 3),
            SessionCountTrigger(threshold: 100)
        ])
        var store = MockReviewStore()
        store.eventCounts = ["done": 3]
        store.sessionCount = 1

        #expect(composite.shouldRequestReview(after: ReviewEvent("done"), store: store))
    }

    @Test("CompositeTrigger fires when second child fires")
    func compositeSecondChildFires() {
        let composite = CompositeTrigger([
            EventCountTrigger(eventName: "done", threshold: 100),
            SessionCountTrigger(threshold: 5)
        ])
        var store = MockReviewStore()
        store.eventCounts = ["done": 1]
        store.sessionCount = 5

        #expect(composite.shouldRequestReview(after: nil, store: store))
    }

    @Test("CompositeTrigger with empty children never fires")
    func compositeEmptyNeverFires() {
        let composite = CompositeTrigger([])
        let store = MockReviewStore()

        #expect(!composite.shouldRequestReview(after: nil, store: store))
    }
}

// MARK: - ReviewKitTests

@Suite("ReviewKit")
struct ReviewKitTests {

    // MARK: signalEvent

    @Test("signalEvent increments the event count in the store")
    func signalEventIncrementsCount() async {
        let store = MockReviewStore()
        let kit = ReviewKit(
            configuration: ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 0),
            store: store
        )

        await kit.signalEvent(ReviewEvent("task_completed"))
        await kit.signalEvent(ReviewEvent("task_completed"))

        let counts = await kit.currentStore.eventCounts
        #expect(counts["task_completed"] == 2)
    }

    @Test("signalEvent accumulates counts for different event names")
    func signalEventDifferentNames() async {
        let store = MockReviewStore()
        let kit = ReviewKit(
            configuration: ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 0),
            store: store
        )

        await kit.signalEvent(ReviewEvent("a"))
        await kit.signalEvent(ReviewEvent("b"))
        await kit.signalEvent(ReviewEvent("a"))

        let counts = await kit.currentStore.eventCounts
        #expect(counts["a"] == 2)
        #expect(counts["b"] == 1)
    }

    // MARK: incrementSessionCount

    @Test("incrementSessionCount increments session count in the store")
    func incrementSessionCount() async {
        let store = MockReviewStore()
        let kit = ReviewKit(
            configuration: ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 0),
            store: store
        )

        await kit.incrementSessionCount()
        await kit.incrementSessionCount()
        await kit.incrementSessionCount()

        let count = await kit.currentStore.sessionCount
        #expect(count == 3)
    }

    // MARK: Trigger registration

    @Test("register adds a trigger that is evaluated on subsequent events")
    func registerTrigger() async {
        let store = MockReviewStore()
        let kit = ReviewKit(
            configuration: ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 0),
            store: store
        )
        await kit.register(EventCountTrigger(eventName: "done", threshold: 2))

        // First signal — count becomes 1, below threshold
        await kit.signalEvent(ReviewEvent("done"))
        // Second signal — count becomes 2, at threshold (prompt would fire if OS allows)
        await kit.signalEvent(ReviewEvent("done"))

        // We can't observe whether the OS showed the UI, but we can verify the store was
        // updated to reflect the prompt attempt (promptDates is appended in recordPrompt).
        // On non-UIKit platforms (test runner is macOS) AppStore.requestReview() is called
        // synchronously, so the prompt date should be recorded.
        let promptCount = await kit.currentStore.promptDates.count
        // 1 prompt recorded (second signal crossed the threshold)
        #expect(promptCount == 1)
    }

    @Test("Policy blocks second prompt within minimum gap")
    func policyBlocksSecondPromptWithinGap() async {
        var preloadedStore = MockReviewStore()
        // Simulate a prompt shown 30 days ago
        preloadedStore.promptDates = [Calendar.current.date(byAdding: .day, value: -30, to: Date())!]

        let kit = ReviewKit(
            configuration: ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 90),
            store: preloadedStore,
            triggers: [EventCountTrigger(eventName: "done", threshold: 1)]
        )

        await kit.signalEvent(ReviewEvent("done"))

        // Prompt should NOT have been recorded (gap not elapsed)
        let promptCount = await kit.currentStore.promptDates.count
        #expect(promptCount == 1)  // still 1 — the pre-existing date, no new one added
    }
}
