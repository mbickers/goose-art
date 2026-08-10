import asyncio
import json
from collections.abc import Coroutine
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any, Protocol

from aioapns import APNs, NotificationRequest, PushType

# untracked for the same reasons as static_data.json: the signing key stays out of the
# repo, and deploy.sh (which only rsyncs git-tracked files) leaves the deployed copy alone
apns_config_path = Path(__file__).parent / "apns_config.json"
device_tokens_path = Path(__file__).parent / "device_tokens.json"

# tokens APNs rejects permanently, as opposed to a transient send failure worth retrying
dead_token_reasons = {"BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"}


@dataclass(kw_only=True, frozen=True)
class ApnsConfig:
    key: str
    key_id: str
    team_id: str
    bundle_id: str
    # debug builds register against APNs sandbox and release builds against production;
    # sending to the wrong one is silently dropped rather than reported as an error
    use_sandbox: bool

    @classmethod
    def from_json(cls, data: dict[str, Any], *, directory: Path):
        return cls(
            key=(directory / data["keyPath"]).read_text(),
            key_id=data["keyId"],
            team_id=data["teamId"],
            bundle_id=data["bundleId"],
            use_sandbox=data["useSandbox"],
        )


# a device belongs to one user at a time: registering moves it, so that logging in as
# someone else on a shared device stops delivering the previous user's notifications
class DeviceTokenRegistry:
    def __init__(self, *, path: Path):
        self.path = path
        self.device_tokens_by_user_id: dict[str, set[str]] = (
            {
                user_id: set(device_tokens)
                for user_id, device_tokens in json.loads(path.read_text()).items()
            }
            if path.exists()
            else {}
        )

    def register(self, *, user_id: str, device_token: str):
        self.device_tokens_by_user_id = {
            other_user_id: device_tokens - {device_token}
            for other_user_id, device_tokens in self.device_tokens_by_user_id.items()
        } | {
            user_id: self.device_tokens_for(user_ids=[user_id]) | {device_token},
        }
        self.save()

    def discard(self, *, device_token: str):
        self.device_tokens_by_user_id = {
            user_id: device_tokens - {device_token}
            for user_id, device_tokens in self.device_tokens_by_user_id.items()
        }
        self.save()

    def device_tokens_for(self, *, user_ids: list[str]) -> set[str]:
        return {
            device_token
            for user_id in user_ids
            if user_id in self.device_tokens_by_user_id
            for device_token in self.device_tokens_by_user_id[user_id]
        }

    def save(self):
        self.path.write_text(
            json.dumps(
                {
                    user_id: sorted(device_tokens)
                    for user_id, device_tokens in self.device_tokens_by_user_id.items()
                    if device_tokens
                },
                indent=2,
            )
        )


@cache
def device_token_registry() -> DeviceTokenRegistry:
    return DeviceTokenRegistry(path=device_tokens_path)


# None when the config file is absent, so that a local server runs without APNs
# credentials. main.py reports which mode it started in.
@cache
def apns_client() -> APNs | None:
    if not apns_config_path.exists():
        return None
    config = ApnsConfig.from_json(
        json.loads(apns_config_path.read_text()), directory=apns_config_path.parent
    )
    return APNs(
        key=config.key,
        key_id=config.key_id,
        team_id=config.team_id,
        topic=config.bundle_id,
        use_sandbox=config.use_sandbox,
    )


async def send_push(*, user_ids: list[str], body: str):
    client = apns_client()
    if client is None:
        return

    registry = device_token_registry()
    device_tokens = sorted(registry.device_tokens_for(user_ids=user_ids))
    results = await asyncio.gather(
        *[
            client.send_notification(
                NotificationRequest(
                    device_token=device_token,
                    message={"aps": {"alert": {"body": body}, "sound": "default"}},
                    push_type=PushType.ALERT,
                )
            )
            for device_token in device_tokens
        ],
        return_exceptions=True,
    )

    for device_token, result in zip(device_tokens, results):
        if isinstance(result, BaseException):
            print(f"push failed: {result}")
        elif not result.is_successful:
            print(f"push rejected: {result.description}")
            if result.description in dead_token_reasons:
                registry.discard(device_token=device_token)


class CoalescedFlush[Key, Event](Protocol):
    def __call__(self, *, key: Key, events: list[Event]) -> Coroutine[Any, Any, None]:
        pass


# batches events sharing a key into one flush. the window is anchored at the first event
# of a batch rather than extended by later ones, so a steady stream of events still
# delivers on a bounded delay instead of being held back indefinitely.
class Coalescer[Key, Event]:
    def __init__(self, *, delay: float, flush: CoalescedFlush[Key, Event]):
        self.delay = delay
        self.flush = flush
        self.pending_events: dict[Key, list[Event]] = {}
        # held so that in-flight batches aren't garbage collected mid-wait
        self.flush_tasks: dict[Key, asyncio.Task] = {}

    def add(self, *, key: Key, event: Event):
        if key in self.pending_events:
            self.pending_events[key].append(event)
            return
        self.pending_events[key] = [event]
        self.flush_tasks[key] = asyncio.create_task(self.flush_after_delay(key=key))

    async def flush_after_delay(self, *, key: Key):
        await asyncio.sleep(self.delay)
        events = self.pending_events.pop(key)
        del self.flush_tasks[key]
        await self.flush(key=key, events=events)
