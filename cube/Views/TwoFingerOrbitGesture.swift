#if os(iOS)
import SwiftUI
import UIKit

/// A two-finger pan that orbits the cube — unambiguous with one-finger
/// face turns. Bridged from UIKit because SwiftUI drags don't expose
/// touch count.
struct TwoFingerOrbitGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onOrbit: (CGSize) -> Void

    init(isEnabled: Bool, onOrbit: @escaping (CGSize) -> Void) {
        self.isEnabled = isEnabled
        self.onOrbit = onOrbit
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer, context: Context
    ) {
        guard recognizer.state == .changed else { return }
        let translation = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        onOrbit(CGSize(width: translation.x, height: translation.y))
    }
}
#endif
