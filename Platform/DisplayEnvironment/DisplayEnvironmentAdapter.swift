#if canImport(UIKit)
import UIKit

/// The only module that names iOS 27.1 fold APIs. The solver itself sees plain rectangles.
@MainActor
public enum DisplayEnvironmentAdapter {
    public static func capture(in view: UIView) -> DisplayEnvironment {
        let safe = view.safeAreaLayoutGuide.layoutFrame
        var regions: [ReservedRegion] = []
        if #available(iOS 27.1, *) {
            regions += view.reservedRegions(kind: .division).filter(\.isActive).map {
                ReservedRegion(frame: $0.frame, kind: .division)
            }
            regions += view.reservedRegions(kind: .occlusion).filter(\.isActive).map {
                ReservedRegion(frame: $0.frame, kind: .occlusion)
            }
        }
        return DisplayEnvironment(bounds: view.bounds, safeBounds: safe, reservedRegions: regions)
    }

    /// A hinge callback requests a fresh geometry query. Hinge status never changes DS lid input.
    @discardableResult
    public static func observeHinge(on view: UIView, geometryChanged: @escaping () -> Void) -> UIInteraction? {
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, _ in geometryChanged() }
            view.addInteraction(interaction)
            return interaction
        }
        return nil
    }
}
#endif
