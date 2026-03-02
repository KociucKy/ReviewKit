import Foundation

// MARK: - ReviewStoreProtocol

/// Defines the persistence contract used by ReviewKit to track prompt history and event counts.
///
/// Conform to this protocol to provide a custom storage backend (e.g. SwiftData, a database,
/// or an in-memory mock for testing). The default implementation uses `UserDefaults`.
public protocol ReviewStoreProtocol: Sendable {

    /// Dates on which the review prompt was actually shown to the user.
    var promptDates: [Date] { get set }

    /// Counts of named significant events signalled via `ReviewKit.signalEvent(_:)`.
    var eventCounts: [String: Int] { get set }

    /// Total number of app sessions recorded via `ReviewKit.incrementSessionCount()`.
    var sessionCount: Int { get set }
}

// MARK: - UserDefaultsReviewStore

/// A `ReviewStoreProtocol` implementation backed by `UserDefaults`.
///
/// All values are stored under keys prefixed with `"ReviewKit."`.
/// Thread-safety is provided by an `NSLock` so the struct can be passed across isolation
/// boundaries as `@unchecked Sendable`.
public struct UserDefaultsReviewStore: ReviewStoreProtocol, @unchecked Sendable {

    // MARK: Keys

    private enum Key {
        static let promptDates = "ReviewKit.promptDates"
        static let eventCounts = "ReviewKit.eventCounts"
        static let sessionCount = "ReviewKit.sessionCount"
    }

    // MARK: Properties

    private let defaults: UserDefaults
    private let lock = NSLock()

    // MARK: Init

    /// Creates a store backed by the given `UserDefaults` suite.
    ///
    /// - Parameter defaults: The `UserDefaults` instance to use. Defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A shared store backed by `UserDefaults.standard`.
    public static let standard = UserDefaultsReviewStore()

    // MARK: ReviewStoreProtocol

    public var promptDates: [Date] {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard let data = defaults.data(forKey: Key.promptDates),
                  let dates = try? JSONDecoder().decode([Date].self, from: data) else {
                return []
            }
            return dates
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.promptDates)
        }
    }

    public var eventCounts: [String: Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard let data = defaults.data(forKey: Key.eventCounts),
                  let counts = try? JSONDecoder().decode([String: Int].self, from: data) else {
                return [:]
            }
            return counts
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.eventCounts)
        }
    }

    public var sessionCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.integer(forKey: Key.sessionCount)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Key.sessionCount)
        }
    }
}
