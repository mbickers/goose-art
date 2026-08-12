#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["websockets"]
# ///

# Places one emoji on a user's canvas, the same way the app would, for testing the
# server without a device: `./place_emoji.py "dev user 1"`.

import argparse
import asyncio
import json
import random
import uuid
from pathlib import Path
from typing import Any

import websockets

from canvas_types import Placement, Position

pumpkin = "🎃"
# matches the size the app drops a placement at, and keeps it clear of the edges
placement_scale = 0.3
placement_position_range = (0.15, 0.85)
confirmation_timeout = 10.0

user_tokens_path = Path(__file__).parent / "user_tokens.json"


def token_for(*, user_id: str) -> str:
    user_ids_by_token: dict[str, str] = json.loads(user_tokens_path.read_text())
    tokens = [
        token
        for token, token_user_id in user_ids_by_token.items()
        if token_user_id == user_id
    ]
    if not tokens:
        known = sorted(set(user_ids_by_token.values()))
        raise SystemExit(
            f"no token for {user_id!r} in {user_tokens_path.name}: {known}"
        )
    return tokens[0]


def random_placement(*, emoji: str) -> Placement:
    return Placement(
        id=str(uuid.uuid4()),
        emoji=emoji,
        position=Position(
            x=random.uniform(*placement_position_range),
            y=random.uniform(*placement_position_range),
        ),
        scale=placement_scale,
        rotation=0.0,
        is_mirrored=False,
    )


def upsert_message(*, placement: Placement) -> dict[str, Any]:
    return {
        "actions": [
            {
                "action": {"type": "upsert", "placement": placement.to_json()},
                # 1 is always accepted because each run invents a device id, so the
                # server has no earlier sequence number for it
                "deviceSequenceNumber": 1,
            }
        ]
    }


async def place(*, base_url: str, user_id: str, emoji: str):
    url = base_url.replace("https://", "wss://").replace("http://", "ws://")
    placement = random_placement(emoji=emoji)

    async with websockets.connect(
        f"{url}/canvas?deviceId={uuid.uuid4()}",
        additional_headers={"Authorization": f"Bearer {token_for(user_id=user_id)}"},
    ) as websocket:
        await websocket.send(json.dumps(upsert_message(placement=placement)))

        # the server broadcasts the whole canvas on every change, so waiting for the
        # placement to come back is what proves it was accepted rather than dropped
        async with asyncio.timeout(confirmation_timeout):
            async for message in websocket:
                state = [
                    Placement.from_json(data) for data in json.loads(message)["state"]
                ]
                if any(p.id == placement.id for p in state):
                    print(f"{user_id} placed {emoji} ({len(state)} on the canvas)")
                    return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("user_id", help="a user in user_tokens.json, e.g. 'dev user 1'")
    parser.add_argument("--emoji", default=pumpkin)
    parser.add_argument("--base-url", default="https://goose-art.maxbickers.com")
    args = parser.parse_args()

    asyncio.run(place(base_url=args.base_url, user_id=args.user_id, emoji=args.emoji))


if __name__ == "__main__":
    main()
