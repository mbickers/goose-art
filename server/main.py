import asyncio
from typing import Callable
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from canvas import Action, CanvasState, Placement

app = FastAPI()


canvas = CanvasState()
users: dict[str, CanvasState] = {
    "max": canvas,
    "brian": canvas,
}


class ClientMessage(BaseModel):
    actions: list[Action]


class ServerMessage(BaseModel):
    greatest_seen_device_sequence_number: int
    placements: list[Placement]


# TODO: auth
@app.websocket("/canvas")
async def canvas_handler(websocket: WebSocket, user_id: str, device_id: str):
    canvas = users.get(user_id)
    if not canvas:
        await websocket.close(code=4001, reason="user not assigned to a canvas")
        return

    await websocket.accept()

    def canvas_subscriber(
        *,
        placements: list[Placement],
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        msg = ServerMessage(
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
        "placements": [p.model_dump() for p in canvas.placements],
        "greatest_seen_device_sequence_numbers": canvas.greatest_seen_device_sequence_numbers,
    }
