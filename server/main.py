import asyncio
from typing import Any, Callable
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from canvas_service import CanvasService
from canvas_types import Action, Placement

app = FastAPI()


canvas = CanvasService()
users: dict[str, CanvasService] = {
    "max": canvas,
    "brian": canvas,
}


def serialize_server_message(
    placements: list[Placement],
    greatest_seen_device_sequence_number: int,
) -> dict[str, Any]:
    return {
        "greatestSeenDeviceSequenceNumber": greatest_seen_device_sequence_number,
        "placements": [p.to_json() for p in placements],
    }


def deserialize_client_message(data: dict[str, Any]) -> list[Action]:
    return [Action.from_json(action_data) for action_data in data["actions"]]


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
        msg = serialize_server_message(
            placements,
            greatest_seen_device_sequence_numbers.get(device_id, 0),
        )
        asyncio.create_task(websocket.send_json(msg))

    unsubscribe: Callable[[], None] | None = None
    try:
        while True:
            data = await websocket.receive_json()
            actions = deserialize_client_message(data)
            canvas.process_actions(actions, device_id=device_id)
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
        "placements": [p.to_json() for p in canvas.placements],
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
