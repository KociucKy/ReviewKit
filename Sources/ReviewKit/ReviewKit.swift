import Foundation
import StoreKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - TriggerStatus

/// A human-readable snapshot of a single registered trigger's current state.
public struct TriggerStatus: Sendable {
    /// A short, human-readable description of the trigger (e.g. `"task_completed ≥ 5"`).
    public let label: String
    /// The current value being measured against the threshold (e.g. current event count).
    public let currentValue: Int?
    /// The threshold the trigger must reach to fire.
    public let threshold: Int?
    /// Whether the trigger has already fired (current value ≥ threshold).
    public let isFired: Bool
}

// MARK: - ReviewKitStatus

/// A point-in-time snapshot of ReviewKit's full state, safe to pass across isolation boundaries.
public struct ReviewKitStatus: Sendable {
    // MARK: Configuration
    /// Maximum number of prompts allowed in a rolling 365-day window.
    public let maximumPromptsPerYear: Int
    /// Minimum number of days required between successive prompts.
    public let minimumDaysBetweenPrompts: Int

    // MARK: Prompt history
    /// All dates on which the review prompt was shown (all-time).
    public let promptDates: [Date]
    /// Number of prompts shown in the last 365 days.
    public let promptsThisYear: Int
    /// Remaining prompt budget for the current 365-day window.
    public let promptsRemainingThisYear: Int
    /// The most recent prompt date, if any.
    public let lastPromptDate: Date?
    /// The earliest date a next prompt is policy-allowed based on the minimum gap.
    /// `nil` if no prompt has been shown yet.
    public let nextEligibleDate: Date?

    // MARK: Usage
    /// Total number of app sessions recorded.
    public let sessionCount: Int
    /// All tracked event names and their cumulative counts.
    public let eventCounts: [String: Int]

    // MARK: Eligibility
    /// Whether the policy currently allows a review prompt to be shown.
    public let isCurrentlyEligible: Bool

    // MARK: Triggers
    /// Status of each registered trigger.
    public let triggerStatuses: [TriggerStatus]

    // MARK: Internal init

    init(store: any ReviewStoreProtocol, policy: ReviewPolicy, triggers: [any ReviewTrigger]) {
        let now = Date()
        let config = policy.configuration

        self.maximumPromptsPerYear = config.maximumPromptsPerYear
        self.minimumDaysBetweenPrompts = config.minimumDaysBetweenPrompts
        self.promptDates = store.promptDates
        self.sessionCount = store.sessionCount
        self.eventCounts = store.eventCounts
        self.isCurrentlyEligible = policy.isEligible(store: store, now: now)
        self.lastPromptDate = store.promptDates.max()

        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? now
        let thisYear = store.promptDates.filter { $0 > oneYearAgo }.count
        self.promptsThisYear = thisYear
        self.promptsRemainingThisYear = max(config.maximumPromptsPerYear - thisYear, 0)

        if let last = store.promptDates.max(), config.minimumDaysBetweenPrompts > 0 {
            self.nextEligibleDate = Calendar.current.date(
                byAdding: .day, value: config.minimumDaysBetweenPrompts, to: last
            )
        } else {
            self.nextEligibleDate = nil
        }

        self.triggerStatuses = triggers.map { trigger in
            TriggerStatus(trigger: trigger, store: store)
        }
    }
}

private extension TriggerStatus {
    init(trigger: any ReviewTrigger, store: any ReviewStoreProtocol) {
        if let t = trigger as? EventCountTrigger {
            let count = store.eventCounts[t.eventName] ?? 0
            self.init(
                label: "\(t.eventName) ≥ \(t.threshold)",
                currentValue: count,
                threshold: t.threshold,
                isFired: count >= t.threshold
            )
        } else if let t = trigger as? SessionCountTrigger {
            self.init(
                label: "Sessions ≥ \(t.threshold)",
                currentValue: store.sessionCount,
                threshold: t.threshold,
                isFired: store.sessionCount >= t.threshold
            )
        } else if let t = trigger as? CompositeTrigger {
            let fired = t.shouldRequestReview(after: nil, store: store)
            self.init(label: "CompositeTrigger", currentValue: nil, threshold: nil, isFired: fired)
        } else {
            self.init(label: String(describing: type(of: trigger)), currentValue: nil, threshold: nil, isFired: false)
        }
    }
}

// MARK: - ReviewKit

/// The central coordinator for App Store review prompts.
///
/// `ReviewKit` evaluates configured triggers and Apple's timing policy before requesting
/// a review, ensuring your app never exceeds the OS-enforced cap of 3 prompts per year.
///
/// ## Quick start
///
/// **UIKit / AppKit**
/// ```swift
/// // At app launch (AppDelegate / @main)
/// await ReviewKit.shared.incrementSessionCount()
///
/// // After a meaningful user action
/// await ReviewKit.shared.signalEvent(ReviewEvent("task_completed"))
/// ```
///
/// **SwiftUI** — attach the modifier once near the root of your view hierarchy:
/// ```swift
/// ContentView()
///     .reviewKitEnabled()
/// ```
/// Then signal events the same way from anywhere.
///
/// ## Configuration
/// ```swift
/// let kit = ReviewKit(
///     configuration: ReviewConfiguration(
///         maximumPromptsPerYear: 3,
///         minimumDaysBetweenPrompts: 60
///     ),
///     triggers: [
///         EventCountTrigger(eventName: "task_completed", threshold: 5),
///         SessionCountTrigger(threshold: 10)
///     ]
/// )
/// ```
public actor ReviewKit {

    // MARK: Shared instance

    /// The shared `ReviewKit` instance configured with defaults.
    ///
    /// Replace this with a custom instance early in your app lifecycle if you need
    /// non-default configuration. Because `ReviewKit` is an `actor` (a reference type),
    /// a `let` constant is sufficient — the instance itself is mutable via actor isolation.
    public static let shared = ReviewKit()

    // MARK: Properties

    private let policy: ReviewPolicy
    private var store: any ReviewStoreProtocol
    private var triggers: [any ReviewTrigger]

    // MARK: Init

    /// Creates a `ReviewKit` instance.
    ///
    /// - Parameters:
    ///   - configuration: Timing rules. Defaults to ``ReviewConfiguration/init()``.
    ///   - store: Persistence backend. Defaults to ``UserDefaultsReviewStore/standard``.
    ///   - triggers: Initial set of triggers. More can be added later via ``register(_:)``.
    public init(
        configuration: ReviewConfiguration = ReviewConfiguration(),
        store: some ReviewStoreProtocol = UserDefaultsReviewStore.standard,
        triggers: [any ReviewTrigger] = []
    ) {
        self.policy = ReviewPolicy(configuration: configuration)
        self.store = store
        self.triggers = triggers
    }

    // MARK: Public API

    /// Registers an additional trigger.
    ///
    /// Triggers are evaluated in the order they were registered; the first one that fires
    /// wins. You can register all triggers upfront in the initializer or add them
    /// incrementally as features are unlocked.
    public func register(_ trigger: some ReviewTrigger) {
        triggers.append(trigger)
    }

    /// Records a session start and, if any trigger fires, requests a review.
    ///
    /// Call this once per app launch (e.g. in `application(_:didFinishLaunchingWithOptions:)`
    /// or in a SwiftUI `App.init`).
    public func incrementSessionCount() async {
        store.sessionCount += 1
        await evaluateAndRequestIfNeeded(event: nil)
    }

    /// Records a significant user event and, if any trigger fires, requests a review.
    ///
    /// - Parameter event: The event to record. Its name is used as a key in the store.
    public func signalEvent(_ event: ReviewEvent) async {
        var counts = store.eventCounts
        counts[event.name, default: 0] += 1
        store.eventCounts = counts
        await evaluateAndRequestIfNeeded(event: event)
    }

    /// Requests a review prompt if the current policy permits it, bypassing trigger evaluation.
    ///
    /// Use this when you have already determined that the moment is appropriate and simply
    /// want the policy guard (yearly cap + day gap) to be the final check.
    public func requestReviewIfAppropriate() async {
        await evaluateAndRequestIfNeeded(event: nil, skipTriggers: true)
    }

    // MARK: Debug / status

    /// Returns a snapshot of the current ReviewKit state for display in a debug UI.
    ///
    /// All fields are safe to read from any isolation context once the `async` call returns.
    public func status() -> ReviewKitStatus {
        ReviewKitStatus(store: store, policy: policy, triggers: triggers)
    }

    /// Resets all persisted review data (prompt dates, event counts, session count).
    ///
    /// Intended for use in debug/dev settings screens only. Calling this in production will
    /// cause ReviewKit to behave as if the app was freshly installed.
    public func resetStore() {
        store.promptDates = []
        store.eventCounts = [:]
        store.sessionCount = 0
    }

    // MARK: Internal helpers (accessible from tests via @testable)

    /// Directly accessible for unit testing.
    var currentStore: any ReviewStoreProtocol { store }

    // MARK: Private

    private func evaluateAndRequestIfNeeded(
        event: ReviewEvent?,
        skipTriggers: Bool = false
    ) async {
        guard policy.isEligible(store: store) else { return }

        if !skipTriggers {
            let triggered = triggers.contains {
                $0.shouldRequestReview(after: event, store: store)
            }
            guard triggered else { return }
        }

        // Record the prompt attempt before presenting, so our policy state is updated
        // even if the OS decides to suppress the UI.
        recordPrompt()
        await presentReview()
    }

    @MainActor
    private func presentReview() {
        #if os(iOS) || os(visionOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        AppStore.requestReview(in: scene)
        #elseif os(macOS)
        // On macOS, SKStoreReviewController.requestReview() is the correct no-argument API.
        SKStoreReviewController.requestReview()
        #elseif os(tvOS)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }
        AppStore.requestReview(in: scene)
        #endif
    }

    private func recordPrompt() {
        store.promptDates.append(Date())
    }
}
