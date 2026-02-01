from typing import Literal, Protocol
from pydantic import BaseModel


class Position(BaseModel):
    x: float
    y: float


class Placement(BaseModel):
    id: str
    emoji: str
    position: Position
    scale: float
    rotation: float
    isMirrored: bool
    userId: str


class PlacementAction(BaseModel):
    type: Literal["place"]
    placement: Placement


class UndoAction(BaseModel):
    type: Literal["undo"]
    id: str


class ClearAction(BaseModel):
    type: Literal["clear"]


class Action(BaseModel):
    action: PlacementAction | UndoAction | ClearAction
    sequence_number: int


class PlacementsSubscriber(Protocol):
    def __call__(
        self,
        *,
        server_sequence_number: int,
        placements: list[Placement],
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        pass


class CanvasState:
    def __init__(self):
        self.placements: list[Placement] = []
        self.server_sequence_number = 0
        self.subscribers: list[PlacementsSubscriber] = []
        self.greatest_seen_device_sequence_numbers = {}

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
        self.server_sequence_number += 1
        for subscriber in self.subscribers:
            subscriber(
                server_sequence_number=self.server_sequence_number,
                placements=self.placements,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

    def subscribe(self, subscriber: PlacementsSubscriber, *, call_on_subscribe: bool):
        if call_on_subscribe:
            subscriber(
                server_sequence_number=self.server_sequence_number,
                placements=self.placements,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

        self.subscribers.append(subscriber)

        def unsubscribe():
            self.subscribers.remove(subscriber)

        return unsubscribe
