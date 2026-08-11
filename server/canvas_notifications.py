import asyncio
from collections.abc import Coroutine
from dataclasses import dataclass
from functools import cache
from typing import Any, Protocol

from apple_notifications import send_push
from canvas_types import Placement

# long enough that dropping a handful of emoji in one sitting arrives as a single push,
# short enough that a placement is still recent news when the phone buzzes
placement_coalesce_delay = 15.0


# one key per pair, so each recipient batches on their own window rather than sharing one
@dataclass(kw_only=True, frozen=True)
class PlacementNotificationKey:
    placer_user_id: str
    recipient_user_id: str


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


class CoalescedFlush[Key, Event](Protocol):
    def __call__(self, *, key: Key, events: list[Event]) -> Coroutine[Any, Any, None]:
        pass


# batches events sharing a key into one flush. the window is anchored at the first event
# of a batch rather than extended by later ones, so a steady stream of events still
# delivers on a bounded delay instead of being held back indefinitely.
class Coalescer[Key, Event]:
    def __init__(self, *, delay: float, flush: CoalescedFlush[Key, Event]):
        self.delay = delay
        self.flush = flush
        self.pending_events: dict[Key, list[Event]] = {}
        # held so that in-flight batches aren't garbage collected mid-wait
        self.flush_tasks: dict[Key, asyncio.Task] = {}

    def add(self, *, key: Key, event: Event):
        if key in self.pending_events:
            self.pending_events[key].append(event)
            return
        self.pending_events[key] = [event]
        self.flush_tasks[key] = asyncio.create_task(self.flush_after_delay(key=key))

    async def flush_after_delay(self, *, key: Key):
        await asyncio.sleep(self.delay)
        events = self.pending_events.pop(key)
        del self.flush_tasks[key]
        await self.flush(key=key, events=events)


async def flush_placements(*, key: PlacementNotificationKey, events: list[str]):
    await send_push(
        user_id=key.recipient_user_id,
        body=f"{key.placer_user_id} placed {''.join(events)}",
    )


@cache
def notification_coalescer() -> Coalescer[PlacementNotificationKey, str]:
    return Coalescer(delay=placement_coalesce_delay, flush=flush_placements)
