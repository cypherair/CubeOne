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

    var canUndo: Bool { historyCursor > 0 && scene.isIdle && solveSession == nil }
    var canRedo: Bool { historyCursor < history.count && scene.isIdle && solveSession == nil }
    var canScramble: Bool { solver != nil && scene.isIdle && solveSession == nil }
    var canReset: Bool { scene.isIdle && cubeState != .solved && solveSession == nil }
    var canSolve: Bool {
        solver != nil && scene.isIdle && !cubeState.isSolved
            && solveSession == nil && !isComputingSolution
    }

    // MARK: Solve session

    /// An active guided solution being played back on the cube.
    struct SolveSession {
        let solution: [Move]
        var nextIndex = 0
        var isPlaying = false
        var isFinished: Bool { nextIndex >= solution.count }
    }

    private(set) var solveSession: SolveSession?
    private(set) var isComputingSolution = false

    func startSolve() {
        guard canSolve, let solver else { return }
        isComputingSolution = true
        let state = cubeState
        Task.detached(priority: .userInitiated) {
            let solution = solver.solve(state, timeBudget: .milliseconds(300))
            await MainActor.run { [weak self] in
                self?.beginSolveSession(solution)
            }
        }
    }

    private func beginSolveSession(_ solution: [Move]?) {
        isComputingSolution = false
        guard let solution, !solution.isEmpty, scene.isIdle else { return }
        // The guided solution takes over: previous undo history no longer
        // applies to where the cube is heading.
        history.removeAll()
        historyCursor = 0
        userMoveCount = 0
        solveSession = SolveSession(solution: solution)
        scene.allowsDirectTurns = false
    }

    func endSolveSession() {
        solveSession = nil
        scene.allowsDirectTurns = true
    }

    func solveTogglePlay() {
        guard var session = solveSession, !session.isFinished else { return }
        session.isPlaying.toggle()
        solveSession = session
        if session.isPlaying { advanceSolution() }
    }

    func solveStepForward() {
        guard var session = solveSession else { return }
        session.isPlaying = false
        solveSession = session
        advanceSolution()
    }

    func solveStepBackward() {
        guard var session = solveSession, session.nextIndex > 0, scene.isIdle else { return }
        session.isPlaying = false
        solveSession = session
        enqueue(session.solution[session.nextIndex - 1].inverse, intent: .solutionBack)
    }

    private func advanceSolution() {
        guard let session = solveSession, !session.isFinished, scene.isIdle else { return }
        enqueue(
            session.solution[session.nextIndex], intent: .solutionForward,
            duration: session.isPlaying ? 0.34 : 0.22
        )
    }

    /// Why a queued move is happening — decides how the commit updates
    /// history. Parallel FIFO to the scene's animation queue.
    private enum MoveIntent {
        case user, undo, redo, scramble, solutionForward, solutionBack
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
        case .solutionForward:
            solveSession?.nextIndex += 1
            if let session = solveSession {
                if session.isFinished {
                    solveSession?.isPlaying = false
                } else if session.isPlaying {
                    advanceSolution()
                }
            }
        case .solutionBack:
            solveSession?.nextIndex -= 1
        }
    }

    private func enqueue(_ move: Move, intent: MoveIntent, duration: TimeInterval = 0.22) {
        pendingIntents.append(intent)
        scene.enqueue(move, duration: duration)
    }
}
