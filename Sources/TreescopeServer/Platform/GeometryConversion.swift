import Foundation
import TreescopeProtocol

#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif

#if canImport(CoreGraphics)
extension CaptureEngine {
    func rect(_ r: CGRect) -> Rect {
        Rect(x: Double(r.origin.x), y: Double(r.origin.y),
             width: Double(r.size.width), height: Double(r.size.height))
    }
}
#endif

#if canImport(QuartzCore)
extension CaptureEngine {
    func transform(_ layer: CALayer) -> Transform3D? {
        let t = layer.transform
        guard !CATransform3DIsIdentity(t) else { return nil }
        return Transform3D(m: [
            Double(t.m11), Double(t.m12), Double(t.m13), Double(t.m14),
            Double(t.m21), Double(t.m22), Double(t.m23), Double(t.m24),
            Double(t.m31), Double(t.m32), Double(t.m33), Double(t.m34),
            Double(t.m41), Double(t.m42), Double(t.m43), Double(t.m44),
        ])
    }
}
#endif
