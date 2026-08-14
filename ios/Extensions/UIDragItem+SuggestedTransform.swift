import ObjectiveC
import UIKit

extension UIDragItem {
    // The pinch and rotation a user applies to a drag preview reach the drop in exactly one
    // place: `__suggestedTransform`, a private ivar on the private `_UIDropItem` standing
    // behind the item. No public API carries it.
    //
    // Unsafe twice over, hence the name. It reads private structure, so a shipped build
    // would count as using private API; and it reads raw memory at an ivar offset, which is
    // why it does so only once the ivar's own type encoding confirms a CGAffineTransform is
    // what lives there. An iOS that renames, retypes or drops the ivar yields nil rather
    // than a plausible-looking misreading of whatever took its place.
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
