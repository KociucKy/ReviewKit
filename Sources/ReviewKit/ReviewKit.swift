import Foundation
import StoreKit

#if canImport(UIKit)
import UIKit
#endif

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
