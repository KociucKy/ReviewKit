import SwiftUI

// MARK: - ReviewKitEnvironmentKey

private struct ReviewKitKey: EnvironmentKey {
    static let defaultValue: ReviewKit = .shared
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {
    /// The `ReviewKit` instance propagated through the SwiftUI environment.
    ///
    /// Override this when you want a specific subtree of your app to use a custom
    /// `ReviewKit` instance:
    /// ```swift
    /// MyView()
    ///     .environment(\.reviewKit, customKit)
    /// ```
    var reviewKit: ReviewKit {
        get { self[ReviewKitKey.self] }
        set { self[ReviewKitKey.self] = newValue }
    }
}

// MARK: - View modifier

/// A view modifier that increments the session count when the view first appears,
/// making it the single place you need to hook ReviewKit into your SwiftUI app.
private struct ReviewKitModifier: ViewModifier {
    @Environment(\.reviewKit) private var reviewKit

    func body(content: Content) -> some View {
        content.task {
            await reviewKit.incrementSessionCount()
        }
    }
}

// MARK: - View extension

public extension View {

    /// Activates ReviewKit for this view subtree and increments the session count on appearance.
    ///
    /// Attach this modifier **once** near the root of your view hierarchy (e.g. on `ContentView`
    /// or directly inside your `App.body`). It uses `.task` internally so the session increment
    /// is properly lifecycle-managed.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .reviewKitEnabled()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter kit: The `ReviewKit` instance to use. Defaults to ``ReviewKit/shared``.
    func reviewKitEnabled(kit: ReviewKit = .shared) -> some View {
        self
            .environment(\.reviewKit, kit)
            .modifier(ReviewKitModifier())
    }
}

// MARK: - signalReviewEvent modifier

public extension View {

    /// Signals a ``ReviewEvent`` to ReviewKit when the given `trigger` value changes.
    ///
    /// Use this to tie events to user interactions declaratively:
    /// ```swift
    /// TaskRowView(task: task)
    ///     .onReviewEvent("task_completed", trigger: task.isCompleted)
    /// ```
    ///
    /// The event is only signalled when `trigger` changes to `true`.
    ///
    /// - Parameters:
    ///   - eventName: The name of the ``ReviewEvent`` to signal.
    ///   - trigger: A `Bool` value observed for changes. The event fires when this becomes `true`.
    ///   - kit: The `ReviewKit` instance to use. Defaults to the environment value.
    func onReviewEvent(
        _ eventName: String,
        trigger: Bool,
        kit: ReviewKit? = nil
    ) -> some View {
        modifier(ReviewEventModifier(eventName: eventName, trigger: trigger, kit: kit))
    }
}

private struct ReviewEventModifier: ViewModifier {
    @Environment(\.reviewKit) private var envKit
    let eventName: String
    let trigger: Bool
    let kit: ReviewKit?

    private var resolvedKit: ReviewKit { kit ?? envKit }

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { newValue in
            guard newValue else { return }
            let resolvedKit = resolvedKit
            let event = ReviewEvent(eventName)
            Task {
                await resolvedKit.signalEvent(event)
            }
        }
    }
}
