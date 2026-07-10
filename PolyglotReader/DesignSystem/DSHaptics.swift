import SwiftUI
import UIKit

// MARK: - Semantic Haptic Events
/// One vocabulary for every haptic in the app. Views use the declarative
/// `.dsHaptic(_:trigger:)`; non-View code (PDFKit coordinators, gesture
/// callbacks) uses the imperative `DSHaptics` functions.
///
/// Never attach haptics to high-frequency events (scrolling, typing).
enum DSHapticEvent {
    /// Discrete selection changed (text selection done, highlight color picked).
    case selection
    /// A surface appeared (translation popup materialized).
    case appear
    /// A background task finished softly (translation completed).
    case complete
    /// Operation succeeded (upload finished, quiz correct).
    case success
    case warning
    /// Operation failed (quiz wrong, user-triggered error).
    case error

    var feedback: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .appear: return .impact(weight: .light)
        case .complete: return .impact(flexibility: .soft)
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
}

extension View {
    /// Declarative haptic bound to a state change.
    func dsHaptic(_ event: DSHapticEvent, trigger: some Equatable) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger)
    }

    /// Declarative haptic that fires only for specific transitions
    /// (e.g. appear-only: `{ _, new in new }` on a visibility flag).
    func dsHaptic<T: Equatable>(
        _ event: DSHapticEvent,
        trigger: T,
        condition: @escaping (T, T) -> Bool
    ) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger) { old, new in condition(old, new) }
    }
}

// MARK: - Imperative Escape Hatch
/// For call sites outside SwiftUI's state world. Prefer `.dsHaptic` in views.
@MainActor
enum DSHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func softImpact() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
