import ObjectiveC
import UIKit

extension UIDragItem {
    func unsafeExtractSuggestedTransform() -> CGAffineTransform? {
        guard
            let ivar = class_getInstanceVariable(
                object_getClass(self),
                "__suggestedTransform"
            ),
            let encoding = ivar_getTypeEncoding(ivar).map({ String(cString: $0) }),
            encoding.contains("CGAffineTransform")
        else { return nil }

        return Unmanaged.passUnretained(self).toOpaque()
            .advanced(by: ivar_getOffset(ivar))
            .assumingMemoryBound(to: CGAffineTransform.self).pointee
    }
}
