# ReviewKit

A lightweight, plug-and-play Swift package for requesting App Store reviews — fully compliant with Apple's guidelines and ready for Swift 6.

## Features

- Respects Apple's hard cap of **3 prompts per rolling 365-day period**
- Configurable **minimum gap between prompts** (default: 90 days)
- Composable **trigger system** — fire on event counts, session counts, or any combination
- **SwiftUI-native** — one modifier wires everything up; declarative event signalling via `.onReviewEvent`
- Works with **UIKit and AppKit** too via a single `async` method call
- **Zero external dependencies**
- **Swift 6** strict concurrency — all public types are `Sendable`, state lives in an `actor`
- Supports **iOS 16+, macOS 13+, tvOS 16+, visionOS 1+**

## Apple Guidelines

ReviewKit is designed around Apple's [ratings and reviews guidelines](https://developer.apple.com/app-store/ratings-and-reviews/):

- Prompts are only shown at **natural moments of user satisfaction** (you define what those are via triggers)
- The OS is always in control — Apple may suppress the prompt at any time regardless of your request; ReviewKit never works around this
- The prompt attempt is **always recorded** before calling the OS API, so your own 3/year budget is correctly tracked even if Apple silently suppresses the UI
- The standardized system prompt is used exclusively — no custom UI, no dark patterns

---

## Installation

### Swift Package Manager

Add the dependency in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/ReviewKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["ReviewKit"]
    )
]
```

Or add it in Xcode via **File › Add Package Dependencies** and paste the repository URL.

---

## Quick Start

### SwiftUI

Attach `.reviewKitEnabled()` **once** near the root of your view hierarchy. It automatically increments the session count each time the view appears (i.e. each app launch):

```swift
import ReviewKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .reviewKitEnabled()
        }
    }
}
```

Then register your triggers. The right place is early in your app lifecycle, before any events are signalled:

```swift
// AppDelegate, @main struct init, or a dedicated setup function
await ReviewKit.shared.register(
    EventCountTrigger(eventName: "task_completed", threshold: 5)
)
```

Signal events declaratively in views:

```swift
TaskRowView(task: task)
    .onReviewEvent("task_completed", trigger: task.isCompleted)
```

Or imperatively from anywhere (view model, use case, etc.):

```swift
await ReviewKit.shared.signalEvent(ReviewEvent("task_completed"))
```

### UIKit / AppKit

```swift
// AppDelegate — application(_:didFinishLaunchingWithOptions:)
Task {
    await ReviewKit.shared.register(
        EventCountTrigger(eventName: "export_completed", threshold: 3)
    )
    await ReviewKit.shared.incrementSessionCount()
}

// After a meaningful user action
Task {
    await ReviewKit.shared.signalEvent(ReviewEvent("export_completed"))
}
```

---

## Configuration

`ReviewConfiguration` controls the two timing parameters. Pass it when creating a custom `ReviewKit` instance:

```swift
let kit = ReviewKit(
    configuration: ReviewConfiguration(
        maximumPromptsPerYear: 3,   // clamped to 1...3 — Apple's hard cap
        minimumDaysBetweenPrompts: 60
    ),
    triggers: [
        EventCountTrigger(eventName: "task_completed", threshold: 5)
    ]
)
```

| Parameter | Default | Description |
|---|---|---|
| `maximumPromptsPerYear` | `3` | Max prompts in a rolling 365-day window. Clamped to `1...3`. |
| `minimumDaysBetweenPrompts` | `90` | Days that must pass between successive prompts. |

To use a custom instance throughout your SwiftUI app, pass it to `.reviewKitEnabled()` and it will be propagated via the environment:

```swift
ContentView()
    .reviewKitEnabled(kit: myCustomKit)
```

Or inject it into a specific subtree only:

```swift
SettingsView()
    .environment(\.reviewKit, myCustomKit)
```

---

## Triggers

Triggers answer one question: *"Is right now a good moment to ask for a review?"*

ReviewKit evaluates all registered triggers in registration order. If **any** trigger returns `true` — and the policy conditions are met — the prompt is requested.

### EventCountTrigger

Fires once a named event has been signalled a cumulative number of times:

```swift
// Prompt after 5 completed tasks (across all sessions)
EventCountTrigger(eventName: "task_completed", threshold: 5)

// Prompt after the user has exported 3 times
EventCountTrigger(eventName: "export_completed", threshold: 3)
```

### SessionCountTrigger

Fires once the app has been launched a cumulative number of times:

```swift
// Prompt on the 10th app launch
SessionCountTrigger(threshold: 10)
```

Pair with `ReviewKit.shared.incrementSessionCount()` (or `.reviewKitEnabled()` in SwiftUI, which calls it automatically).

### CompositeTrigger

Fires when **any** child trigger fires (logical OR). Use this to prompt on whichever milestone arrives first:

```swift
CompositeTrigger([
    EventCountTrigger(eventName: "task_completed", threshold: 5),
    SessionCountTrigger(threshold: 10)
])
```

### Custom Triggers

Implement `ReviewTrigger` to express any logic you need:

```swift
struct PurchaseTrigger: ReviewTrigger {
    func shouldRequestReview(after event: ReviewEvent?, store: any ReviewStoreProtocol) -> Bool {
        // Only prompt after in-app purchases, not general events
        return event?.name == "purchase_completed"
    }
}

await ReviewKit.shared.register(PurchaseTrigger())
```

The protocol is `Sendable`, so your implementation must be safe to pass across concurrency boundaries — a plain `struct` with no mutable state is always fine.

---

## Manual Request

If you want full control over timing and only need the yearly-cap / day-gap guardrails, call `requestReviewIfAppropriate()` directly. This bypasses trigger evaluation:

```swift
// Your own logic determines the moment is right
if userJustCompletedOnboarding {
    await ReviewKit.shared.requestReviewIfAppropriate()
}
```

---

## Persistence

State is persisted in `UserDefaults` under keys prefixed with `"ReviewKit."`:

| Key | Stores |
|---|---|
| `ReviewKit.promptDates` | Dates when the prompt was requested |
| `ReviewKit.eventCounts` | Cumulative count per event name |
| `ReviewKit.sessionCount` | Total app launch count |

### Custom Storage

Implement `ReviewStoreProtocol` to use a different backend (e.g. a shared App Group suite, SwiftData, or a remote store):

```swift
struct AppGroupReviewStore: ReviewStoreProtocol {
    private let defaults = UserDefaults(suiteName: "group.com.example.app")!

    var promptDates: [Date] { ... }
    var eventCounts: [String: Int] { ... }
    var sessionCount: Int { ... }
}

let kit = ReviewKit(store: AppGroupReviewStore())
```

---

## Debug Tools

### ReviewKitDebugView

`ReviewKitDebugView` is a SwiftUI view (compiled only in `DEBUG` builds) that displays a live snapshot of ReviewKit's full state: eligibility, prompt history, trigger progress, session count, and event counts. It also includes a **Reset** button that clears all persisted data — useful for testing first-run flows.

```swift
// In your debug/dev settings screen:
NavigationLink("Review Prompt Status") {
    ReviewKitDebugView()
}

// Or with a custom instance:
ReviewKitDebugView(kit: myKit)
```

### status()

Returns a `ReviewKitStatus` snapshot — a `Sendable` struct containing all the same fields shown by `ReviewKitDebugView`. Use this to build your own debug UI or to log ReviewKit's state:

```swift
let status = await ReviewKit.shared.status()
print("Prompts this year: \(status.promptsThisYear) / \(status.maximumPromptsPerYear)")
print("Next eligible: \(String(describing: status.nextEligibleDate))")
```

### resetStore()

Clears all persisted ReviewKit data (prompt dates, event counts, session count). Intended for debug/dev settings screens only:

```swift
await ReviewKit.shared.resetStore()
```

---

## Testing

Use your own in-memory `ReviewStoreProtocol` implementation to write deterministic tests without touching `UserDefaults`:

```swift
import ReviewKit

struct MockReviewStore: ReviewStoreProtocol {
    var promptDates: [Date] = []
    var eventCounts: [String: Int] = [:]
    var sessionCount: Int = 0
}

// In your test:
let store = MockReviewStore()
let kit = ReviewKit(
    configuration: ReviewConfiguration(minimumDaysBetweenPrompts: 0),
    store: store,
    triggers: [EventCountTrigger(eventName: "done", threshold: 1)]
)
await kit.signalEvent(ReviewEvent("done"))
// Assert on store.promptDates.count, etc.
```

---

## Architecture

```
ReviewKit (actor)
├── ReviewConfiguration    — timing parameters
├── ReviewPolicy           — eligibility evaluation (internal)
├── ReviewStoreProtocol    — persistence contract
│   └── UserDefaultsReviewStore  — default implementation
├── ReviewTrigger          — "should prompt now?" contract
│   ├── EventCountTrigger
│   ├── SessionCountTrigger
│   └── CompositeTrigger
├── ReviewKitStatus        — Sendable state snapshot (via status())
├── SwiftUI+ReviewKit      — .reviewKitEnabled(), .onReviewEvent(), \.reviewKit
└── ReviewKitDebugView     — debug UI (DEBUG builds only)
```

All mutable state is confined to the `ReviewKit` actor. Public types are `Sendable`. The `UserDefaultsReviewStore` struct uses an `NSLock` for its `@unchecked Sendable` conformance since `UserDefaults` is not natively `Sendable`.

---

## Requirements

| Platform | Minimum version |
|---|---|
| iOS | 16.0 |
| macOS | 13.0 |
| tvOS | 16.0 |
| visionOS | 1.0 |

- Swift 6.0+
- Xcode 16.0+

---

## License

MIT. See [LICENSE](LICENSE) for details.
