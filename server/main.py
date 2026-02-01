import asyncio
from typing import Any, Callable
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from canvas_service import (
    Action,
    CanvasService,
    ClearAction,
    Placement,
    PlacementAction,
    Position,
    UndoAction,
)

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
        "placements": [
            {
                "id": p.id,
                "emoji": p.emoji,
                "position": {"x": p.position.x, "y": p.position.y},
                "scale": p.scale,
                "rotation": p.rotation,
                "isMirrored": p.is_mirrored,
                "userId": p.user_id,
            }
            for p in placements
        ],
    }


def deserialize_client_message(data: dict[str, Any]) -> list[Action]:
    actions = []
    for action_data in data["actions"]:
        sequence_number = action_data["sequenceNumber"]
        inner = action_data["action"]

        if "placement" in inner:
            p = inner["placement"]
            action = PlacementAction(
                placement=Placement(
                    id=p["id"],
                    emoji=p["emoji"],
                    position=Position(x=p["position"]["x"], y=p["position"]["y"]),
                    scale=p["scale"],
                    rotation=p["rotation"],
                    is_mirrored=p["isMirrored"],
                    user_id=p["userId"],
                )
            )
        elif "id" in inner:
            action = UndoAction(id=inner["id"])
        else:
            action = ClearAction()

        actions.append(Action(action=action, sequence_number=sequence_number))

    return actions


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
        "placements": [
            {
                "id": p.id,
                "emoji": p.emoji,
                "position": {"x": p.position.x, "y": p.position.y},
                "scale": p.scale,
                "rotation": p.rotation,
                "isMirrored": p.is_mirrored,
                "userId": p.user_id,
            }
            for p in canvas.placements
        ],
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
