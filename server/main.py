import asyncio
import json
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from functools import cache
from pathlib import Path
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import (
    FastAPI,
    Header,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import Response
from pydantic import BaseModel, Field

from canvas_notifications import (
    PlacementNotification,
    placed_emojis,
    placement_coalescer,
)
from canvas_types import (
    Action,
    Placement,
    action_from_json,
    placements_to_json,
    reduce_canvas,
)
from distributed_state_machine import (
    DistributedStateMachineServer,
    deserialize_client_message,
    serialize_server_message,
)
from notifications import apns_client, device_token_registry

type CanvasServer = DistributedStateMachineServer[list[Placement], Action]

clear_timezone = ZoneInfo("America/New_York")
clear_time = time(hour=2)


def seconds_until_next_clear(now: datetime) -> float:
    next_clear = datetime.combine(now.date(), clear_time, tzinfo=clear_timezone)
    if next_clear <= now:
        next_clear = datetime.combine(
            now.date() + timedelta(days=1), clear_time, tzinfo=clear_timezone
        )
    return (next_clear - now).total_seconds()


async def clear_canvases_daily():
    while True:
        await asyncio.sleep(seconds_until_next_clear(datetime.now(clear_timezone)))
        # set() because users share canvases, and clearing one twice would broadcast twice
        for canvas in set(static_data().canvases_by_user_id.values()):
            canvas.reset()
        print(f"cleared canvases at {datetime.now(clear_timezone)}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if apns_client() is None:
        print("push notifications disabled: no apns_config.json")
    clear_task = asyncio.create_task(clear_canvases_daily())
    yield
    clear_task.cancel()


app = FastAPI(lifespan=lifespan)

# untracked so that tokens stay out of the repo, and so that deploy.sh (which only
# rsyncs git-tracked files) leaves the deployed copy alone
static_data_path = Path(__file__).parent / "static_data.json"


@dataclass(kw_only=True, frozen=True)
class StaticData:
    user_ids_by_token: dict[str, str]
    canvases_by_user_id: dict[str, CanvasServer]


# validated on load so that every later lookup can index directly: a token whose user
# has no canvas is a mistake in the file, not a case to handle per request
@cache
def static_data() -> StaticData:
    data = json.loads(static_data_path.read_text())
    user_ids_by_token: dict[str, str] = data["userIdsByToken"]
    canvas_ids_by_user_id: dict[str, str] = data["canvasIdsByUserId"]

    unassigned = set(user_ids_by_token.values()) - set(canvas_ids_by_user_id)
    if unassigned:
        raise ValueError(f"users with a token but no canvas: {sorted(unassigned)}")

    canvases: dict[str, CanvasServer] = {
        canvas_id: DistributedStateMachineServer(initial_state=[], reduce=reduce_canvas)
        for canvas_id in set(canvas_ids_by_user_id.values())
    }
    return StaticData(
        user_ids_by_token=user_ids_by_token,
        canvases_by_user_id={
            user_id: canvases[canvas_id]
            for user_id, canvas_id in canvas_ids_by_user_id.items()
        },
    )


def authenticated_user_id(authorization: str | None) -> str | None:
    if authorization is None or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ")
    user_ids = static_data().user_ids_by_token
    if token not in user_ids:
        return None
    return user_ids[token]


# derived per connection rather than stored, because static data never changes and the
# number of users sharing a canvas is small
def other_user_ids_sharing_canvas(user_id: str) -> frozenset[str]:
    canvases = static_data().canvases_by_user_id
    canvas = canvases[user_id]
    return frozenset(
        other_user_id
        for other_user_id, other_canvas in canvases.items()
        if other_canvas is canvas and other_user_id != user_id
    )


@app.websocket("/canvas")
async def canvas_handler(
    websocket: WebSocket,
    device_id: Annotated[str, Query(alias="deviceId")],
    authorization: Annotated[str | None, Header()] = None,
):
    # closing before accept makes the handshake fail with HTTP 403, which the client
    # reads as "this token is bad" and stops retrying
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        await websocket.close(code=4001, reason="unauthenticated")
        return
    canvas = static_data().canvases_by_user_id[user_id]

    await websocket.accept()

    def canvas_subscriber(
        *,
        state: list[Placement],
        greatest_seen_device_sequence_numbers: dict[str, int],
    ):
        msg = serialize_server_message(
            state=state,
            greatest_seen_device_sequence_number=greatest_seen_device_sequence_numbers.get(
                device_id, 0
            ),
            serialize_state=placements_to_json,
        )
        asyncio.create_task(websocket.send_json(msg))

    notification = PlacementNotification(
        placer_user_id=user_id,
        recipient_user_ids=other_user_ids_sharing_canvas(user_id),
    )

    unsubscribe = canvas.subscribe(canvas_subscriber, call_on_subscribe=True)
    try:
        while True:
            data = await websocket.receive_json()
            actions = deserialize_client_message(
                data, deserialize_action=action_from_json
            )
            # safe to hold across the call because reducing replaces the state rather
            # than mutating it
            before = canvas.state
            canvas.process_actions(actions, device_id=device_id)

            if notification.recipient_user_ids:
                for emoji in placed_emojis(before=before, after=canvas.state):
                    placement_coalescer().add(key=notification, event=emoji)
    except WebSocketDisconnect:
        pass
    finally:
        unsubscribe()


class DeviceTokenBody(BaseModel):
    device_token: str = Field(alias="deviceToken")


@app.post("/deviceToken")
async def register_device_token(
    body: DeviceTokenBody, authorization: Annotated[str | None, Header()] = None
):
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401)
    device_token_registry().register(user_id=user_id, device_token=body.device_token)


@app.get("/login")
async def login(authorization: Annotated[str | None, Header()] = None):
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401)
    return {"userId": user_id}


# TODO: remove
@app.get("/inspect")
async def inspect_canvas(authorization: Annotated[str | None, Header()] = None):
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401)
    canvas = static_data().canvases_by_user_id[user_id]
    data = {
        "placements": placements_to_json(canvas.state),
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
    return Response(
        content=json.dumps(data, indent=2, ensure_ascii=False),
        media_type="application/json; charset=utf-8",
    )
