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
    /// Every committed turn, for sound/haptic triggers.
    private(set) var committedMoveCount = 0
    private let click = ClickSound()

    var solver: KociembaSolver? {
        if case .ready(let solver) = solverStatus { return solver }
        return nil
    }

    /// No session is active and the scene is settled.
    private var isFreePlay: Bool {
        scene.isIdle && solveSession == nil && editor == nil && timerSession == nil
    }

    var canUndo: Bool { historyCursor > 0 && isFreePlay }
    var canRedo: Bool { historyCursor < history.count && isFreePlay }
    var canScramble: Bool { solver != nil && isFreePlay }
    var canReset: Bool { cubeState != .solved && isFreePlay }
    var canSolve: Bool {
        solver != nil && !cubeState.isSolved && isFreePlay && !isComputingSolution
    }
    var canEdit: Bool { isFreePlay }
    var canStartTimer: Bool { solver != nil && isFreePlay }

    // MARK: Timer session

    /// A timed solve: scramble plays, the clock starts on the user's
    /// first turn, and stops automatically when the cube is solved.
    struct TimerSession {
        enum Phase {
            case scrambling
            case ready
            case running(Date)
            case finished(TimeInterval, isBest: Bool)
        }
        var phase: Phase = .scrambling
        var moveCount = 0
    }

    private(set) var timerSession: TimerSession?
    let stats: StatsStore

    func startTimerMode() {
        guard canStartTimer, let solver else { return }
        timerSession = TimerSession()
        runScramble(using: solver)
    }

    func exitTimerMode() {
        timerSession = nil
    }

    // MARK: Editor session

    /// Sticker-painting mode: a working facelet copy with live validation.
    struct EditorSession {
        var facelets: FaceletCube
        var selectedColor: Face = .up
        var error: CubeValidationError?
        var isValid: Bool { error == nil }
    }

    private(set) var editor: EditorSession?

    func beginEditing() {
        guard canEdit else { return }
        editor = EditorSession(facelets: cubeState.facelets)
        scene.allowsDirectTurns = false
        // Reset transforms so every sticker entity sits at its home
        // facelet position and painting maps one-to-one.
        scene.rebase(to: cubeState.facelets)
    }

    func cancelEditing() {
        guard editor != nil else { return }
        editor = nil
        scene.allowsDirectTurns = true
        scene.rebase(to: cubeState.facelets)
    }

    func applyEditing() {
        guard let session = editor,
              let state = try? session.facelets.validatedState() else { return }
        cubeState = state
        history.removeAll()
        historyCursor = 0
        userMoveCount = 0
        pendingIntents.removeAll()
        editor = nil
        scene.allowsDirectTurns = true
        // The scene already shows the edited stickers at home transforms.
        persistState()
    }

    func editorSelectColor(_ face: Face) {
        editor?.selectedColor = face
    }

    /// Repaints the whole working copy (e.g. back to solved).
    func editorReplaceAll(with facelets: FaceletCube) {
        guard var session = editor else { return }
        session.facelets = facelets
        session.error = Self.validationError(of: facelets)
        editor = session
        scene.rebase(to: facelets)
    }

    func paintSticker(at index: Int) {
        guard var session = editor, !FaceletCube.isCenter(index) else { return }
        session.facelets.stickers[index] = session.selectedColor
        session.error = Self.validationError(of: session.facelets)
        editor = session
        scene.paintSticker(at: index, with: session.selectedColor)
    }

    private static func validationError(of facelets: FaceletCube) -> CubeValidationError? {
        do {
            _ = try facelets.validatedState()
            return nil
        } catch {
            return error
        }
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
        stats = StatsStore()
        scene.onMoveCommitted = { [weak self] move in
            self?.commit(move)
        }
        restoreSavedState()
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
        runScramble(using: solver)
    }

    private func runScramble(using solver: KociembaSolver) {
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
        persistState()
    }

    // MARK: Commits from the scene

    private func commit(_ move: Move) {
        cubeState.apply(move)
        committedMoveCount += 1
        click.play()
        persistState()
        let intent = pendingIntents.isEmpty ? .user : pendingIntents.removeFirst()
        switch intent {
        case .user:
            if historyCursor < history.count {
                history.removeSubrange(historyCursor...)
            }
            history.append(move)
            historyCursor += 1
            userMoveCount += 1
            advanceTimer()
        case .undo:
            historyCursor -= 1
            userMoveCount = max(0, userMoveCount - 1)
        case .redo:
            historyCursor += 1
            userMoveCount += 1
        case .scramble:
            if case .scrambling = timerSession?.phase,
               !pendingIntents.contains(.scramble)
            {
                timerSession?.phase = .ready
            }
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

    /// Timer transitions on user turns: first turn starts the clock,
    /// reaching solved stops it and records the result.
    private func advanceTimer() {
        guard var session = timerSession else { return }
        if case .ready = session.phase {
            session.phase = .running(Date.now)
        }
        session.moveCount += 1
        if case .running(let start) = session.phase, cubeState.isSolved {
            let duration = Date.now.timeIntervalSince(start)
            let isBest = (stats.best?.duration).map { duration < $0 } ?? true
            stats.add(duration: duration, moveCount: session.moveCount)
            session.phase = .finished(duration, isBest: isBest)
        }
        timerSession = session
    }

    private func enqueue(_ move: Move, intent: MoveIntent, duration: TimeInterval = 0.22) {
        pendingIntents.append(intent)
        scene.enqueue(move, duration: duration)
    }

    // MARK: Cube state persistence

    private static var stateURL: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    private func restoreSavedState() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(CubeState.self, from: data),
              state.isLegal
        else { return }
        cubeState = state
        scene.rebase(to: state.facelets)
    }

    func persistState() {
        try? FileManager.default.createDirectory(
            at: Self.supportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cubeState) {
            try? data.write(to: Self.stateURL, options: .atomic)
        }
    }
}
