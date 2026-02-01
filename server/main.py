import asyncio
from typing import Callable, Literal, Protocol
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

app = FastAPI()


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


class PlaceActionData(BaseModel):
    type: Literal["place"]
    placement: Placement


class UndoActionData(BaseModel):
    type: Literal["undo"]
    id: str


class ClearActionData(BaseModel):
    type: Literal["clear"]


ActionData = PlaceActionData | UndoActionData | ClearActionData


class Action(BaseModel):
    action: ActionData
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

            if isinstance(action.action, PlaceActionData):
                self.placements.append(action.action.placement)
            elif isinstance(action.action, UndoActionData):
                self.placements = [
                    p for p in self.placements if p.id != action.action.id
                ]
            elif isinstance(action.action, ClearActionData):
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


canvas = CanvasState()
users: dict[str, CanvasState] = {
    "max": canvas,
    "brian": canvas,
}


class ClientMessage(BaseModel):
    actions: list[Action]
    greatest_seen_server_sequence_numbere: int


class ServerMessage(BaseModel):
    server_sequence_number: int
    greatest_seen_device_sequence_number: int
    placements: list[Placement]


# TODO: auth
@app.websocket("/canvas/v1")
async def canvas_handler(websocket: WebSocket, user_id: str, device_id: str):
    canvas = users.get(user_id)
    if not canvas:
        await websocket.close(code=4001, reason="user not assigned to a canvas")
        return

    await websocket.accept()

    def canvas_subscriber(
        *,
        server_sequence_number: int,
        placements: list[Placement],
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        msg = ServerMessage(
            server_sequence_number=server_sequence_number,
            greatest_seen_device_sequence_number=greatest_seen_device_sequence_numbers.get(
                device_id, 0
            ),
            placements=placements,
        )
        asyncio.create_task(websocket.send_json(msg.model_dump()))

    unsubscribe: Callable[[], None] | None = None
    try:
        while True:
            data = await websocket.receive_json()
            message = ClientMessage.model_validate(data)
            canvas.process_actions(message.actions, device_id=device_id)
            if unsubscribe is None:
                unsubscribe = canvas.subscribe(
                    canvas_subscriber, call_on_subscribe=True
                )

    except WebSocketDisconnect:
        pass
    finally:
        if unsubscribe is not None:
            unsubscribe()


# TODO: auth
@app.get("/inspect")
async def inspect_canvas(user_id: str):
    canvas = users[user_id]
    return {
        "server_sequence_number": canvas.server_sequence_number,
        "placements": [p.model_dump() for p in canvas.placements],
        "greatest_seen_device_sequence_numbers": canvas.greatest_seen_device_sequence_numbers,
    }
