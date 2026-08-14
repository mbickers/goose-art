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

## Most comments shouldn't exist!

The only reason to leave a comment is to justify confusing code, e.g.

- **The framework does something surprising, so correct code looks wrong.**
- **A dead end you already tried**
- **A unit or coordinate system the types don't carry.**
- **Something tightly coupled that isn't obvious locally**

Use plain language. Write it the way you'd say it out loud to the next person.
A comment that reads like an essay is usually explaining something the code
already said.

## Keep comments short, and attach it to what it explains

A block above a call that explains three of its arguments in turn makes a reader
hold all three at once and then match them back by position. Split it, and put
each part on the argument it's about:

```swift
// bad — a paragraph to unpick and map back onto the call
// the preview's own centre rather than the touch: a drag is carried by the point it
// was grabbed at, so the finger sits off the glyph's centre by however far that was,
// and dropping at it lands crooked. its size is what it was before the pinch, so the
// size on screen is that put through the transform.
onDrop(
    emoji,
    preview.target.center,
    preview.size.height * transform.scaleFactor(),
    transform.rotationAngle()
)

// good — each reason sits on the line it explains
onDrop(
    emoji,
    // a drag hangs off wherever it was grabbed, so the touch isn't the centre
    preview.target.center,
    // the preview's size is what it was before the pinch
    preview.size.height * transform.scaleFactor(),
    transform.rotationAngle()
)
```

Put a comment on the line it is about. Attaching it to the function or type
around it is not close enough: the reader has to work out which line it meant,
and it drifts as the code changes. A note about one modifier goes on that
modifier, inside the body. One about a property goes on the property, at the end
of the line if it fits. One about a branch goes inside the branch.

## Comments and docs describe the code as it stands

Whoever reads a comment is looking at the code it sits above, and whoever reads
a doc is following it today. Both want to know what is there — not the route
that produced it. "We used to…", "this changed when…", or a rule introduced by
naming the first change that needed it all hand the reader a timeline they
can't see and don't need. Git history is where that belongs.

```md
<!-- bad — the rule arrives wrapped in a change the reader has to already know -->
Saved canvases are untracked too, so a change to their format has to be applied
on the droplet after the deploy that introduced it. Titles were the first:

<!-- good — the same rule, and still true of the next format change -->
Saved canvases are untracked too, so a change to the format they are written in
has to be migrated on the droplet by hand after the deploy that changed it.
```

Code that has to survive data an older version wrote is the one place the past
is worth mentioning at all, and even there it is the general property that keeps
the code honest. An old version can appear as an example; it isn't the subject.

```swift
// bad — only a reader who remembers that change can tell what this protects against
// a canvas written by a build from before canvases had titles is a bare array of
// placements, which fails to decode here

// good — says what the code guarantees, whatever wrote the state
// local state that fails to decode — written by an older version of the app, say — is
// discarded rather than crashing: the device starts empty and the server's copy replaces
// it on connect
```

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
