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


def action_from_json(data: dict[str, Any]) -> Action:
    action_type = data["type"]

    if action_type == "upsert":
        return UpsertAction(placement=Placement.from_json(data["placement"]))
    elif action_type == "remove":
        return RemoveAction(placement_id=data["placementId"])
    elif action_type == "clear":
        return ClearAction()
    else:
        raise ValueError(f"Unknown action type: {action_type}")


def reduce_canvas(state: list[Placement], action: Action) -> list[Placement]:
    match action:
        case UpsertAction(placement=placement):
            # an upserted placement moves to the top of the z-order
            return [p for p in state if p.id != placement.id] + [placement]
        case RemoveAction(placement_id=placement_id):
            return [p for p in state if p.id != placement_id]
        case ClearAction():
            return []


def placements_to_json(placements: list[Placement]) -> list[dict[str, Any]]:
    return [p.to_json() for p in placements]
