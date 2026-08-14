import asyncio
from collections import Counter
from dataclasses import dataclass
from functools import cache

from apple_notifications import send_push
from canvas_types import Placement
from users import other_user_ids_sharing_canvas, user_configs_by_user_id


@dataclass(kw_only=True, frozen=True)
class PlacementNotificationKey:
    placer_user_id: str
    recipient_user_id: str


def placed_emojis(*, before: list[Placement], after: list[Placement]) -> list[str]:
    placement_ids_before = {placement.id for placement in before}
    return [
        placement.emoji
        for placement in after
        if placement.id not in placement_ids_before
    ]


class PlacementNotifier:
    def __init__(self):
        self.connection_counts_by_user_id: Counter[str] = Counter()
        self.unseen_emojis_by_key: dict[PlacementNotificationKey, list[str]] = {}
        # held so that in-flight sends aren't garbage collected
        self.send_tasks: set[asyncio.Task] = set()

    def connected(self, *, user_id: str):
        self.connection_counts_by_user_id[user_id] += 1
        self.unseen_emojis_by_key = {
            key: emojis
            for key, emojis in self.unseen_emojis_by_key.items()
            if key.recipient_user_id != user_id
        }

    def canvas_cleared(self, *, canvas_id: str):
        self.unseen_emojis_by_key = {
            key: emojis
            for key, emojis in self.unseen_emojis_by_key.items()
            if user_configs_by_user_id[key.recipient_user_id].canvas_id != canvas_id
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
                    # each send replaces the last, so a burst shows up as one
                    # notification instead of a stack
                    collapse_id=f"{placer_user_id}:{recipient_user_id}",
                )
            )
            self.send_tasks.add(task)
            task.add_done_callback(self.send_tasks.discard)


@cache
def placement_notifier() -> PlacementNotifier:
    return PlacementNotifier()
