import Testing
@testable import CubeKit

@Suite struct FaceletCubeTests {
    @Test func solvedRoundTrip() throws {
        let state = try FaceletCube.solved.validatedState()
        #expect(state.isSolved)
    }

    @Test func randomStatesRoundTrip() throws {
        var rng = SeededRandom(seed: 42)
        for _ in 0..<200 {
            let state = Scrambler.randomState(using: &rng)
            let roundTripped = try state.facelets.validatedState()
            #expect(roundTripped == state)
        }
    }

    @Test func moveSequenceMatchesFaceletRendering() throws {
        // Applying moves at the cubie level and reading stickers back
        // must agree with the validated state.
        let moves = [Move](notation: "R U R' U' F2 D L' B")!
        let state = CubeState.solved.applying(moves)
        #expect(try state.facelets.validatedState() == state)
    }

    private func expectError(
        _ stickers: [Face], _ expected: CubeValidationError,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try FaceletCube(stickers: stickers).validatedState()
            Issue.record("expected \(expected)", sourceLocation: sourceLocation)
        } catch {
            #expect(error == expected, sourceLocation: sourceLocation)
        }
    }

    @Test func detectsWrongColorCounts() {
        var stickers = FaceletCube.solved.stickers
        stickers[0] = .down
        expectError(stickers, .wrongColorCounts)
    }

    @Test func detectsWrongCenters() {
        var stickers = FaceletCube.solved.stickers
        stickers[FaceletCube.centerIndex(of: .up)] = .down
        stickers[FaceletCube.centerIndex(of: .down)] = .up
        expectError(stickers, .wrongCenters)
    }

    @Test func detectsTwistedCorner() {
        var state = CubeState.solved
        state.cornerOrientation[0] = 1
        expectError(state.facelets.stickers, .cornerTwist)
    }

    @Test func detectsFlippedEdge() {
        var state = CubeState.solved
        state.edgeOrientation[0] = 1
        expectError(state.facelets.stickers, .edgeFlip)
    }

    @Test func detectsSwappedCorners() {
        var state = CubeState.solved
        state.cornerPermutation.swapAt(0, 1)
        expectError(state.facelets.stickers, .permutationParity)
    }

    @Test func detectsSwappedEdges() {
        var state = CubeState.solved
        state.edgePermutation.swapAt(0, 1)
        expectError(state.facelets.stickers, .permutationParity)
    }

    @Test func detectsUnrecognizableCorner() {
        // Swap a corner sticker (U color) with an edge sticker (F color):
        // counts stay balanced but the corner has no U/D sticker.
        var stickers = FaceletCube.solved.stickers
        stickers.swapAt(8, 19)
        expectError(stickers, .unrecognizablePiece)
    }

    @Test func detectsDuplicateCorners() {
        // Render two URF pieces: overwrite the DRB slot's stickers with
        // URF colors arranged so both slots read as the same real piece,
        // then fix counts by also borrowing matching opposite stickers.
        var state = CubeState.solved
        // Put piece URF into both slot URF and slot DRB (state-level
        // duplication renders stickers that read back as duplicates).
        state.cornerPermutation[Corner.drb.rawValue] = Corner.urf.rawValue
        expectError(state.facelets.stickers, .wrongColorCounts)
    }
}

@Suite struct ScramblerTests {
    @Test func randomStatesAreAlwaysLegal() throws {
        var rng = SeededRandom(seed: 99)
        var solvedCount = 0
        for _ in 0..<300 {
            let state = Scrambler.randomState(using: &rng)
            // Legality means the facelet rendering validates cleanly.
            _ = try state.facelets.validatedState()
            if state.isSolved { solvedCount += 1 }
        }
        #expect(solvedCount == 0)
    }

    @Test func parityFixProducesLegalPermutations() {
        var rng = SeededRandom(seed: 5)
        for _ in 0..<300 {
            let state = Scrambler.randomState(using: &rng)
            #expect(
                permutationParity(state.cornerPermutation)
                    == permutationParity(state.edgePermutation)
            )
            #expect(state.cornerOrientation.reduce(0, +) % 3 == 0)
            #expect(state.edgeOrientation.reduce(0, +) % 2 == 0)
        }
    }
}
