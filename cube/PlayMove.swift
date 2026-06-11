import CubeKit

/// A turn the user can perform on the cube: an outer face turn or an
/// independent middle-slice turn.
enum PlayMove: Hashable {
    case face(Move)
    case slice(SliceMove)

    var inverse: PlayMove {
        switch self {
        case .face(let move): .face(move.inverse)
        case .slice(let slice): .slice(slice.inverse)
        }
    }

    var notation: String {
        switch self {
        case .face(let move): move.notation
        case .slice(let slice): slice.notation
        }
    }
}

extension Array where Element == PlayMove {
    var notation: String { map(\.notation).joined(separator: " ") }
}
