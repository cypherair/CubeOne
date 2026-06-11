import Testing
@testable import CubeKit

@Suite struct SliceMoveTests {
    @Test func notationRoundTrips() {
        for slice in SliceMove.allCases {
            #expect(SliceMove(notation: slice.notation) == slice)
        }
        #expect(SliceMove(notation: "M'") == .mPrime)
        #expect(SliceMove(notation: "X") == nil)
        #expect(SliceMove(notation: "M3") == nil)
    }

    @Test(arguments: SliceMove.allCases)
    func inverseCancels(slice: SliceMove) {
        let state = CubeState.solved.applying(slice).applying(slice.inverse)
        #expect(state.isSolved)
    }

    @Test func quarterTurnOrders() {
        for axis in 0..<3 {
            let quarter = SliceMove(axisIndex: axis, quarterTurns: 1)!
            var state = CubeState.solved
            for i in 1...4 {
                state = state.applying(quarter)
                #expect(state.isSolved == (i == 4), "axis \(axis) period")
            }
            // Half turn equals two quarters.
            let half = SliceMove(axisIndex: axis, quarterTurns: 2)!
            #expect(
                CubeState.solved.applying(half)
                    == CubeState.solved.applying(quarter).applying(quarter))
            // Prime equals three quarters.
            let prime = SliceMove(axisIndex: axis, quarterTurns: 3)!
            #expect(
                CubeState.solved.applying(prime)
                    == CubeState.solved.applying(quarter).applying(quarter).applying(quarter))
        }
    }

    @Test func fixedCenterEquivalentsFixTheSliceItself() {
        // In the fixed-center representation, the slice's own edges stay
        // put (the frame moves instead) while both outer layers — and
        // therefore all corners — rotate.
        let fixedEdges: [SliceMove: [Int]] = [
            .m: [1, 3, 5, 7],   // uf, ub, df, db
            .e: [8, 9, 10, 11], // fr, fl, bl, br
            .s: [0, 2, 4, 6],   // ur, ul, dr, dl
        ]
        for (slice, slots) in fixedEdges {
            let state = CubeState.solved.applying(slice)
            for slot in slots {
                #expect(state.edgePermutation[slot] == slot, "\(slice) slot \(slot)")
                #expect(state.edgeOrientation[slot] == 0, "\(slice) slot \(slot)")
            }
            // Every corner belongs to one of the two outer layers.
            #expect((0..<8).allSatisfy { state.cornerPermutation[$0] != $0 })
        }
    }

    @Test func parallelSlicesCommute() {
        // Outer pairs on the same axis commute trivially; different axes
        // don't — sanity-check the algebra wiring.
        let me = CubeState.solved.applying(SliceMove.m).applying(SliceMove.e)
        let em = CubeState.solved.applying(SliceMove.e).applying(SliceMove.m)
        #expect(me != em)

        let mm2 = CubeState.solved.applying(SliceMove.m).applying(SliceMove.m2)
        #expect(mm2 == CubeState.solved.applying(SliceMove.mPrime))
    }

    @Test func signedQuarterTurnsMatchInverses() {
        for slice in SliceMove.allCases {
            #expect(slice.inverse.axisIndex == slice.axisIndex)
            // Inverse rotation sums to a full turn (mod 4) in signed terms.
            let total = slice.signedQuarterTurns + slice.inverse.signedQuarterTurns
            #expect(total % 4 == 0)
        }
    }
}
