from typing import Protocol

from canvas_types import (
    ClearAction,
    Placement,
    PlacementAction,
    SequencedAction,
    UndoAction,
)


class PlacementsSubscriber(Protocol):
    def __call__(
        self,
        *,
        placements: list[Placement],
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        pass


class CanvasService:
    def __init__(self):
        self.placements: list[Placement] = []
        self.subscribers: list[PlacementsSubscriber] = []
        self.greatest_seen_device_sequence_numbers: dict[str, int] = {}

    def process_actions(self, actions: list[SequencedAction], *, device_id: str):
        if device_id not in self.greatest_seen_device_sequence_numbers:
            self.greatest_seen_device_sequence_numbers[device_id] = 0
        actions = [
            action
            for action in actions
            if action.device_sequence_number
            > self.greatest_seen_device_sequence_numbers[device_id]
        ]
        if not actions:
            return

        for action in actions:
            self.greatest_seen_device_sequence_numbers[device_id] = (
                action.device_sequence_number
            )

            if isinstance(action.action, PlacementAction):
                self.placements.append(action.action.placement)
            elif isinstance(action.action, UndoAction):
                self.placements = [
                    p for p in self.placements if p.id != action.action.placement_id
                ]
            elif isinstance(action.action, ClearAction):
                self.placements = []

        self.on_change()

    def clear(self):
        self.placements = []
        self.on_change()

    def on_change(self):
        for subscriber in self.subscribers:
            subscriber(
                placements=self.placements,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

    def subscribe(self, subscriber: PlacementsSubscriber, *, call_on_subscribe: bool):
        if call_on_subscribe:
            subscriber(
                placements=self.placements,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

        self.subscribers.append(subscriber)

        def unsubscribe():
            self.subscribers.remove(subscriber)

        return unsubscribe
