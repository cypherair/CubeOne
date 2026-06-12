import CubeKit
import SwiftUI

/// User preferences, persisted as JSON in Application Support.
@Observable
final class SettingsStore {
    enum TurnSpeed: String, Codable, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: String { rawValue }
        var duration: TimeInterval {
            switch self {
            case .slow: 0.32
            case .normal: 0.22
            case .fast: 0.14
            }
        }
        var label: String { rawValue.capitalized }
    }

    struct StoredColor: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    enum ColorPreset: String, CaseIterable, Identifiable {
        case classic, pastel, vivid
        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        /// Colors indexed by `Face.rawValue` (U, R, F, D, L, B).
        var colors: [StoredColor] {
            switch self {
            case .classic:
                [
                    StoredColor(red: 1.00, green: 1.00, blue: 1.00),
                    StoredColor(red: 0.85, green: 0.12, blue: 0.16),
                    StoredColor(red: 0.06, green: 0.62, blue: 0.27),
                    StoredColor(red: 1.00, green: 0.84, blue: 0.05),
                    StoredColor(red: 0.95, green: 0.48, blue: 0.04),
                    StoredColor(red: 0.05, green: 0.32, blue: 0.73),
                ]
            case .pastel:
                [
                    StoredColor(red: 0.98, green: 0.97, blue: 0.94),
                    StoredColor(red: 0.95, green: 0.55, blue: 0.58),
                    StoredColor(red: 0.62, green: 0.86, blue: 0.65),
                    StoredColor(red: 0.99, green: 0.91, blue: 0.60),
                    StoredColor(red: 0.98, green: 0.74, blue: 0.52),
                    StoredColor(red: 0.61, green: 0.72, blue: 0.94),
                ]
            case .vivid:
                [
                    StoredColor(red: 1.00, green: 1.00, blue: 1.00),
                    StoredColor(red: 1.00, green: 0.05, blue: 0.25),
                    StoredColor(red: 0.00, green: 0.85, blue: 0.35),
                    StoredColor(red: 1.00, green: 0.92, blue: 0.00),
                    StoredColor(red: 1.00, green: 0.45, blue: 0.00),
                    StoredColor(red: 0.00, green: 0.45, blue: 1.00),
                ]
            }
        }
    }

    /// What kinds of cube manipulation are currently allowed.
    enum LockMode: String, Codable, CaseIterable, Identifiable {
        /// Layer turns and whole-cube rotation both work.
        case free
        /// Only layer turns — whole-cube rotation is locked.
        case layersOnly
        /// Only whole-cube rotation — layer turns are locked.
        case viewOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .free: "Off"
            case .layersOnly: "Layers only"
            case .viewOnly: "View only"
            }
        }

        var next: LockMode {
            switch self {
            case .free: .layersOnly
            case .layersOnly: .viewOnly
            case .viewOnly: .free
            }
        }
    }

    var soundEnabled = true { didSet { save() } }
    var hapticsEnabled = true { didSet { save() } }
    var turnSpeed = TurnSpeed.normal { didSet { save() } }
    /// Multiplier on orbit drag sensitivity.
    var orbitSensitivity = 1.0 { didSet { save() } }
    var lockMode = LockMode.free { didSet { save() } }
    var solvingMethod = SolvingMethod.fast { didSet { save() } }

    enum SolvingMethod: String, Codable, CaseIterable, Identifiable {
        /// Kociemba two-phase: ~20 moves, found in milliseconds.
        case fast
        /// Korf IDA* over pattern databases: provably shortest, takes
        /// minutes and requires prepared tables.
        case optimal
        /// Thistlethwaite's four-phase group reduction: each phase
        /// provably shortest within its move set.
        case thistlethwaite
        /// The speedcubing method: cross, F2L pairs, then the full
        /// OLL/PLL algorithm sets with named cases.
        case cfop
        /// Classic layer-by-layer, the way people learn: long but
        /// followable, with named stages.
        case beginner

        var id: String { rawValue }
        var label: String {
            switch self {
            case .fast: "Fast"
            case .optimal: "Optimal"
            case .thistlethwaite: "Thistlethwaite"
            case .cfop: "CFOP"
            case .beginner: "Beginner"
            }
        }

        var detail: String {
            switch self {
            case .fast: "~20 moves, found instantly"
            case .optimal: "Proven shortest — takes minutes, needs tables"
            case .thistlethwaite: "Four phases, each provably shortest (~30–45 moves)"
            case .cfop: "Cross, F2L, OLL, PLL — the speedcuber's way (~60 moves)"
            case .beginner: "Step by step, the way people learn (~200 moves)"
            }
        }
    }
    /// iOS: orbit requires two fingers; one finger only turns faces.
    var twoFingerOrbit = false { didSet { save() } }
    private(set) var faceColors = ColorPreset.classic.colors

    /// All fields optional so settings files from any older version
    /// still load (`rotationLock` is the legacy boolean lock).
    private struct Snapshot: Codable {
        var soundEnabled: Bool?
        var hapticsEnabled: Bool?
        var turnSpeed: TurnSpeed?
        var orbitSensitivity: Double?
        var rotationLock: Bool?
        var lockMode: LockMode?
        /// Stored as a raw string so a file written by a newer version
        /// (with methods this build doesn't know) still decodes — an
        /// unknown method falls back to `.fast` instead of throwing and
        /// silently resetting every setting.
        var solvingMethod: String?
        var twoFingerOrbit: Bool?
        var faceColors: [StoredColor]?
    }

    private let fileURL: URL
    private var isLoading = false

    init(directory: URL = AppModel.supportDirectory) {
        fileURL = directory.appendingPathComponent("settings.json")
        load()
    }

    // MARK: Colors

    func platformColor(for face: Face) -> PlatformColor {
        let c = faceColors[face.rawValue]
        return PlatformColor(
            red: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: 1)
    }

    func color(for face: Face) -> Color {
        let c = faceColors[face.rawValue]
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    func setColor(_ color: Color, for face: Face) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
        let resolved = PlatformColor(color).usingColorSpace(.sRGB) ?? .white
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        PlatformColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        faceColors[face.rawValue] = StoredColor(
            red: Double(red), green: Double(green), blue: Double(blue))
        save()
    }

    func apply(preset: ColorPreset) {
        faceColors = preset.colors
        save()
    }

    // MARK: Persistence

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        soundEnabled = snapshot.soundEnabled ?? true
        hapticsEnabled = snapshot.hapticsEnabled ?? true
        turnSpeed = snapshot.turnSpeed ?? .normal
        orbitSensitivity = snapshot.orbitSensitivity ?? 1.0
        lockMode = snapshot.lockMode
            ?? (snapshot.rotationLock == true ? .layersOnly : .free)
        solvingMethod = snapshot.solvingMethod.flatMap(SolvingMethod.init(rawValue:)) ?? .fast
        twoFingerOrbit = snapshot.twoFingerOrbit ?? false
        if let colors = snapshot.faceColors, colors.count == 6 {
            faceColors = colors
        }
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Snapshot(
            soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled,
            turnSpeed: turnSpeed, orbitSensitivity: orbitSensitivity,
            rotationLock: nil, lockMode: lockMode, solvingMethod: solvingMethod.rawValue,
            twoFingerOrbit: twoFingerOrbit, faceColors: faceColors)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}
