import CubeKit
import RealityKit
import SwiftUI
import simd

/// Identifies a sticker entity and the cubelet face it was placed on.
struct StickerComponent: Component {
    let faceletIndex: Int
    let homeNormal: SIMD3<Float>
}

/// Owns the RealityKit scene: 26 cubelets carrying 54 sticker entities,
/// the turn-animation queue, and the gesture math that converts drags
/// into face turns.
///
/// Sticker colors always render the "base state" set by `rebase(to:)`;
/// cubelet transforms carry the moves performed since. The app's
/// `CubeState` is the logical source of truth — the scene reports each
/// committed move through `onMoveCommitted`.
@Observable
final class CubeSceneController {
    private(set) var root = Entity()
    private let cubeRoot = Entity()
    private var cubelets: [Entity] = []
    private var stickerEntities: [Int: ModelEntity] = [:]
    private let camera = PerspectiveCamera()
    private let settings: SettingsStore
    /// The facelet colors the stickers currently render (the state at the
    /// last rebase, with individual edits applied on top).
    private(set) var baseFacelets = FaceletCube.solved

    /// Called when a turn's animation completes and the move logically
    /// happened.
    var onMoveCommitted: ((PlayMove) -> Void)?

    /// Disables drag-to-turn (used while solving plays back or editing).
    var allowsDirectTurns = true

    private struct PendingTurn {
        let turn: PlayMove
        let duration: TimeInterval
    }
    private var queue: [PendingTurn] = []
    private var isAnimating = false
    private(set) var isIdle = true

    static let spacing: Float = 1.04
    private let cameraDirection = simd_normalize(SIMD3<Float>(3.2, 2.8, 5.2))
    /// User pinch zoom, as a multiplier on the auto-fit distance.
    private var zoomFactor: Float = 1.0
    private var viewportAspect: Float = 1.0

    init(settings: SettingsStore) {
        self.settings = settings
        StickerComponent.registerComponent()
        buildScene()
    }

    private func stickerMaterial(for face: Face) -> SimpleMaterial {
        CubeMaterials.sticker(settings.platformColor(for: face))
    }

    // MARK: Scene construction

    private func buildScene() {
        root.addChild(cubeRoot)

        for x in -1...1 {
            for y in -1...1 {
                for z in -1...1 where !(x == 0 && y == 0 && z == 0) {
                    let cubelet = makeCubelet()
                    cubelet.position = SIMD3<Float>(Float(x), Float(y), Float(z)) * Self.spacing
                    cubeRoot.addChild(cubelet)
                    cubelets.append(cubelet)
                }
            }
        }

        for placement in FaceletGeometry.allPlacements {
            guard let cubelet = cubelet(atGrid: placement.gridPosition) else { continue }
            let sticker = makeSticker(for: placement)
            cubelet.addChild(sticker)
            stickerEntities[placement.faceletIndex] = sticker
        }

        camera.look(at: .zero, from: cameraDirection * fitDistance(), relativeTo: nil)
        root.addChild(camera)

        let keyLight = Entity()
        keyLight.components.set(DirectionalLightComponent(color: .white, intensity: 2600))
        keyLight.look(at: .zero, from: [4, 6, 6], relativeTo: nil)
        root.addChild(keyLight)

        let fillLight = Entity()
        fillLight.components.set(DirectionalLightComponent(color: .white, intensity: 900))
        fillLight.look(at: .zero, from: [-5, -2, 3], relativeTo: nil)
        root.addChild(fillLight)
    }

    private func makeCubelet() -> Entity {
        let body = ModelEntity(
            mesh: .generateBox(size: 1.0, cornerRadius: 0.09),
            materials: [CubeMaterials.plastic]
        )
        return body
    }

    private func makeSticker(for placement: FaceletGeometry.Placement) -> ModelEntity {
        let sticker = ModelEntity(
            mesh: .generateBox(width: 0.84, height: 0.84, depth: 0.04, cornerRadius: 0.10),
            materials: [stickerMaterial(for: placement.face)]
        )
        let normal = placement.face.normal
        sticker.position = normal * 0.51
        // The sticker mesh faces +z; orient it along the face normal.
        if placement.face != .front {
            if placement.face == .back {
                sticker.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            } else {
                let rotationAxis = simd_normalize(simd_cross([0, 0, 1], normal))
                sticker.orientation = simd_quatf(angle: .pi / 2, axis: rotationAxis)
            }
        }
        sticker.components.set(StickerComponent(faceletIndex: placement.faceletIndex, homeNormal: normal))
        sticker.components.set(InputTargetComponent())
        sticker.collision = CollisionComponent(shapes: [.generateBox(width: 0.84, height: 0.84, depth: 0.06)])
        return sticker
    }

    private func cubelet(atGrid grid: SIMD3<Int>) -> Entity? {
        cubelets.first { gridPosition(of: $0) == grid }
    }

    private func gridPosition(of cubelet: Entity) -> SIMD3<Int> {
        let scaled = cubelet.position / Self.spacing
        return SIMD3<Int>(Int(scaled.x.rounded()), Int(scaled.y.rounded()), Int(scaled.z.rounded()))
    }

    // MARK: Rendering a state

    /// Resets all cubelet transforms to home and paints stickers from
    /// `facelets`, making it the new visual base state.
    func rebase(to facelets: FaceletCube) {
        queue.removeAll()
        var cubeletIndex = 0
        for x in -1...1 {
            for y in -1...1 {
                for z in -1...1 where !(x == 0 && y == 0 && z == 0) {
                    let cubelet = cubelets[cubeletIndex]
                    cubelet.transform = Transform(
                        translation: SIMD3<Float>(Float(x), Float(y), Float(z)) * Self.spacing)
                    cubeletIndex += 1
                }
            }
        }
        baseFacelets = facelets
        for (faceletIndex, sticker) in stickerEntities {
            sticker.model?.materials = [stickerMaterial(for: facelets.stickers[faceletIndex])]
        }
    }

    /// Paints a single sticker (editor support).
    func paintSticker(at faceletIndex: Int, with face: Face) {
        baseFacelets.stickers[faceletIndex] = face
        stickerEntities[faceletIndex]?.model?.materials = [stickerMaterial(for: face)]
    }

    /// Re-skins every sticker with the current settings colors (call
    /// after the user changes the color scheme).
    func repaintAll() {
        for (faceletIndex, sticker) in stickerEntities {
            sticker.model?.materials = [stickerMaterial(for: baseFacelets.stickers[faceletIndex])]
        }
    }

    /// The facelet index a hit entity represents. Only meaningful while
    /// rebased (editor mode), when home placement equals current.
    func faceletIndex(of entity: Entity) -> Int? {
        entity.components[StickerComponent.self]?.faceletIndex
    }

    // MARK: Turn animation

    func enqueue(_ turn: PlayMove, duration: TimeInterval = 0.22) {
        queue.append(PendingTurn(turn: turn, duration: duration))
        isIdle = false
        processQueue()
    }

    func enqueue(_ moves: [Move], duration: TimeInterval) {
        guard !moves.isEmpty else { return }
        queue.append(contentsOf: moves.map { PendingTurn(turn: .face($0), duration: duration) })
        isIdle = false
        processQueue()
    }

    private func processQueue() {
        guard !isAnimating else { return }
        guard !queue.isEmpty else {
            isIdle = true
            return
        }
        isAnimating = true
        let turn = queue.removeFirst()
        animate(turn)
    }

    private func animate(_ turn: PendingTurn) {
        let axis: SIMD3<Float>
        let angle: Float
        let layer: Int
        switch turn.turn {
        case .face(let move):
            (axis, angle, layer) = FaceletGeometry.rotation(for: move)
        case .slice(let slice):
            (axis, angle) = FaceletGeometry.rotation(for: slice)
            layer = 0
        }
        let axisIndex = FaceletGeometry.axisIndex(of: axis)

        let pivot = Entity()
        cubeRoot.addChild(pivot)
        let participants = cubelets.filter { gridPosition(of: $0)[axisIndex] == layer }
        for cubelet in participants {
            cubelet.setParent(pivot, preservingWorldTransform: true)
        }

        var target = Transform()
        target.rotation = simd_quatf(angle: angle, axis: axis)
        pivot.move(to: target, relativeTo: cubeRoot, duration: turn.duration, timingFunction: .easeInOut)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(turn.duration + 0.02))
            pivot.transform = target
            for cubelet in participants {
                cubelet.setParent(self.cubeRoot, preservingWorldTransform: true)
            }
            pivot.removeFromParent()

            if case .slice = turn.turn {
                // Re-express the slice turn in fixed-center terms: rotate
                // the whole cube by the slice rotation and counter-rotate
                // every cubelet. Net visual change: none. The slice's own
                // cubelets return to their original transforms (centers
                // never move in the model); the outer layers end exactly
                // where the equivalent outer-turn pair would put them.
                let q = target.rotation
                self.cubeRoot.orientation = self.cubeRoot.orientation * q
                let qInverse = q.inverse
                for cubelet in self.cubelets {
                    cubelet.position = qInverse.act(cubelet.position)
                    cubelet.orientation = qInverse * cubelet.orientation
                }
            }
            for cubelet in self.cubelets {
                self.snapTransform(of: cubelet)
            }
            // Settle the queue (and isIdle) before reporting the commit,
            // so a commit handler can immediately enqueue a follow-up.
            self.isAnimating = false
            self.processQueue()
            self.onMoveCommitted?(turn.turn)
        }
    }

    /// Re-quantizes a cubelet's transform after a turn so float drift
    /// can never accumulate.
    private func snapTransform(of cubelet: Entity) {
        let grid = gridPosition(of: cubelet)
        cubelet.position = SIMD3<Float>(Float(grid.x), Float(grid.y), Float(grid.z)) * Self.spacing
        cubelet.orientation = Self.snappedOrientation(cubelet.orientation)
    }

    /// Nearest orientation whose basis vectors are signed unit axes.
    static func snappedOrientation(_ orientation: simd_quatf) -> simd_quatf {
        let matrix = simd_matrix3x3(orientation)
        func snap(_ column: SIMD3<Float>) -> SIMD3<Float> {
            let snapped = FaceletGeometry.snappedAxis(column)
            return SIMD3<Float>(Float(snapped.x), Float(snapped.y), Float(snapped.z))
        }
        let x = snap(matrix.columns.0)
        let y = snap(matrix.columns.1)
        let z = simd_cross(x, y)
        return simd_quatf(simd_float3x3(columns: (x, y, z)))
    }

    // MARK: Gestures

    private var dragConsumed = false
    private var orbitBlocked = false

    /// Handles a drag that started on a sticker. Returns the turn once
    /// the drag has committed to one (at most once per gesture).
    func handleStickerDrag(entity: Entity, translation: CGSize) -> PlayMove? {
        // In view-only mode the whole cube surface acts as an orbit
        // handle, so sticker touches must not block orbiting.
        guard settings.lockMode != .viewOnly else { return nil }
        orbitBlocked = true
        guard allowsDirectTurns, !dragConsumed, isIdle else { return nil }
        let dragVector = SIMD2<Float>(Float(translation.width), Float(-translation.height))
        guard simd_length(dragVector) > 12 else { return nil }

        guard let sticker = entity.components[StickerComponent.self],
              let cubelet = entity.parent else { return nil }

        // Current outward normal of the sticker in cube-local space.
        let normal = FaceletGeometry.snappedAxis(cubelet.orientation.act(sticker.homeNormal))
        let grid = gridPosition(of: cubelet)
        guard let turn = resolveTurn(grid: grid, normal: normal, drag: dragVector) else { return nil }
        dragConsumed = true
        return turn
    }

    func dragEnded() {
        dragConsumed = false
        orbitBlocked = false
    }

    /// Picks the turn whose on-screen motion best matches the drag —
    /// outer layers become face moves, the middle layer a slice move.
    private func resolveTurn(grid: SIMD3<Int>, normal: SIMD3<Int>, drag: SIMD2<Float>) -> PlayMove? {
        let cameraRight = camera.orientation.act([1, 0, 0])
        let cameraUp = camera.orientation.act([0, 1, 0])
        let cubeOrientation = cubeRoot.orientation

        let stickerLocal = SIMD3<Float>(Float(grid.x), Float(grid.y), Float(grid.z)) * Self.spacing
            + SIMD3<Float>(Float(normal.x), Float(normal.y), Float(normal.z)) * 0.5
        let stickerWorld = cubeOrientation.act(stickerLocal)

        let normalizedDrag = simd_normalize(drag)
        var bestScore: Float = 0.25  // minimum alignment before we commit
        var bestTurn: PlayMove?

        for axisIndex in 0..<3 {
            // Rotation axes parallel to the sticker normal don't move it.
            guard axisIndex != FaceletGeometry.axisIndex(of: SIMD3<Float>(
                Float(normal.x), Float(normal.y), Float(normal.z))) else { continue }
            let layer = grid[axisIndex]

            var axisLocal = SIMD3<Float>(repeating: 0)
            axisLocal[axisIndex] = 1
            let axisWorld = cubeOrientation.act(axisLocal)
            // Velocity of the sticker under positive rotation about the axis.
            let velocity = simd_cross(axisWorld, stickerWorld)
            let screen = SIMD2<Float>(simd_dot(velocity, cameraRight), simd_dot(velocity, cameraUp))
            guard simd_length(screen) > 0.05 else { continue }
            let score = simd_dot(simd_normalize(screen), normalizedDrag)
            guard abs(score) > bestScore else { continue }
            let sign = score > 0 ? 1 : -1
            let turn: PlayMove?
            if abs(layer) == 1 {
                turn = FaceletGeometry.move(
                    axis: axisIndex, layer: layer, rotationSign: sign).map(PlayMove.face)
            } else {
                turn = FaceletGeometry.sliceMove(
                    axis: axisIndex, rotationSign: sign).map(PlayMove.slice)
            }
            if let turn {
                bestScore = abs(score)
                bestTurn = turn
            }
        }
        return bestTurn
    }

    /// Whether a freshly started background drag may orbit right now.
    /// (Two-finger mode and rotation lock route around one-finger orbits.)
    var canBeginOrbit: Bool {
        var allowed = !orbitBlocked && settings.lockMode != .layersOnly
        #if os(iOS)
        allowed = allowed && !settings.twoFingerOrbit
        #endif
        return allowed
    }

    /// Orbits the whole cube. `bypassGating` is used by the dedicated
    /// two-finger gesture, which is unambiguous by construction.
    func orbit(translationDelta: CGSize, bypassGating: Bool = false) {
        if !bypassGating {
            guard !orbitBlocked, settings.lockMode != .layersOnly else { return }
        } else {
            guard settings.lockMode != .layersOnly else { return }
        }
        let sensitivity = 0.008 * Float(settings.orbitSensitivity)
        let yaw = simd_quatf(
            angle: Float(translationDelta.width) * sensitivity, axis: [0, 1, 0])
        let cameraRight = camera.orientation.act([1, 0, 0])
        let pitch = simd_quatf(
            angle: Float(translationDelta.height) * sensitivity, axis: cameraRight)
        cubeRoot.orientation = yaw * pitch * cubeRoot.orientation
    }

    // MARK: Camera fit & zoom

    /// Auto-fits the camera so the whole cube is visible whatever the
    /// view's shape (fixes overflow on portrait iPhone and Mac resizes).
    func setViewportAspect(_ aspect: CGFloat) {
        viewportAspect = max(Float(aspect), 0.05)
        updateCameraPosition(factor: zoomFactor)
    }

    /// Distance at which the cube's bounding sphere fits both the
    /// vertical and horizontal field of view (default vertical FOV 60°).
    private func fitDistance() -> Float {
        let boundingRadius: Float = Self.spacing * 1.5 * 1.7320508 * 1.07
        let halfVertical: Float = .pi / 6
        let halfHorizontal = atan(tan(halfVertical) * viewportAspect)
        let limiting = min(halfVertical, halfHorizontal)
        return boundingRadius / sin(limiting) * 1.05
    }

    private func updateCameraPosition(factor: Float) {
        camera.position = cameraDirection * (fitDistance() * factor)
    }

    func zoom(magnification: CGFloat, ended: Bool) {
        let proposed = zoomFactor / Float(magnification)
        let clamped = min(max(proposed, 0.6), 1.8)
        updateCameraPosition(factor: clamped)
        if ended { zoomFactor = clamped }
    }
}
