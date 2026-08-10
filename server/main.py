import asyncio
import json
from functools import cache
from pathlib import Path
from typing import Annotated, Any

from fastapi import (
    FastAPI,
    Header,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import Response

from canvas_service import CanvasService
from canvas_types import Placement, SequencedAction

app = FastAPI()


canvas = CanvasService()
users: dict[str, CanvasService] = {
    "max": canvas,
    "brian": canvas,
}

# untracked so that tokens stay out of the repo, and so that deploy.sh (which only
# rsyncs git-tracked files) leaves the deployed copy alone
tokens_path = Path(__file__).parent / "tokens.json"


@cache
def user_ids_by_token() -> dict[str, str]:
    return json.loads(tokens_path.read_text())


def authenticated_user_id(authorization: str | None) -> str | None:
    if authorization is None or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ")
    user_ids = user_ids_by_token()
    if token not in user_ids:
        return None
    return user_ids[token]


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


@app.websocket("/canvas")
async def canvas_handler(
    websocket: WebSocket,
    device_id: Annotated[str, Query(alias="deviceId")],
    authorization: Annotated[str | None, Header()] = None,
):
    # closing before accept makes the handshake fail with HTTP 403, which the client
    # reads as "this token is bad" and stops retrying
    user_id = authenticated_user_id(authorization)
    if user_id is None or user_id not in users:
        await websocket.close(code=4001, reason="unauthenticated")
        return
    canvas = users[user_id]

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


@app.get("/login")
async def login(authorization: Annotated[str | None, Header()] = None):
    user_id = authenticated_user_id(authorization)
    if user_id is None or user_id not in users:
        raise HTTPException(status_code=401)
    return {"userId": user_id}


# TODO: remove
@app.get("/inspect")
async def inspect_canvas(authorization: Annotated[str | None, Header()] = None):
    user_id = authenticated_user_id(authorization)
    if user_id is None or user_id not in users:
        raise HTTPException(status_code=401)
    canvas = users[user_id]
    data = {
        "placements": [p.to_json() for p in canvas.placements],
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
    return Response(
        content=json.dumps(data, indent=2, ensure_ascii=False),
        media_type="application/json; charset=utf-8",
    )
