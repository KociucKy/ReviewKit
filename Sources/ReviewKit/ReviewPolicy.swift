import Foundation

// MARK: - ReviewConfiguration

/// Controls the timing rules that govern when a review prompt may be shown.
///
/// The defaults are deliberately conservative and comply with Apple's guidelines
/// (max 3 prompts per 365-day rolling window, with a meaningful gap between them).
///
/// ```swift
/// var config = ReviewConfiguration()
/// config.minimumDaysBetweenPrompts = 60
/// let kit = ReviewKit(configuration: config)
/// ```
public struct ReviewConfiguration: Sendable {

    /// Maximum number of times the prompt may be shown in any rolling 365-day period.
    ///
    /// Apple enforces a hard cap of 3, so values above 3 are silently clamped to 3.
    /// Defaults to `3`.
    public var maximumPromptsPerYear: Int

    /// Minimum number of days that must elapse between successive prompts.
    ///
    /// Setting a higher value makes the prompts feel less intrusive. Defaults to `90` days
    /// (roughly once per quarter, which fills the Apple cap over a year).
    public var minimumDaysBetweenPrompts: Int

    /// Creates a configuration with the given timing parameters.
    ///
    /// - Parameters:
    ///   - maximumPromptsPerYear: Hard cap per 365-day window. Clamped to `1...3`. Defaults to `3`.
    ///   - minimumDaysBetweenPrompts: Minimum gap between prompts in days. Defaults to `90`.
    public init(
        maximumPromptsPerYear: Int = 3,
        minimumDaysBetweenPrompts: Int = 90
    ) {
        self.maximumPromptsPerYear = min(max(maximumPromptsPerYear, 1), 3)
        self.minimumDaysBetweenPrompts = max(minimumDaysBetweenPrompts, 0)
    }
}

// MARK: - ReviewPolicy

/// Encapsulates the eligibility logic that decides whether a review prompt may be shown.
///
/// This type is internal; consumers interact with it via ``ReviewKit``.
struct ReviewPolicy: Sendable {

    public let configuration: ReviewConfiguration

    // MARK: Eligibility

    /// Returns `true` if all policy conditions are satisfied for showing a prompt.
    ///
    /// Conditions (all must pass):
    /// 1. Fewer than `maximumPromptsPerYear` prompts have been shown in the last 365 days.
    /// 2. At least `minimumDaysBetweenPrompts` days have elapsed since the last prompt.
    func isEligible(store: any ReviewStoreProtocol, now: Date = Date()) -> Bool {
        return withinYearlyLimit(store: store, now: now)
            && respectsMinimumGap(store: store, now: now)
    }

    // MARK: Private helpers

    /// Checks the rolling 365-day prompt count against `maximumPromptsPerYear`.
    private func withinYearlyLimit(store: any ReviewStoreProtocol, now: Date) -> Bool {
        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? now
        let recentCount = store.promptDates.filter { $0 > oneYearAgo }.count
        return recentCount < configuration.maximumPromptsPerYear
    }

    /// Checks that enough days have passed since the most recent prompt.
    private func respectsMinimumGap(store: any ReviewStoreProtocol, now: Date) -> Bool {
        guard configuration.minimumDaysBetweenPrompts > 0,
              let lastDate = store.promptDates.max() else {
            return true  // no prompts yet — gap is satisfied
        }
        let daysSinceLast = Calendar.current.dateComponents(
            [.day], from: lastDate, to: now
        ).day ?? 0
        return daysSinceLast >= configuration.minimumDaysBetweenPrompts
    }
}
