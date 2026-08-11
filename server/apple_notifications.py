import asyncio
import json
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any

from aioapns import APNs, NotificationRequest, PushType

# untracked for the same reasons as static_data.json: the signing key stays out of the
# repo, and deploy.sh (which only rsyncs git-tracked files) leaves the deployed copy alone
apns_config_path = Path(__file__).parent / "apns_config.json"
device_notification_tokens_path = (
    Path(__file__).parent / "device_notification_tokens.json"
)

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
class DeviceNotificationTokenRegistry:
    def __init__(self, *, path: Path):
        self.path = path
        self.device_notification_tokens_by_user_id: dict[str, set[str]] = (
            {
                user_id: set(device_notification_tokens)
                for user_id, device_notification_tokens in json.loads(
                    path.read_text()
                ).items()
            }
            if path.exists()
            else {}
        )

    def register(self, *, user_id: str, device_notification_token: str):
        self.device_notification_tokens_by_user_id = {
            other_user_id: device_notification_tokens - {device_notification_token}
            for other_user_id, device_notification_tokens in self.device_notification_tokens_by_user_id.items()
        } | {
            user_id: self.device_notification_tokens_for(user_id=user_id)
            | {device_notification_token},
        }
        self.save()

    def discard(self, *, device_notification_token: str):
        self.device_notification_tokens_by_user_id = {
            user_id: device_notification_tokens - {device_notification_token}
            for user_id, device_notification_tokens in self.device_notification_tokens_by_user_id.items()
        }
        self.save()

    def device_notification_tokens_for(self, *, user_id: str) -> set[str]:
        if user_id not in self.device_notification_tokens_by_user_id:
            return set()
        return set(self.device_notification_tokens_by_user_id[user_id])

    def save(self):
        self.path.write_text(
            json.dumps(
                {
                    user_id: sorted(device_notification_tokens)
                    for user_id, device_notification_tokens in self.device_notification_tokens_by_user_id.items()
                    if device_notification_tokens
                },
                indent=2,
            )
        )


@cache
def device_notification_token_registry() -> DeviceNotificationTokenRegistry:
    return DeviceNotificationTokenRegistry(path=device_notification_tokens_path)


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


async def send_push(*, user_id: str, body: str):
    client = apns_client()
    if client is None:
        return

    registry = device_notification_token_registry()
    device_notification_tokens = sorted(
        registry.device_notification_tokens_for(user_id=user_id)
    )
    results = await asyncio.gather(
        *[
            client.send_notification(
                NotificationRequest(
                    device_token=device_notification_token,
                    message={"aps": {"alert": {"body": body}, "sound": "default"}},
                    push_type=PushType.ALERT,
                )
            )
            for device_notification_token in device_notification_tokens
        ],
        return_exceptions=True,
    )

    for device_notification_token, result in zip(device_notification_tokens, results):
        if isinstance(result, BaseException):
            print(f"push failed: {result}")
        elif not result.is_successful:
            print(f"push rejected: {result.description}")
            if result.description in dead_token_reasons:
                registry.discard(device_notification_token=device_notification_token)
