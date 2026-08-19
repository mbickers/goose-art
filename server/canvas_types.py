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
class CanvasState:
    title: str
    placements: list[Placement]

    def to_json(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "placements": [placement.to_json() for placement in self.placements],
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Self:
        return cls(
            title=data["title"],
            placements=[Placement.from_json(p) for p in data["placements"]],
        )


def empty_canvas() -> CanvasState:
    return CanvasState(title="", placements=[])


@dataclass(kw_only=True)
class UpsertAction:
    placement: Placement
    behind_id: str | None


@dataclass(kw_only=True)
class RemoveAction:
    placement_id: str


@dataclass(kw_only=True)
class SetTitleAction:
    title: str


@dataclass(kw_only=True)
class ClearAction:
    pass


Action = UpsertAction | RemoveAction | SetTitleAction | ClearAction


def action_from_json(data: dict[str, Any]) -> Action:
    action_type = data["type"]

    if action_type == "upsert":
        # clients before layer ordering send no behindId, meaning the top
        return UpsertAction(
            placement=Placement.from_json(data["placement"]),
            behind_id=data.get("behindId"),
        )
    elif action_type == "remove":
        return RemoveAction(placement_id=data["placementId"])
    elif action_type == "setTitle":
        return SetTitleAction(title=data["title"])
    elif action_type == "clear":
        return ClearAction()
    else:
        raise ValueError(f"Unknown action type: {action_type}")


def reduce_canvas(state: CanvasState, action: Action) -> CanvasState:
    match action:
        case UpsertAction(placement=placement, behind_id=behind_id):
            # an upserted placement lands directly behind behind_id, or on top of
            # the z-order when there is no such placement
            others = [p for p in state.placements if p.id != placement.id]
            index = next(
                (i for i, p in enumerate(others) if p.id == behind_id), len(others)
            )
            return CanvasState(
                title=state.title,
                placements=others[:index] + [placement] + others[index:],
            )
        case RemoveAction(placement_id=placement_id):
            return CanvasState(
                title=state.title,
                placements=[p for p in state.placements if p.id != placement_id],
            )
        case SetTitleAction(title=title):
            return CanvasState(title=title, placements=state.placements)
        case ClearAction():
            return empty_canvas()
