#if os(iOS)
import SwiftUI
import UIKit

/// Allows the two-finger pan and pinch to recognize together (and
/// alongside SwiftUI's gestures) so rotating and zooming coexist.
final class SimultaneousGestureCoordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

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

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousGestureCoordinator {
        SimultaneousGestureCoordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.delegate = context.coordinator
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

/// Pinch-to-zoom bridged through UIKit so it can co-recognize with the
/// two-finger orbit pan (a SwiftUI MagnifyGesture refuses to share
/// two-finger touches with a UIKit recognizer).
struct TwoFingerZoomGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    /// (magnification, ended)
    let onZoom: (CGFloat, Bool) -> Void

    init(isEnabled: Bool, onZoom: @escaping (CGFloat, Bool) -> Void) {
        self.isEnabled = isEnabled
        self.onZoom = onZoom
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> SimultaneousGestureCoordinator {
        SimultaneousGestureCoordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPinchGestureRecognizer, context: Context
    ) {
        switch recognizer.state {
        case .changed:
            onZoom(recognizer.scale, false)
        case .ended, .cancelled:
            onZoom(recognizer.scale, true)
        default:
            break
        }
    }
}
#endif
