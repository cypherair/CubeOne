import CubeKit
import SwiftUI

/// Application state: the logical cube, move history, and the bridge to
/// the 3D scene. The scene renders and animates; every committed move
/// flows back here.
@Observable
final class AppModel {
    let scene = CubeSceneController()

    private(set) var cubeState = CubeState.solved
    private(set) var moveHistory: [Move] = []

    init() {
        scene.onMoveCommitted = { [weak self] move in
            self?.commit(move)
        }
    }

    private func commit(_ move: Move) {
        cubeState.apply(move)
        moveHistory.append(move)
    }

    /// A user drag resolved to a face turn.
    func performUserMove(_ move: Move) {
        scene.enqueue(move)
    }
}
