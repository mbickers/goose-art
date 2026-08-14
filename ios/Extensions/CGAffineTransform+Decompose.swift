import CoreGraphics
import Foundation

// a drag preview is only ever scaled and rotated, never skewed, so the transform stays a
// similarity and these two numbers describe it completely
extension CGAffineTransform {
    func scaleFactor() -> CGFloat {
        return sqrt(a * a + b * b)
    }

    func rotationAngle() -> CGFloat {
        return atan2(b, a)
    }
}
