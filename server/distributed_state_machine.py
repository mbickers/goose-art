from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass(kw_only=True)
class SequencedAction[Action]:
    action: Action
    device_sequence_number: int


class StateSubscriber[State](Protocol):
    def __call__(
        self,
        *,
        state: State,
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        pass


class DistributedStateMachineServer[State, Action]:
    def __init__(
        self,
        *,
        initial_state: State,
        reduce: Callable[[State, Action], State],
    ):
        self.initial_state = initial_state
        self.reduce = reduce
        self.state = initial_state
        self.subscribers: list[StateSubscriber[State]] = []
        self.greatest_seen_device_sequence_numbers: dict[str, int] = {}

    def process_actions(
        self, actions: list[SequencedAction[Action]], *, device_id: str
    ):
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
            self.state = self.reduce(self.state, action.action)

        self.on_change()

    def reset(self):
        self.state = self.initial_state
        self.on_change()

    def on_change(self):
        for subscriber in self.subscribers:
            subscriber(
                state=self.state,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

    def subscribe(self, subscriber: StateSubscriber[State], *, call_on_subscribe: bool):
        if call_on_subscribe:
            subscriber(
                state=self.state,
                greatest_seen_device_sequence_numbers=self.greatest_seen_device_sequence_numbers,
            )

        self.subscribers.append(subscriber)

        def unsubscribe():
            self.subscribers.remove(subscriber)

        return unsubscribe


def serialize_server_message[State](
    *,
    state: State,
    greatest_seen_device_sequence_number: int,
    serialize_state: Callable[[State], Any],
) -> dict[str, Any]:
    return {
        "greatestSeenDeviceSequenceNumber": greatest_seen_device_sequence_number,
        "state": serialize_state(state),
    }


def deserialize_client_message[Action](
    data: dict[str, Any],
    *,
    deserialize_action: Callable[[dict[str, Any]], Action],
) -> list[SequencedAction[Action]]:
    return [
        SequencedAction(
            action=deserialize_action(action_data["action"]),
            device_sequence_number=action_data["deviceSequenceNumber"],
        )
        for action_data in data["actions"]
    ]
