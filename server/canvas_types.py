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
    id: str


@dataclass(kw_only=True)
class ClearAction:
    pass


@dataclass(kw_only=True)
class Action:
    action: PlacementAction | UndoAction | ClearAction
    sequence_number: int

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        inner = data["action"]

        if "placement" in inner:
            action = PlacementAction(placement=Placement.from_json(inner["placement"]))
        elif "id" in inner:
            action = UndoAction(id=inner["id"])
        else:
            action = ClearAction()

        return cls(action=action, sequence_number=data["sequenceNumber"])
