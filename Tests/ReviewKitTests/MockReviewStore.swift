import Foundation
@testable import ReviewKit

// MARK: - MockReviewStore

/// An in-memory ``ReviewStoreProtocol`` implementation for use in unit tests.
///
/// All values are stored as plain Swift properties — no `UserDefaults` or file I/O involved.
struct MockReviewStore: ReviewStoreProtocol {
    var promptDates: [Date] = []
    var eventCounts: [String: Int] = [:]
    var sessionCount: Int = 0
}
