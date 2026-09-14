import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper so logging flows can fire haptics without dropping to UIKit
/// call sites throughout the UI. SwiftUI `.sensoryFeedback` is preferred at
/// the view layer; this covers service-level events (workout start/stop).
enum Haptics {
    @MainActor
    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    @MainActor
    static func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    @MainActor
    static func impact() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}
