from dataclasses import dataclass
from typing import Protocol


@dataclass(kw_only=True)
class Position:
    x: float
    y: float


@dataclass(kw_only=True)
class Placement:
    id: str
    emoji: str
    position: Position
    scale: float
    rotation: float
    is_mirrored: bool
    user_id: str


@dataclass(kw_only=True)
class PlacementAction:
    placement: Placement


@dataclass(kw_only=True)
class UndoAction:
    id: str


@dataclass(kw_only=True)
class ClearAction:
    pass


@dataclass(kw_only=True)
class Action:
    action: PlacementAction | UndoAction | ClearAction
    sequence_number: int


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

    def process_actions(self, actions: list[Action], *, device_id: str):
        if device_id not in self.greatest_seen_device_sequence_numbers:
            self.greatest_seen_device_sequence_numbers[device_id] = 0
        actions = [
            action
            for action in actions
            if action.sequence_number
            > self.greatest_seen_device_sequence_numbers[device_id]
        ]
        if not actions:
            return

        for action in actions:
            self.greatest_seen_device_sequence_numbers[device_id] = (
                action.sequence_number
            )

            if isinstance(action.action, PlacementAction):
                self.placements.append(action.action.placement)
            elif isinstance(action.action, UndoAction):
                self.placements = [
                    p for p in self.placements if p.id != action.action.id
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
