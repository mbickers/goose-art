from dataclasses import dataclass
from functools import cache

from canvas_types import Placement
from notifications import Coalescer, send_push

# long enough that dropping a handful of emoji in one sitting arrives as a single push,
# short enough that a placement is still recent news when the phone buzzes
placement_coalesce_delay = 15.0


@dataclass(kw_only=True, frozen=True)
class PlacementNotification:
    placer_user_id: str
    recipient_user_ids: frozenset[str]


# comparing the canvas before and after rather than reading the actions: an emoji that was
# only moved keeps its id, one that was placed and dropped off the canvas in the same
# message never lands in the after state, and actions a reconnecting client resent change
# nothing, so none of them are mistaken for a placement
def placed_emojis(*, before: list[Placement], after: list[Placement]) -> list[str]:
    placement_ids_before = {placement.id for placement in before}
    return [
        placement.emoji
        for placement in after
        if placement.id not in placement_ids_before
    ]


async def flush_placements(*, key: PlacementNotification, events: list[str]):
    await send_push(
        user_ids=sorted(key.recipient_user_ids),
        body=f"{key.placer_user_id} placed {''.join(events)}",
    )


@cache
def placement_coalescer() -> Coalescer[PlacementNotification, str]:
    return Coalescer(delay=placement_coalesce_delay, flush=flush_placements)
