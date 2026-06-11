/// WCA-style scrambling: a uniformly random *state* over all
/// ~4.3 × 10¹⁹ legal cube positions, not a random move sequence.
public enum Scrambler {
    public static func randomState() -> CubeState {
        var rng = SystemRandomNumberGenerator()
        return randomState(using: &rng)
    }

    public static func randomState(using rng: inout some RandomNumberGenerator) -> CubeState {
        let cornerPermutation = Array(0..<8).shuffled(using: &rng)
        var edgePermutation = Array(0..<12).shuffled(using: &rng)
        if permutationParity(cornerPermutation) != permutationParity(edgePermutation) {
            edgePermutation.swapAt(0, 1)
        }

        var cornerOrientation = (0..<7).map { _ in Int.random(in: 0..<3, using: &rng) }
        cornerOrientation.append((3 - cornerOrientation.reduce(0, +) % 3) % 3)

        var edgeOrientation = (0..<11).map { _ in Int.random(in: 0..<2, using: &rng) }
        edgeOrientation.append(edgeOrientation.reduce(0, +) % 2)

        return CubeState(
            cornerPermutation: cornerPermutation, cornerOrientation: cornerOrientation,
            edgePermutation: edgePermutation, edgeOrientation: edgeOrientation
        )
    }
}
