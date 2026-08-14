from dataclasses import dataclass


@dataclass(kw_only=True, frozen=True)
class UserConfig:
    canvas_id: str
    # debug builds register with the APNs sandbox and release builds with production, so
    # this follows how the user's app was built rather than which canvas they are on
    use_sandbox_notifications: bool


# hardcoded because a new user needs a token handed out by hand anyway, so there is
# nothing a config file would let us change without a deploy
user_configs_by_user_id = {
    "max": UserConfig(canvas_id="prod", use_sandbox_notifications=False),
    "brian": UserConfig(canvas_id="prod", use_sandbox_notifications=False),
    "dev user 1": UserConfig(canvas_id="dev", use_sandbox_notifications=True),
    "dev user 2": UserConfig(canvas_id="dev", use_sandbox_notifications=True),
}


def other_user_ids_sharing_canvas(user_id: str) -> frozenset[str]:
    canvas_id = user_configs_by_user_id[user_id].canvas_id
    return frozenset(
        other_user_id
        for other_user_id, other_user_config in user_configs_by_user_id.items()
        if other_user_config.canvas_id == canvas_id and other_user_id != user_id
    )
