import asyncio
import json
from contextlib import asynccontextmanager
from datetime import UTC, datetime, time, timedelta
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
from canvas_notifications import placed_emojis, placement_notifier
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
from users import user_configs_by_user_id

type CanvasServer = DistributedStateMachineServer[list[Placement], Action]

clear_timezone = ZoneInfo("America/New_York")
clear_time = time(hour=2)

saved_canvases_path = Path(__file__).parent / "saved_canvases"


def seconds_until_next_clear(now: datetime) -> float:
    next_clear = datetime.combine(now.date(), clear_time, tzinfo=clear_timezone)
    if next_clear <= now:
        next_clear = datetime.combine(
            now.date() + timedelta(days=1), clear_time, tzinfo=clear_timezone
        )
    return (next_clear - now).total_seconds()


def save_canvas(*, canvas_id: str, placements: list[Placement]):
    path = (
        saved_canvases_path / canvas_id / f"{datetime.now(UTC):%Y-%m-%dT%H-%M-%SZ}.json"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(placements_to_json(placements), indent=2, ensure_ascii=False)
    )


async def clear_canvases_daily():
    while True:
        await asyncio.sleep(seconds_until_next_clear(datetime.now(clear_timezone)))
        for canvas_id, canvas in canvas_servers_by_canvas_id().items():
            if canvas.state:
                save_canvas(canvas_id=canvas_id, placements=canvas.state)
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
def canvas_servers_by_canvas_id() -> dict[str, CanvasServer]:
    return {
        user_config.canvas_id: DistributedStateMachineServer(
            initial_state=[], reduce=reduce_canvas
        )
        for user_config in user_configs_by_user_id.values()
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
    canvas_id = user_configs_by_user_id[user_id].canvas_id
    canvas = canvas_servers_by_canvas_id()[canvas_id]

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

    placement_notifier().connected(user_id=user_id)
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

            # comparing before and after rather than reading the actions: a clear a
            # reconnecting client resent changes nothing, and taking the last placement
            # off the canvas empties it just as a clear does
            if before and not canvas.state:
                save_canvas(canvas_id=canvas_id, placements=before)

            placement_notifier().placed(
                placer_user_id=user_id,
                emojis=placed_emojis(before=before, after=canvas.state),
            )
    except WebSocketDisconnect:
        pass
    finally:
        unsubscribe()
        placement_notifier().disconnected(user_id=user_id)


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


@app.get("/inspect")
async def inspect_canvas(authorization: Annotated[str | None, Header()] = None):
    user_id = authenticated_user_id(authorization)
    if user_id is None:
        raise HTTPException(status_code=401)
    canvas = canvas_servers_by_canvas_id()[user_configs_by_user_id[user_id].canvas_id]
    data = {
        "placements": placements_to_json(canvas.state),
        "greatestSeenDeviceSequenceNumbers": canvas.greatest_seen_device_sequence_numbers,
    }
    return Response(
        content=json.dumps(data, indent=2, ensure_ascii=False),
        media_type="application/json; charset=utf-8",
    )
