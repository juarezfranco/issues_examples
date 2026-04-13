# Bonfire Issue #600 — Oversized tiles & Tiled layer order

Two related bugs in `TiledWorldBuilder` when a Tiled map uses tiles whose
sprite is larger than the map's tile size (e.g. 192×256 trees on a 64×64 map).

![example](https://github.com/juarezfranco/issues_examples/blob/main/bonfire_issue_600/example.gif)

## The projects

- `bug/` — minimal repro on `bonfire: ^3.16.1` (pub).
- `fix/` — same project pointing at the fork with both fixes applied
  (`juarezfranco/bonfire`, branch `bugfix/tiled-oversized-and-layer-order`).

Both projects load the same map (`assets/images/map.json`) with a Pawn
spawning on an `initialPoint` object.

## Bug 1 — Oversized tiles are squished

Any tile larger than the map cell went through the regular tile path in
`_addTileLayer`, which renders every tile with `width = _tileWidth`,
`height = _tileHeight`. A 192×256 tree was drawn inside a 64×64 cell, shrunk
to fit.

The only existing escape hatch was marking a tile as `type=above` or
`type=dynamicAbove`, which extracts it as a `GameDecoration` — but even that
path used the map's tile size for the decoration, so the tree was still
squished, just now as a game-level component.

### Fix

Detect oversized tiles automatically and route them through the
`GameDecoration` path with their **native** size and a bottom-left anchor:

```dart
final nativeSize = data.sprite?.size;
final isOversized = nativeSize != null &&
    (nativeSize.x > _tileWidthOrigin ||
        nativeSize.y > _tileHeightOrigin);
if (tileIsAbove || isDynamic || isOversized) {
  _addGameDecorationAbove(...);
}
```

Inside `_addGameDecorationAbove`:

```dart
final drawW = (nativeSize?.x ?? _tileWidthOrigin) * scaleX;
final drawH = (nativeSize?.y ?? _tileHeightOrigin) * scaleY;
final position = Vector2(
  cellX * _tileWidth,
  (cellY + 1) * _tileHeight - drawH, // bottom-left anchor
);
```

Result: oversized tiles render at the size Tiled shows them, anchored the
way the editor previews them.

## Bug 2 — Layer order ignored after extraction

Fixing Bug 1 surfaced a second problem. Once an oversized tile becomes a
`GameDecoration`, it is added to `_components` and then attached via
`gameRef.addAll(...)`. That makes it a **sibling** of the `WorldMap`, not a
child of it:

```
BonfireGame
├── WorldMap            ← holds all tile layers internally
│   ├── tile layer 0
│   ├── tile layer 1
│   └── tile layer 2
└── GameDecoration      ← sibling of the entire map
```

Flame's priority system only orders siblings within the same parent. A
game-level decoration can be above or below the whole WorldMap, but it can
**never** sit between two tile layers — they live in a different subtree.

Concretely: a water tile on layer 1 and a splash animation on layer 2 would
both be dragged above the terrain on layer 3, because the splash was promoted
to game level and got Y-sorted above the tile map as a block.

### Fix — `type=layered`

New opt-in layer property in Tiled:

```
type=layered
```

When a tile layer has this property, oversized (or otherwise extracted)
decorations from that layer are attached as **children of the WorldMap**
instead of siblings:

```dart
if (layered) {
  comp.priorityOverride = layerIndex;
  _mapDecorations.add(comp); // goes into WorldBuildData.mapChildren
}
```

`WorldMapByTiled.onLoad` then adds each `mapChildren` entry via
`add(child)`, placing them in the same subtree as the tile layers. Now
priority comparisons are meaningful and the decorations interleave with the
regular tile layers following Tiled's natural layer order.

### Why a new flag and not automatic

Making every oversized tile `layered` by default would be a breaking change:
projects that rely on the current behaviour (decorations Y-sorted above the
tile map, player passing behind them) would suddenly see trees pinned to
layer order and the player rendered on top of them.

`type=layered` is opt-in on the layer, so existing maps keep working and
authors explicitly choose when a layer should follow Tiled's stacking.

## Type flags reference

| Tiled marking          | Destination                        | Ordering                                 |
| ---------------------- | ---------------------------------- | ---------------------------------------- |
| *(none)*               | tile layer (if fits) / `_components` | legacy: tile grid / dynamic Y-sort       |
| `type=above`           | `_components` (game-level)         | always above the player (dynamic Y-sort) |
| `type=dynamicAbove`    | `_components` (game-level)         | dynamic Y-sort                           |
| `type=layered` (new)   | `_mapDecorations` (WorldMap child) | follows Tiled layer order                |

## Files touched in the fork

- `lib/map/tiled/builder/tiled_world_builder.dart` — oversized detection,
  native-size rendering, `LAYERED_TYPE` routing.
- `lib/map/tiled/model/tiled_world_data.dart` — added `mapChildren`.
- `lib/map/tiled/world_map_by_tiled.dart` — attaches `mapChildren` as
  children of the `WorldMap`.
- `lib/base/game_component.dart` — added `priorityOverride` so layered
  decorations can pin to a fixed priority instead of the default Y-sort.
