from dataclasses import dataclass
from typing import Any, Self


@dataclass(kw_only=True)
class Position:
    x: float
    y: float

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        return cls(x=data["x"], y=data["y"])


@dataclass(kw_only=True)
class Placement:
    id: str
    emoji: str
    position: Position
    scale: float
    rotation: float
    is_mirrored: bool

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "emoji": self.emoji,
            "position": {"x": self.position.x, "y": self.position.y},
            "scale": self.scale,
            "rotation": self.rotation,
            "isMirrored": self.is_mirrored,
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        return cls(
            id=data["id"],
            emoji=data["emoji"],
            position=Position.from_json(data["position"]),
            scale=data["scale"],
            rotation=data["rotation"],
            is_mirrored=data["isMirrored"],
        )


@dataclass(kw_only=True)
class UpsertAction:
    placement: Placement


@dataclass(kw_only=True)
class RemoveAction:
    placement_id: str


@dataclass(kw_only=True)
class ClearAction:
    pass


Action = UpsertAction | RemoveAction | ClearAction


@dataclass(kw_only=True)
class SequencedAction:
    action: UpsertAction | RemoveAction | ClearAction
    device_sequence_number: int

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        inner = data["action"]
        action_type = inner["type"]

        if action_type == "upsert":
            action = UpsertAction(placement=Placement.from_json(inner["placement"]))
        elif action_type == "remove":
            action = RemoveAction(placement_id=inner["placementId"])
        elif action_type == "clear":
            action = ClearAction()
        else:
            raise ValueError(f"Unknown action type: {action_type}")

        return cls(action=action, device_sequence_number=data["deviceSequenceNumber"])
