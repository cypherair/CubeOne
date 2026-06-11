import CubeKit
import RealityKit
import SwiftUI

/// The interactive 3D cube. Drag a sticker to turn its layer, drag empty
/// space to orbit (or two fingers, if that setting is on), pinch to zoom.
struct CubeView: View {
    let model: AppModel

    /// Decided once at the start of each background drag: a gesture that
    /// began while a sticker was being touched (or while orbiting is
    /// disallowed) stays inert for its entire lifetime.
    @State private var orbitDecision: Bool?
    @State private var lastOrbitTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            RealityView { content in
                content.camera = .virtual
                content.add(model.scene.root)
            }
            .gesture(stickerDrag)
            .simultaneousGesture(orbitDrag)
            .simultaneousGesture(zoom)
            #if os(iOS)
            .gesture(TwoFingerOrbitGesture(isEnabled: model.settings.twoFingerOrbit) { delta in
                model.scene.orbit(translationDelta: delta, bypassGating: true)
            })
            #endif
            .onAppear {
                model.scene.setViewportAspect(proxy.size.width / max(proxy.size.height, 1))
            }
            .onChange(of: proxy.size) { _, size in
                model.scene.setViewportAspect(size.width / max(size.height, 1))
            }
        }
    }

    private var stickerDrag: some Gesture {
        // Zero minimum distance so the first touch immediately claims the
        // gesture and blocks orbiting; the controller applies its own
        // movement threshold before committing a turn.
        DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .onChanged { value in
                if let move = model.scene.handleStickerDrag(
                    entity: value.entity, translation: value.gestureValue.translation)
                {
                    model.performUserMove(move)
                }
            }
            .onEnded { value in
                model.scene.dragEnded()
                // In edit mode a motionless press on a sticker paints it.
                let translation = value.gestureValue.translation
                if model.editor != nil, abs(translation.width) < 6, abs(translation.height) < 6,
                   let index = model.scene.faceletIndex(of: value.entity)
                {
                    model.paintSticker(at: index)
                }
            }
    }

    private var orbitDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if orbitDecision == nil {
                    orbitDecision = model.scene.canBeginOrbit
                }
                guard orbitDecision == true else { return }
                let delta = CGSize(
                    width: value.translation.width - lastOrbitTranslation.width,
                    height: value.translation.height - lastOrbitTranslation.height
                )
                lastOrbitTranslation = value.translation
                model.scene.orbit(translationDelta: delta)
            }
            .onEnded { _ in
                orbitDecision = nil
                lastOrbitTranslation = .zero
            }
    }

    private var zoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                model.scene.zoom(magnification: value.magnification, ended: false)
            }
            .onEnded { value in
                model.scene.zoom(magnification: value.magnification, ended: true)
            }
    }
}
