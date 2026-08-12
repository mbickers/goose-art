import asyncio
from collections import Counter
from dataclasses import dataclass
from functools import cache

from apple_notifications import send_push
from canvas_types import Placement
from users import other_user_ids_sharing_canvas


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


# a placement notifies immediately, and the push names every emoji the recipient has not
# seen from that placer rather than only the ones that just landed. the collapse id makes
# each send replace the last, so a burst reads as one notification whose body grows
# instead of a stack of them — which is what waiting on a timer used to buy, without the
# notification arriving after the user has already watched the emoji appear.
#
# a recipient with a live connection is being served the canvas as it changes, so nothing
# placed while they are connected is unseen in the first place.
class PlacementNotifier:
    def __init__(self):
        # counted rather than a flag because a user can have more than one device, and
        # one of them going away doesn't mean they stopped looking
        self.connection_counts_by_user_id: Counter[str] = Counter()
        self.unseen_emojis_by_key: dict[PlacementNotificationKey, list[str]] = {}
        # held so that in-flight sends aren't garbage collected
        self.send_tasks: set[asyncio.Task] = set()

    # a connection is served the whole canvas on subscribe, which shows everything
    # outstanding at once, so none of it is still unseen
    def connected(self, *, user_id: str):
        self.connection_counts_by_user_id[user_id] += 1
        self.unseen_emojis_by_key = {
            key: emojis
            for key, emojis in self.unseen_emojis_by_key.items()
            if key.recipient_user_id != user_id
        }

    def disconnected(self, *, user_id: str):
        self.connection_counts_by_user_id[user_id] -= 1
        if self.connection_counts_by_user_id[user_id] <= 0:
            del self.connection_counts_by_user_id[user_id]

    def placed(self, *, placer_user_id: str, emojis: list[str]):
        if not emojis:
            return
        for recipient_user_id in sorted(other_user_ids_sharing_canvas(placer_user_id)):
            if recipient_user_id in self.connection_counts_by_user_id:
                continue
            key = PlacementNotificationKey(
                placer_user_id=placer_user_id, recipient_user_id=recipient_user_id
            )
            unseen_emojis = self.unseen_emojis_by_key.get(key, []) + emojis
            self.unseen_emojis_by_key[key] = unseen_emojis
            task = asyncio.create_task(
                send_push(
                    user_id=recipient_user_id,
                    body=f"{placer_user_id} placed {''.join(unseen_emojis)}",
                    collapse_id=f"{placer_user_id}:{recipient_user_id}",
                )
            )
            self.send_tasks.add(task)
            task.add_done_callback(self.send_tasks.discard)


@cache
def placement_notifier() -> PlacementNotifier:
    return PlacementNotifier()
