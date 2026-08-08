import CoreGraphics
import Foundation

extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    func safeDivide(_ divisor: CGFloat) -> CGPoint {
        guard divisor != 0 else { return .zero }
        return CGPoint(x: x / divisor, y: y / divisor)
    }

    func norm() -> CGFloat {
        return sqrt(x * x + y * y)
    }

    func angle() -> CGFloat {
        return atan2(y, x)
    }
}
