import Foundation

// MARK: - ReviewEvent

/// A named event that represents a significant user action within your app.
///
/// Use descriptive names that map to meaningful milestones — for example `"task_completed"`,
/// `"level_cleared"`, or `"photo_exported"`. These names are used as keys in the store, so
/// keep them stable across app versions.
public struct ReviewEvent: Sendable, Hashable {
    /// The name that identifies this event.
    public let name: String

    /// Creates a new event with the given name.
    public init(_ name: String) {
        self.name = name
    }
}

// MARK: - ReviewTrigger

/// Determines whether a review prompt should be requested after a given event and store state.
///
/// Implement this protocol to create custom trigger logic, or use the built-in types:
/// - ``EventCountTrigger``
/// - ``SessionCountTrigger``
/// - ``CompositeTrigger``
public protocol ReviewTrigger: Sendable {
    /// Returns `true` if this trigger considers a review prompt appropriate right now.
    ///
    /// - Parameters:
    ///   - event: The event that was just signalled. May be `nil` when the request comes
    ///     from a manual call rather than a specific event.
    ///   - store: The current persistence state.
    func shouldRequestReview(after event: ReviewEvent?, store: any ReviewStoreProtocol) -> Bool
}

// MARK: - EventCountTrigger

/// Fires after a specific named event has been signalled at least `threshold` times in total.
///
/// Example — prompt after 5 task completions:
/// ```swift
/// EventCountTrigger(eventName: "task_completed", threshold: 5)
/// ```
public struct EventCountTrigger: ReviewTrigger {
    /// The event name this trigger watches.
    public let eventName: String
    /// The minimum cumulative count required to fire.
    public let threshold: Int

    /// Creates a trigger that fires once `eventName` has been signalled `threshold` or more times.
    public init(eventName: String, threshold: Int) {
        self.eventName = eventName
        self.threshold = threshold
    }

    public func shouldRequestReview(after event: ReviewEvent?, store: any ReviewStoreProtocol) -> Bool {
        guard event?.name == eventName else { return false }
        let count = store.eventCounts[eventName] ?? 0
        return count >= threshold
    }
}

// MARK: - SessionCountTrigger

/// Fires after the app has been opened at least `threshold` times.
///
/// Pair this with `ReviewKit.incrementSessionCount()` called at app launch.
///
/// Example — prompt after the 10th launch:
/// ```swift
/// SessionCountTrigger(threshold: 10)
/// ```
public struct SessionCountTrigger: ReviewTrigger {
    /// The minimum cumulative session count required to fire.
    public let threshold: Int

    /// Creates a trigger that fires once the session count reaches `threshold`.
    public init(threshold: Int) {
        self.threshold = threshold
    }

    public func shouldRequestReview(after event: ReviewEvent?, store: any ReviewStoreProtocol) -> Bool {
        return store.sessionCount >= threshold
    }
}

// MARK: - CompositeTrigger

/// Fires when **any** of its child triggers would fire (logical OR).
///
/// Use this to combine multiple strategies, for example triggering on either a high
/// event count or a high session count — whichever comes first.
///
/// ```swift
/// CompositeTrigger([
///     EventCountTrigger(eventName: "task_completed", threshold: 3),
///     SessionCountTrigger(threshold: 10)
/// ])
/// ```
public struct CompositeTrigger: ReviewTrigger {
    private let triggers: [any ReviewTrigger]

    /// Creates a composite trigger from an array of child triggers.
    public init(_ triggers: [any ReviewTrigger]) {
        self.triggers = triggers
    }

    public func shouldRequestReview(after event: ReviewEvent?, store: any ReviewStoreProtocol) -> Bool {
        return triggers.contains { $0.shouldRequestReview(after: event, store: store) }
    }
}
