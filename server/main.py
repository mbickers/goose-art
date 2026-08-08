import asyncio
import json
from typing import Annotated, Any

from canvas_service import CanvasService
from canvas_types import Placement, SequencedAction
from fastapi import FastAPI, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import Response

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


def deserialize_client_message(data: dict[str, Any]) -> list[SequencedAction]:
    return [SequencedAction.from_json(action_data) for action_data in data["actions"]]


# TODO: auth
@app.websocket("/canvas")
async def canvas_handler(
    websocket: WebSocket,
    user_id: Annotated[str, Query(alias="userId")],
    device_id: Annotated[str, Query(alias="deviceId")],
):
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

    unsubscribe = canvas.subscribe(canvas_subscriber, call_on_subscribe=True)
    try:
        while True:
            data = await websocket.receive_json()
            actions = deserialize_client_message(data)
            canvas.process_actions(actions, device_id=device_id)
    except WebSocketDisconnect:
        pass
    finally:
        unsubscribe()


# TODO: auth/remove
@app.get("/inspect")
async def inspect_canvas(user_id: Annotated[str, Query(alias="userId")]):
    canvas = users[user_id]
    data = {
        "placements": [p.to_json() for p in canvas.placements],
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
    return Response(
        content=json.dumps(data, indent=2, ensure_ascii=False),
        media_type="application/json; charset=utf-8",
    )
