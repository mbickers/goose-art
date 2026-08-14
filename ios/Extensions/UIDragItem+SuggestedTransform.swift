import ObjectiveC
import UIKit

extension UIDragItem {
    // the pinch and rotation a drag preview was given, which UIKit keeps to itself on the
    // private _UIDropItem behind the item. unsafe twice over: private structure, so a
    // shipped build counts as using private API, and a raw read at an ivar offset — hence
    // the encoding check, so a renamed or retyped ivar yields nil rather than nonsense
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
