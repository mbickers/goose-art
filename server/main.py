import asyncio
import json
from contextlib import asynccontextmanager
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

from apple_notifications import apns_config, device_notification_token_registry
from canvas_notifications import (
    PlacementNotificationKey,
    notification_coalescer,
    placed_emojis,
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
from users import other_user_ids_sharing_canvas, user_configs_by_user_id

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
        for canvas in set(canvas_servers_by_user_id().values()):
            canvas.reset()
        print(f"cleared canvases at {datetime.now(clear_timezone)}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    if apns_config() is None:
        print("push notifications disabled: no apns_config.json")
    clear_task = asyncio.create_task(clear_canvases_daily())
    yield
    clear_task.cancel()


app = FastAPI(lifespan=lifespan)

# untracked so that tokens stay out of the repo, and so that deploy.sh (which only
# rsyncs git-tracked files) leaves the deployed copy alone
user_tokens_path = Path(__file__).parent / "user_tokens.json"


# validated on load so that every later lookup can index directly: a token for a user
# who isn't in users.py is a mistake in the file, not a case to handle per request
@cache
def user_ids_by_token() -> dict[str, str]:
    tokens: dict[str, str] = json.loads(user_tokens_path.read_text())
    unknown = set(tokens.values()) - set(user_configs_by_user_id)
    if unknown:
        raise ValueError(f"tokens for unknown users: {sorted(unknown)}")
    return tokens


@cache
def canvas_servers_by_user_id() -> dict[str, CanvasServer]:
    canvas_servers = {
        user_config.canvas_id: DistributedStateMachineServer(
            initial_state=[], reduce=reduce_canvas
        )
        for user_config in user_configs_by_user_id.values()
    }
    return {
        user_id: canvas_servers[user_config.canvas_id]
        for user_id, user_config in user_configs_by_user_id.items()
    }


def authenticated_user_id(authorization: str | None) -> str | None:
    if authorization is None or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ")
    user_ids = user_ids_by_token()
    if token not in user_ids:
        return None
    return user_ids[token]


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
    canvas = canvas_servers_by_user_id()[user_id]

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

    notification_keys = [
        PlacementNotificationKey(
            placer_user_id=user_id, recipient_user_id=recipient_user_id
        )
        for recipient_user_id in sorted(other_user_ids_sharing_canvas(user_id))
    ]

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

            for emoji in placed_emojis(before=before, after=canvas.state):
                for key in notification_keys:
                    notification_coalescer().add(key=key, event=emoji)
    except WebSocketDisconnect:
        pass
    finally:
        unsubscribe()


class DeviceNotificationTokenBody(BaseModel):
    device_notification_token: str = Field(alias="deviceNotificationToken")


@app.post("/deviceNotificationToken")
async def register_device_notification_token(
    body: DeviceNotificationTokenBody,
    authorization: Annotated[str | None, Header()] = None,
):
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401)
    device_notification_token_registry().register(
        user_id=user_id, device_notification_token=body.device_notification_token
    )


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
    canvas = canvas_servers_by_user_id()[user_id]
    data = {
        "placements": placements_to_json(canvas.state),
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
    return Response(
        content=json.dumps(data, indent=2, ensure_ascii=False),
        media_type="application/json; charset=utf-8",
    )
