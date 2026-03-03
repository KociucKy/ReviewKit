#if DEBUG
import SwiftUI

// MARK: - ReviewKitDebugView

/// A SwiftUI view that displays a full summary of the current ReviewKit state.
///
/// Drop this into your dev/debug settings screen to inspect prompt eligibility,
/// history, triggers, and event counts at a glance. It also offers a **Reset**
/// action that clears all persisted ReviewKit data — useful for testing first-run flows.
///
/// ```swift
/// // In your DevSettingsView:
/// NavigationLink("Review Prompt Status") {
///     ReviewKitDebugView()
/// }
/// // Or with a custom instance:
/// ReviewKitDebugView(kit: myKit)
/// ```
///
/// - Note: This view is only compiled in `DEBUG` builds.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
public struct ReviewKitDebugView: View {

    // MARK: Properties

    private let kit: ReviewKit
    @State private var status: ReviewKitStatus?
    @State private var showResetConfirmation = false

    // MARK: Init

    /// Creates the debug view for the given `ReviewKit` instance.
    ///
    /// - Parameter kit: The instance to inspect. Defaults to ``ReviewKit/shared``.
    public init(kit: ReviewKit = .shared) {
        self.kit = kit
    }

    // MARK: Body

    public var body: some View {
        Group {
            if let status {
                List {
                    eligibilitySection(status)
                    promptHistorySection(status)
                    usageSection(status)
                    triggersSection(status)
                    eventsSection(status)
                    resetSection
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Review Prompt Status")
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refresh() }
        .refreshable { await refresh() }
        .confirmationDialog(
            "Reset all ReviewKit data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task {
                    await kit.resetStore()
                    await refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears prompt history, event counts and session count. The effect is immediate.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func eligibilitySection(_ s: ReviewKitStatus) -> some View {
        Section("Policy") {
            LabeledRow(label: "Eligible now") {
                EligibilityBadge(isEligible: s.isCurrentlyEligible)
            }
            LabeledRow(label: "Prompts this year") {
                Text("\(s.promptsThisYear) / \(s.maximumPromptsPerYear)")
                    .monospacedDigit()
            }
            LabeledRow(label: "Remaining this year") {
                Text("\(s.promptsRemainingThisYear)")
                    .monospacedDigit()
                    .foregroundStyle(s.promptsRemainingThisYear == 0 ? .red : .primary)
            }
            LabeledRow(label: "Min. gap (days)") {
                Text("\(s.minimumDaysBetweenPrompts)")
                    .monospacedDigit()
            }
            if let next = s.nextEligibleDate {
                LabeledRow(label: "Next eligible") {
                    VStack(alignment: .trailing) {
                        Text(next, style: .date)
                        if next > Date() {
                            Text(next, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Now")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } else {
                LabeledRow(label: "Next eligible") {
                    Text("Anytime (no prior prompt)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func promptHistorySection(_ s: ReviewKitStatus) -> some View {
        Section("Prompt History (\(s.promptDates.count) total)") {
            if s.promptDates.isEmpty {
                Text("No prompts shown yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(s.promptDates.sorted(by: >), id: \.self) { date in
                    HStack {
                        Text(date, style: .date)
                        Spacer()
                        Text(date, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func usageSection(_ s: ReviewKitStatus) -> some View {
        Section("Usage") {
            LabeledRow(label: "Session count") {
                Text("\(s.sessionCount)")
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func triggersSection(_ s: ReviewKitStatus) -> some View {
        Section("Triggers (\(s.triggerStatuses.count))") {
            if s.triggerStatuses.isEmpty {
                Text("No triggers registered")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(s.triggerStatuses.enumerated()), id: \.offset) { _, trigger in
                    TriggerRow(status: trigger)
                }
            }
        }
    }

    @ViewBuilder
    private func eventsSection(_ s: ReviewKitStatus) -> some View {
        Section("Event Counts (\(s.eventCounts.count))") {
            if s.eventCounts.isEmpty {
                Text("No events recorded yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(s.eventCounts.sorted(by: { $0.key < $1.key }), id: \.key) { name, count in
                    LabeledRow(label: name) {
                        Text("\(count)")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset All Data", systemImage: "trash")
            }
        } footer: {
            Text("Clears prompt dates, event counts and session count from storage. Use for testing only.")
        }
    }

    // MARK: Helpers

    private func refresh() async {
        status = await kit.status()
    }

    // MARK: Preview helpers

    /// Initialiser used exclusively by previews to inject a pre-built status snapshot,
    /// bypassing the async `kit.status()` call so the preview renders immediately.
    fileprivate init(previewStatus: ReviewKitStatus) {
        self.kit = .shared
        self._status = State(initialValue: previewStatus)
    }
}

// MARK: - Supporting views

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
private struct LabeledRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            trailing()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
private struct EligibilityBadge: View {
    let isEligible: Bool

    var body: some View {
        Text(isEligible ? "Yes" : "No")
            .font(.callout.bold())
            .foregroundStyle(isEligible ? .green : .red)
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
private struct TriggerRow: View {
    let status: TriggerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.label)
                    .font(.callout)
                Spacer()
                firedBadge
            }
            if let current = status.currentValue, let threshold = status.threshold {
                ProgressView(value: Double(min(current, threshold)), total: Double(threshold))
                    .tint(status.isFired ? .green : .accentColor)
                Text("\(current) / \(threshold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var firedBadge: some View {
        if status.isFired {
            Text("Fired")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green, in: Capsule())
        } else {
            Text("Waiting")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
private struct PreviewStore: ReviewStoreProtocol {
    var promptDates: [Date]
    var eventCounts: [String: Int]
    var sessionCount: Int
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
#Preview("Rich data") {
    let store = PreviewStore(
        promptDates: [
            Date().addingTimeInterval(-200 * 86400),
            Date().addingTimeInterval(-95 * 86400)
        ],
        eventCounts: [
            "task_completed": 4,
            "photo_exported": 12,
            "level_cleared": 1
        ],
        sessionCount: 47
    )
    let config = ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 90)
    let policy = ReviewPolicy(configuration: config)
    let triggers: [any ReviewTrigger] = [
        EventCountTrigger(eventName: "task_completed", threshold: 5),
        EventCountTrigger(eventName: "photo_exported", threshold: 10),
        SessionCountTrigger(threshold: 30)
    ]
    let status = ReviewKitStatus(store: store, policy: policy, triggers: triggers)
    return NavigationStack {
        ReviewKitDebugView(previewStatus: status)
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
#Preview("Fresh install") {
    let store = PreviewStore(promptDates: [], eventCounts: [:], sessionCount: 0)
    let config = ReviewConfiguration()
    let policy = ReviewPolicy(configuration: config)
    let triggers: [any ReviewTrigger] = [
        SessionCountTrigger(threshold: 10)
    ]
    let status = ReviewKitStatus(store: store, policy: policy, triggers: triggers)
    return NavigationStack {
        ReviewKitDebugView(previewStatus: status)
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, visionOS 1.0, *)
#Preview("Yearly limit reached") {
    let now = Date()
    let store = PreviewStore(
        promptDates: [
            now.addingTimeInterval(-10 * 86400),
            now.addingTimeInterval(-120 * 86400),
            now.addingTimeInterval(-240 * 86400)
        ],
        eventCounts: ["task_completed": 20],
        sessionCount: 80
    )
    let config = ReviewConfiguration(maximumPromptsPerYear: 3, minimumDaysBetweenPrompts: 90)
    let policy = ReviewPolicy(configuration: config)
    let triggers: [any ReviewTrigger] = [
        EventCountTrigger(eventName: "task_completed", threshold: 5)
    ]
    let status = ReviewKitStatus(store: store, policy: policy, triggers: triggers)
    return NavigationStack {
        ReviewKitDebugView(previewStatus: status)
    }
}
#endif
