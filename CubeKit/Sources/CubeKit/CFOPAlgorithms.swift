/// The last-layer algorithm tables for CFOP: the full 57-case OLL and
/// 21-case PLL sets, transcribed from the standard algorithm sheets
/// (extended notation — wide/slice/rotation tokens — is expanded to
/// outer turns by `ExtendedNotation`).
///
/// Nothing here is trusted by transcription alone: recognition keys are
/// *derived* from each algorithm (the case an algorithm solves is the
/// state its inverse produces from solved), and `validationIssues()`
/// re-checks every entry — parseability, first-two-layer preservation,
/// key uniqueness, and exhaustive coverage of every legal last-layer
/// state. The test suite asserts the issue list is empty.
enum CFOPAlgorithms {
    // MARK: OLL — orient the last layer (57 cases)

    static let ollEntries: [(name: String, notation: String)] = [
        ("1", "R U2 R2 F R F' U2 R' F R F'"),
        ("2", "F R U R' U' F' f R U R' U' f'"),
        ("3", "f R U R' U' f' U' F R U R' U' F'"),
        ("4", "f R U R' U' f' U F R U R' U' F'"),
        ("5", "r' U2 R U R' U r"),
        ("6", "r U2 R' U' R U' r'"),
        ("7", "r U R' U R U2 r'"),
        ("8", "r' U' R U' R' U2 r"),
        ("9", "R U R' U' R' F R2 U R' U' F'"),
        ("10", "R U R' U R' F R F' R U2 R'"),
        ("11", "r U R' U R' F R F' R U2 r'"),
        ("12", "F R U R' U' F' U F R U R' U' F'"),
        ("13", "F U R U' R2 F' R U R U' R'"),
        ("14", "R' F R U R' F' R F U' F'"),
        ("15", "r' U' r R' U' R U r' U r"),
        ("16", "r U r' R U R' U' r U' r'"),
        ("17", "R U R' U R' F R F' U2 R' F R F'"),
        ("18", "r U R' U R U2 r2 U' R U' R' U2 r"),
        ("19", "M U R U R' U' M' R' F R F'"),
        ("20", "M U R U R' U' M2 U R U' r'"),
        ("21", "R U2 R' U' R U R' U' R U' R'"),
        ("22", "R U2 R2 U' R2 U' R2 U2 R"),
        ("23", "R2 D' R U2 R' D R U2 R"),
        ("24", "r U R' U' r' F R F'"),
        ("25", "F' r U R' U' r' F R"),
        ("26 (Anti-Sune)", "R U2 R' U' R U' R'"),
        ("27 (Sune)", "R U R' U R U2 R'"),
        ("28", "r U R' U' M U R U' R'"),
        ("29", "R U R' U' R U' R' F' U' F R U R'"),
        ("30", "F R' F R2 U' R' U' R U R' F2"),
        ("31", "R' U' F U R U' R' F' R"),
        ("32", "L U F' U' L' U L F L'"),
        ("33", "R U R' U' R' F R F'"),
        ("34", "R U R2 U' R' F R U R U' F'"),
        ("35", "R U2 R2 F R F' R U2 R'"),
        ("36", "L' U' L U' L' U L U L F' L' F"),
        ("37", "F R' F' R U R U' R'"),
        ("38", "R U R' U R U' R' U' R' F R F'"),
        ("39", "L F' L' U' L U F U' L'"),
        ("40", "R' F R U R' U' F' U R"),
        ("41", "R U R' U R U2 R' F R U R' U' F'"),
        ("42", "R' U' R U' R' U2 R F R U R' U' F'"),
        ("43", "F' U' L' U L F"),
        ("44", "F U R U' R' F'"),
        ("45", "F R U R' U' F'"),
        ("46", "R' U' R' F R F' U R"),
        ("47", "R' U' R' F R F' R' F R F' U R"),
        ("48", "F R U R' U' R U R' U' F'"),
        ("49", "r U' r2 U r2 U r2 U' r"),
        ("50", "r' U r2 U' r2 U' r2 U r'"),
        ("51", "F U R U' R' U R U' R' F'"),
        ("52", "R U R' U R U' B U' B' R'"),
        ("53", "r' U' R U' R' U R U' R' U2 r"),
        ("54", "r U R' U R U' R' U R U2 r'"),
        ("55", "R' F R U R U' R2 F' R2 U' R' U R U R'"),
        ("56", "r' U' r U' R' U R U' R' U R r' U r"),
        ("57", "R U R' U' M' U R U' r'"),
    ]

    // MARK: PLL — permute the last layer (21 cases)

    static let pllEntries: [(name: String, notation: String)] = [
        ("Aa", "x R' U R' D2 R U' R' D2 R2 x'"),
        ("Ab", "x R2 D2 R U R' D2 R U' R x'"),
        ("E", "x' R U' R' D R U R' D' R U R' D R U' R' D' x"),
        ("F", "R' U' F' R U R' U' R' F R2 U' R' U' R U R' U R"),
        ("Ga", "R2 U R' U R' U' R U' R2 U' D R' U R D'"),
        ("Gb", "R' U' R U D' R2 U R' U R U' R U' R2 D"),
        ("Gc", "R2 U' R U' R U R' U R2 U D' R U' R' D"),
        ("Gd", "R U R' U' D R2 U' R U' R' U R' U R2 D'"),
        ("H", "M2 U M2 U2 M2 U M2"),
        ("Ja", "R' U L' U2 R U' R' U2 R L"),
        ("Jb", "R U R' F' R U R' U' R' F R2 U' R'"),
        ("Na", "R U R' U R U R' F' R U R' U' R' F R2 U' R' U2 R U' R'"),
        ("Nb", "R' U R U' R' F' U' F R U R' F R' F' R U' R"),
        ("Ra", "R U' R' U' R U R D R' U' R D' R' U2 R'"),
        ("Rb", "R2 F R U R U' R' F' R U2 R' U2 R"),
        ("T", "R U R' U' R' F R2 U' R' U' R U R' F'"),
        ("Ua", "M2 U M U2 M' U M2"),
        ("Ub", "M2 U' M U2 M' U' M2"),
        ("V", "R' U R' U' y R' F' R2 U' R' U R' F R F"),
        ("Y", "F R U' R' U' R U R' F' R U R' U' R' F R F'"),
        ("Z", "M' U M2 U M2 U M' U2 M2"),
    ]

    // MARK: Derived tables

    /// Last-layer orientation pattern: corner twists (base 3) and edge
    /// flips (base 2) of slots 0–3, folded into one integer. Only
    /// meaningful when the first two layers are solved.
    static func ollPattern(of state: CubeState) -> Int {
        var corners = 0
        var edges = 0
        for slot in 0..<4 {
            corners = corners * 3 + state.cornerOrientation[slot]
            edges = edges * 2 + state.edgeOrientation[slot]
        }
        return corners * 16 + edges
    }

    static let orientedPattern = ollPattern(of: .solved)

    /// The case each OLL algorithm solves, derived from the algorithm
    /// itself: its inverse applied to a solved cube.
    static let ollTable: [Int: (name: String, moves: [Move])] = {
        var table: [Int: (name: String, moves: [Move])] = [:]
        for entry in ollEntries {
            guard let moves = ExtendedNotation.moves(entry.notation) else { continue }
            let preState = CubeState.solved.applying(moves.inverse)
            table[ollPattern(of: preState)] = (entry.name, moves)
        }
        return table
    }()

    static let pllMoves: [(name: String, moves: [Move])] = pllEntries.compactMap { entry in
        guard let moves = ExtendedNotation.moves(entry.notation) else { return nil }
        return (entry.name, moves)
    }

    // MARK: Validation

    /// True when the bottom two layers (cross edges, middle edges, and
    /// bottom corners) are all home.
    static func firstTwoLayersSolved(_ state: CubeState) -> Bool {
        (4..<12).allSatisfy {
            state.edgePermutation[$0] == $0 && state.edgeOrientation[$0] == 0
        } && (4..<8).allSatisfy {
            state.cornerPermutation[$0] == $0 && state.cornerOrientation[$0] == 0
        }
    }

    /// A U turn carries last-layer orientations along unchanged, so a
    /// pattern rotates by slot index.
    static func rotatedPattern(_ pattern: Int) -> Int {
        var corners = pattern / 16
        var edges = pattern % 16
        var cornerDigits = [0, 0, 0, 0]
        var edgeDigits = [0, 0, 0, 0]
        for i in stride(from: 3, through: 0, by: -1) {
            cornerDigits[i] = corners % 3
            corners /= 3
            edgeDigits[i] = edges % 2
            edges /= 2
        }
        // U sends slot i → i + 1.
        var rotatedCorners = 0
        var rotatedEdges = 0
        for i in 0..<4 {
            rotatedCorners = rotatedCorners * 3 + cornerDigits[(i + 3) % 4]
            rotatedEdges = rotatedEdges * 2 + edgeDigits[(i + 3) % 4]
        }
        return rotatedCorners * 16 + rotatedEdges
    }

    /// Every problem with the algorithm tables, as human-readable
    /// strings; the test suite requires this to be empty.
    static func validationIssues() -> [String] {
        var issues: [String] = []

        // OLL: parse, preserve F2L, produce distinct cases (also
        // distinct modulo U rotation), and cover every legal pattern.
        var seenOrbits: [Int: String] = [:]
        for entry in ollEntries {
            guard let moves = ExtendedNotation.moves(entry.notation) else {
                issues.append("OLL \(entry.name): unparseable notation")
                continue
            }
            let preState = CubeState.solved.applying(moves.inverse)
            guard firstTwoLayersSolved(preState) else {
                issues.append("OLL \(entry.name): does not preserve the first two layers")
                continue
            }
            var pattern = ollPattern(of: preState)
            if pattern == orientedPattern {
                issues.append("OLL \(entry.name): solves nothing (already-oriented case)")
                continue
            }
            // Canonical orbit representative: smallest of the 4 rotations.
            var orbitMin = pattern
            for _ in 0..<3 {
                pattern = rotatedPattern(pattern)
                orbitMin = min(orbitMin, pattern)
            }
            if let other = seenOrbits[orbitMin] {
                issues.append("OLL \(entry.name): same case as OLL \(other) (mod U)")
            } else {
                seenOrbits[orbitMin] = entry.name
            }
        }

        // Coverage: all 27 × 8 legal orientation patterns.
        for corners in 0..<81 {
            let digits = [corners / 27 % 3, corners / 9 % 3, corners / 3 % 3, corners % 3]
            guard digits.reduce(0, +) % 3 == 0 else { continue }
            for edges in 0..<16 where edges.nonzeroBitCount % 2 == 0 {
                var pattern = (((digits[0] * 3 + digits[1]) * 3 + digits[2]) * 3 + digits[3]) * 16 + edges
                var covered = pattern == orientedPattern
                for _ in 0..<4 {
                    if ollTable[pattern] != nil { covered = true }
                    pattern = rotatedPattern(pattern)
                }
                if !covered {
                    issues.append("OLL: no algorithm covers pattern \(pattern) "
                        + "(corners \(digits), edges \(String(edges, radix: 2)))")
                }
            }
        }

        // PLL: parse, preserve F2L and last-layer orientation, and
        // cover every legal last-layer permutation.
        for entry in pllEntries {
            guard let moves = ExtendedNotation.moves(entry.notation) else {
                issues.append("PLL \(entry.name): unparseable notation")
                continue
            }
            let preState = CubeState.solved.applying(moves.inverse)
            if !firstTwoLayersSolved(preState) {
                issues.append("PLL \(entry.name): does not preserve the first two layers")
            } else if ollPattern(of: preState) != orientedPattern {
                issues.append("PLL \(entry.name): disturbs last-layer orientation")
            } else if preState.isSolved {
                issues.append("PLL \(entry.name): solves nothing")
            }
        }

        let uTurns = [[], [Move.u], [Move.u2], [Move.uPrime]]
        var pllStates: [CubeState] = []
        for cornerRank in 0..<24 {
            let cp = Coordinates.unrankPermutation(cornerRank, count: 4)
            for edgeRank in 0..<24 {
                let ep = Coordinates.unrankPermutation(edgeRank, count: 4)
                guard permutationParity(cp) == permutationParity(ep) else { continue }
                var state = CubeState.solved
                for i in 0..<4 {
                    state.cornerPermutation[i] = cp[i]
                    state.edgePermutation[i] = ep[i]
                }
                pllStates.append(state)
            }
        }
        for state in pllStates {
            var covered = false
            outer: for pre in uTurns {
                let aligned = state.applying(pre)
                if aligned.isSolved { covered = true; break }
                for entry in pllMoves {
                    let applied = aligned.applying(entry.moves)
                    for post in uTurns where applied.applying(post).isSolved {
                        covered = true
                        break outer
                    }
                }
            }
            if !covered {
                issues.append("PLL: no algorithm covers corners "
                    + "\(Array(state.cornerPermutation[0..<4])) edges \(Array(state.edgePermutation[0..<4]))")
            }
        }

        return issues
    }
}
