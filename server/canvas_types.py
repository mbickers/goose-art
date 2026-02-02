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
    user_id: str

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "emoji": self.emoji,
            "position": {"x": self.position.x, "y": self.position.y},
            "scale": self.scale,
            "rotation": self.rotation,
            "isMirrored": self.is_mirrored,
            "userId": self.user_id,
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
            user_id=data["userId"],
        )


@dataclass(kw_only=True)
class PlacementAction:
    placement: Placement


@dataclass(kw_only=True)
class UndoAction:
    placement_id: str


@dataclass(kw_only=True)
class ClearAction:
    pass


Action = PlacementAction | UndoAction | ClearAction


@dataclass(kw_only=True)
class SequencedAction:
    action: PlacementAction | UndoAction | ClearAction
    device_sequence_number: int

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        inner = data["action"]
        action_type = inner["type"]

        if action_type == "place":
            action = PlacementAction(placement=Placement.from_json(inner["placement"]))
        elif action_type == "undo":
            action = UndoAction(placement_id=inner["placementId"])
        elif action_type == "clear":
            action = ClearAction()
        else:
            raise ValueError(f"Unknown action type: {action_type}")

        return cls(action=action, device_sequence_number=data["deviceSequenceNumber"])
