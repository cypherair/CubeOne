import CubeKit
import Foundation
import SwiftUI

/// Application state: the logical cube, move history with undo/redo, the
/// solver, and the bridge to the 3D scene. The scene renders and
/// animates; every committed move flows back here tagged with the intent
/// that caused it.
@Observable
final class AppModel {
    enum SolverStatus {
        case preparing
        case ready(KociembaSolver)
        case failed
    }

    let scene = CubeSceneController()

    private(set) var cubeState = CubeState.solved
    private(set) var solverStatus = SolverStatus.preparing

    /// Moves the user has performed since the last scramble/reset;
    /// `historyCursor` counts how many are currently applied (undo moves
    /// it back, redo forward).
    private(set) var history: [Move] = []
    private(set) var historyCursor = 0
    private(set) var userMoveCount = 0

    var solver: KociembaSolver? {
        if case .ready(let solver) = solverStatus { return solver }
        return nil
    }

    var canUndo: Bool { historyCursor > 0 && scene.isIdle }
    var canRedo: Bool { historyCursor < history.count && scene.isIdle }
    var canScramble: Bool { solver != nil && scene.isIdle }
    var canReset: Bool { scene.isIdle && cubeState != .solved }

    /// Why a queued move is happening — decides how the commit updates
    /// history. Parallel FIFO to the scene's animation queue.
    private enum MoveIntent {
        case user, undo, redo, scramble
    }
    private var pendingIntents: [MoveIntent] = []

    static let supportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CubeOne", isDirectory: true)

    init() {
        scene.onMoveCommitted = { [weak self] move in
            self?.commit(move)
        }
        let directory = Self.supportDirectory
        Task.detached(priority: .userInitiated) {
            let status: SolverStatus
            do {
                let tables = try SolverTables.cached(in: directory)
                status = .ready(KociembaSolver(tables: tables))
            } catch {
                print("Solver tables unavailable: \(error)")
                status = .failed
            }
            await MainActor.run { [weak self] in
                self?.solverStatus = status
            }
        }
    }

    // MARK: Actions

    /// A user drag resolved to a face turn.
    func performUserMove(_ move: Move) {
        enqueue(move, intent: .user)
    }

    func undo() {
        guard canUndo else { return }
        enqueue(history[historyCursor - 1].inverse, intent: .undo)
    }

    func redo() {
        guard canRedo else { return }
        enqueue(history[historyCursor], intent: .redo)
    }

    /// Resets to solved, then animates a WCA-style random-state scramble.
    func scramble() {
        guard canScramble, let solver else { return }
        let target = Scrambler.randomState()
        Task.detached(priority: .userInitiated) {
            guard let sequence = Scrambler.scrambleSequence(to: target, using: solver) else {
                return
            }
            await MainActor.run { [weak self] in
                self?.beginScramble(sequence)
            }
        }
    }

    private func beginScramble(_ sequence: [Move]) {
        guard scene.isIdle else { return }
        resetToSolvedInstantly()
        pendingIntents.append(contentsOf: sequence.map { _ in MoveIntent.scramble })
        scene.enqueue(sequence, duration: 0.09)
    }

    func reset() {
        guard scene.isIdle else { return }
        resetToSolvedInstantly()
    }

    private func resetToSolvedInstantly() {
        cubeState = .solved
        history.removeAll()
        historyCursor = 0
        userMoveCount = 0
        pendingIntents.removeAll()
        scene.rebase(to: FaceletCube.solved)
    }

    // MARK: Commits from the scene

    private func commit(_ move: Move) {
        cubeState.apply(move)
        let intent = pendingIntents.isEmpty ? .user : pendingIntents.removeFirst()
        switch intent {
        case .user:
            if historyCursor < history.count {
                history.removeSubrange(historyCursor...)
            }
            history.append(move)
            historyCursor += 1
            userMoveCount += 1
        case .undo:
            historyCursor -= 1
            userMoveCount = max(0, userMoveCount - 1)
        case .redo:
            historyCursor += 1
            userMoveCount += 1
        case .scramble:
            break
        }
    }

    private func enqueue(_ move: Move, intent: MoveIntent) {
        pendingIntents.append(intent)
        scene.enqueue(move)
    }
}
