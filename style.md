# Style

## Formatting is automated, so nothing below is about whitespace

`./format.sh` formats and lints everything — ruff for Python, swift-format for
Swift — or `./format.sh <files>` for specific ones. Always go through it rather
than invoking ruff or swift-format yourself: it owns the tool versions, config
paths, and flags, so a direct call can disagree with what the hook does. The
pre-commit hook in
`.githooks/pre-commit` runs it on staged files and restages the result, so
formatting never reaches a review. Point git at it once per clone:

```sh
git config core.hooksPath .githooks
```

The rules that follow are the ones a formatter can't check: what to name, what
to label, and when a thing is worth naming at all.

## A TODO belongs to a branch, never to main

A TODO is how you leave a note for yourself while a branch is in flight, so
branches carry them freely. Landing one on main turns it into a note to nobody:
the code says work is outstanding and nothing says who owes it. Resolve it, or
delete what it is attached to, before the branch lands.

The same hook enforces this — it refuses a commit on main whose index holds a
`TODO` in a `.py` or `.swift` file, and `.githooks/pre-merge-commit` hands merges
to it, since a merge that applies cleanly commits without running `pre-commit`.

## Use explicit, required keyword arguments whenever the meaning of an argument is not obvious

A call site should be readable without opening the function being called. If a
reader can't tell what a value *means* from the call alone, it needs a label.

Make keyword arguments **mandatory by default** in both languages, and only drop
the label when the argument's meaning is unmistakable from the function name and
the value itself.

The rule earns its keep when a function takes **several** arguments — that's
where a bare value is genuinely ambiguous and where a reader has to count
positions. With a single argument there's nothing to confuse it with, so a label
is optional; add one only if the value's role still isn't clear from the call.

### Swift

Label every argument, with one exception: **don't repeat a word in both the base
name and the first argument's label.** Swift reads the function name and its
first argument as a single phrase, so a label that restates the name stutters at
the call site.

```swift
// bad — stutters: upsertPlacement(placement:), placementGlyph(placement:)
func upsertPlacement(placement: Placement)
func placementGlyph(placement: Placement) -> some View

// good — the noun lives in the base name, so the first label is dropped
func upsertPlacement(_ placement: Placement)
func placementGlyph(_ placement: Placement) -> some View

// also good — the noun lives in the label instead
func upsert(placement: Placement)
```

`_` is only for that first, already-named argument. Every later argument keeps
its label, and any argument whose meaning isn't carried by the function name
keeps its label regardless of position:

```swift
func makeDragGesture(
    source: ActivePlacementState.Source,
    makePlacement: @escaping (CGPoint) -> Placement
) -> some Gesture
```

Give enum cases with associated values labels too, so `switch` bindings and
construction both read as prose:

```swift
case upsert(placement: Placement)   // not: case upsert(Placement)
case remove(placementId: String)
```

`_` is still right when the label would only stutter — `Emoji(_ character:
Character)`, or operators.

### Python

Use `*` in signatures, and `@dataclass(kw_only=True)` for data types, so callers
must name their arguments:

```python
def process_actions(self, actions: list[SequencedAction], *, device_id: str): ...
def subscribe(self, subscriber: PlacementsSubscriber, *, call_on_subscribe: bool): ...

@dataclass(kw_only=True)
class Placement: ...
```

A single argument the function name already describes may stay positional:
`Placement.from_json(data)`.

## Only name a constant when the name earns its place

A literal used once, next to the code that explains it, is already clear. Lifting
it to a named constant costs a reader a jump to a definition somewhere else in
the file — or another file — to learn a number they could have read in place. A
comment at the use site says more than a name ever can.

```swift
// bad — two names to look up, both used exactly once, neither closer to the truth
private let scaleSensitivity: CGFloat = 1.5
private let minimumInitialOffsetNorm: CGFloat = 0.01
...
let clampedInitialOffsetNorm = max(secondTouchState.initialOffset.norm(), minimumInitialOffsetNorm)
let clampedScale = secondTouchState.baseScale * scaleSensitivity * ...

// good — the comment explains what the names couldn't
// how far the second finger has to travel to scale the placement, and the floor on
// where it started from, so that a second touch landing on the placement itself
// doesn't divide by ~0
let clampedInitialOffsetNorm = max(secondTouchState.initialOffset.norm(), 0.01)
let clampedScale = secondTouchState.baseScale * 1.5 * ...
```

Name a constant when it is a fact about the domain rather than a tuning knob in
the code that happens to use it — when it belongs to the type, and would still be
true if the UI using it were rewritten. Those live with the type they describe:

```swift
// good — a placement is invalid outside this range no matter who is clamping it
struct Placement {
    static let scaleRange: ClosedRange<CGFloat> = 0.05...1
}
```

The other reason to name one is **more than one use**: two call sites that must
agree need a single definition, or they'll drift apart.

## Avoid ViewBuilder-style trailing closures for our own functions

Trailing-closure syntax hides the parameter label, which is exactly the
information a reader needs when the closure's role isn't self-evident. Pass the
closure as a normal labeled argument:

```swift
// bad — nothing at the call site says what this closure is for
makeDragGesture(source: .palette) { placementPosition in
    Placement(emoji: emoji, position: placementPosition, ...)
}

// good
makeDragGesture(
    source: .palette,
    makePlacement: { placementPosition in
        Placement(emoji: emoji, position: placementPosition, ...)
    }
)
```

Trailing closures are fine where the role genuinely is obvious: SwiftUI
container builders (`VStack { }`, `ZStack { }`, `ForEach(...) { }`), and a
button's action (`ActionButton(iconName: "gearshape") { ... }`).
