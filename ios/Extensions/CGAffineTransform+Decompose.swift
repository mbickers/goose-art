import CoreGraphics
import Foundation

extension CGAffineTransform {
    func scaleFactor() -> CGFloat {
        return sqrt(a * a + b * b)
    }

    func rotationAngle() -> CGFloat {
        return atan2(b, a)
    }
}
