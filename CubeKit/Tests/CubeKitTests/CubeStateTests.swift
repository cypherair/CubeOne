import Testing
@testable import CubeKit

@Suite struct MoveTests {
    @Test func notationRoundTrip() {
        for move in Move.allCases {
            #expect(Move(notation: move.notation) == move)
        }
        let sequence = [Move](notation: "R U R' U' F2 B' D2 L")
        #expect(sequence?.notation == "R U R' U' F2 B' D2 L")
        #expect([Move](notation: "R X") == nil)
        #expect([Move](notation: "R2'") == nil)
    }

    @Test func inverseUndoes() {
        for move in Move.allCases {
            #expect(move.inverse.face == move.face)
            #expect((move.quarterTurns + move.inverse.quarterTurns) % 4 == 0)
        }
    }

    @Test func faceAndTurnsRoundTrip() {
        for move in Move.allCases {
            #expect(Move(face: move.face, quarterTurns: move.quarterTurns) == move)
        }
    }
}

@Suite struct CubeStateTests {
    @Test func solvedIsSolved() {
        #expect(CubeState.solved.isSolved)
        #expect(CubeState.solved.facelets == FaceletCube.solved)
    }

    @Test(arguments: Move.allCases)
    func moveHasCorrectOrder(move: Move) {
        // A quarter turn returns to solved after 4 applications, a half
        // turn after 2 — and never earlier.
        let period = move.quarterTurns == 2 ? 2 : 4
        var state = CubeState.solved
        for i in 1...period {
            state.apply(move)
            #expect(state.isSolved == (i == period))
        }
    }

    @Test(arguments: Move.allCases)
    func moveInverseCancels(move: Move) {
        #expect(CubeState.solved.applying(move).applying(move.inverse).isSolved)
    }

    @Test func sequenceInverseCancels() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<20 {
            let moves = (0..<25).map { _ in Move.allCases.randomElement(using: &rng)! }
            #expect(CubeState.solved.applying(moves).applying(moves.inverse).isSolved)
        }
    }

    @Test func stateInverseComposesToIdentity() {
        var rng = SeededRandom(seed: 11)
        for _ in 0..<50 {
            let state = Scrambler.randomState(using: &rng)
            #expect(state.composed(with: state.inverse).isSolved)
            #expect(state.inverse.composed(with: state).isSolved)
        }
    }

    @Test func compositionMatchesSequentialApplication() {
        var rng = SeededRandom(seed: 13)
        let a = (0..<15).map { _ in Move.allCases.randomElement(using: &rng)! }
        let b = (0..<15).map { _ in Move.allCases.randomElement(using: &rng)! }
        let viaSequence = CubeState.solved.applying(a + b)
        let viaComposition = CubeState.solved.applying(a)
            .composed(with: CubeState.solved.applying(b))
        #expect(viaSequence == viaComposition)
    }

    @Test func sexyMoveHasOrderSix() {
        let sexy = [Move](notation: "R U R' U'")!
        var state = CubeState.solved
        for i in 1...6 {
            state = state.applying(sexy)
            #expect(state.isSolved == (i == 6))
        }
    }

    @Test func ruHasOrder105() {
        let ru = [Move](notation: "R U")!
        var state = CubeState.solved
        var order = 0
        repeat {
            state = state.applying(ru)
            order += 1
        } while !state.isSolved && order < 1000
        #expect(order == 105)
    }

    @Test func superflipFlipsAllEdgesOnly() {
        // The famous 20-move superflip: every edge flipped in place,
        // corners untouched. A strong end-to-end check of the move tables.
        let superflip = [Move](notation: "U R2 F B R B2 R U2 L B2 R U' D' R2 F R' L B2 U2 F2")!
        let state = CubeState.solved.applying(superflip)
        #expect(state.cornerPermutation == Array(0..<8))
        #expect(state.cornerOrientation == Array(repeating: 0, count: 8))
        #expect(state.edgePermutation == Array(0..<12))
        #expect(state.edgeOrientation == Array(repeating: 1, count: 12))
    }
}
