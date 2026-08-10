from dataclasses import dataclass
from functools import cache

from canvas_types import Action, UpsertAction
from notifications import Coalescer, send_push

# long enough that dropping a handful of emoji in one sitting arrives as a single push,
# short enough that a placement is still recent news when the phone buzzes
placement_coalesce_delay = 15.0


@dataclass(kw_only=True, frozen=True)
class PlacementNotification:
    placer_user_id: str
    recipient_user_ids: frozenset[str]


# an upsert of an id already on the canvas is a move, resize or rotate of an emoji that
# is already there, which is not worth a notification. the ids seen so far grow as the
# batch is walked, because a client that was offline sends the placement of an emoji and
# the moves that followed it in one message, and only the first of those is a placement.
def placed_emojis(
    *, actions: list[Action], existing_placement_ids: set[str]
) -> list[str]:
    seen_placement_ids = set(existing_placement_ids)
    emojis = []
    for action in actions:
        if (
            isinstance(action, UpsertAction)
            and action.placement.id not in seen_placement_ids
        ):
            emojis.append(action.placement.emoji)
            seen_placement_ids.add(action.placement.id)
    return emojis


async def flush_placements(*, key: PlacementNotification, events: list[str]):
    await send_push(
        user_ids=sorted(key.recipient_user_ids),
        body=f"{key.placer_user_id} placed {''.join(events)}",
    )


@cache
def placement_coalescer() -> Coalescer[PlacementNotification, str]:
    return Coalescer(delay=placement_coalesce_delay, flush=flush_placements)
