# Architecture Wizard Tower Technical Plan

This document lists the engine/editor work needed to make
[`ARCHITECTURE_WIZARD_TOWER_SCENARIO.md`](ARCHITECTURE_WIZARD_TOWER_SCENARIO.md)
possible without generic mesh editing.

The goal is not a one-off wizard tower generator. The goal is a semantic
Architecture workflow that can author tall, irregular fantasy buildings quickly:
round footprints, floors, curved stairs, projecting turret rooms, conical roofs,
openings, materials, collision, and save/reload.

## Product Requirements

- Architecture mode has task-level UX: Display, Plan, Build, Roof, Materials.
- Users can create round or near-round tower footprints.
- Users can create multi-floor buildings from one footprint.
- Users can add curved or spiral stairs that connect floor elevations.
- Users can attach bartizans or small turret rooms to upper floors.
- Users can apply conical roofs to circular/polygonal footprints.
- Doors and windows work on curved or segmented walls.
- Materials can be assigned by architectural role.
- Generated geometry, collision, and saved data all derive from the same
  semantic building model.

## Data Model Work

Extend the semantic building model in `src/runtime/shared/architecture.zig` or a
nearby architecture document module.

Required concepts:

- **Building**
  - Stable id.
  - Footprint vertices and wall segments.
  - Floor definitions.
  - Openings.
  - Roof definitions.
  - Attached features.
  - Material slots.

- **Floor**
  - Index.
  - Base height.
  - Height.
  - Optional floor slab thickness.
  - Optional display name.

- **Curved footprint**
  - Store as a polygon with enough radial segments for editing.
  - Preserve semantic intent such as `circle`, `radial_polygon`, or `custom`
    when possible.
  - Keep generated wall segments editable.

- **Stair**
  - Kind: straight, curved, spiral.
  - Start floor and end floor.
  - Center, radius, width, start angle, sweep angle.
  - Step count or rise/run.
  - Direction: clockwise or counter-clockwise.
  - Optional landing points.

- **Bartizan**
  - Parent building id.
  - Attachment wall or attachment point on footprint.
  - Floor index or vertical range.
  - Projection distance.
  - Radius/width/depth.
  - Local footprint.
  - Roof reference.

- **Roof**
  - Kind: flat, shed, gable, hip, conical, custom.
  - Target: whole building, floor/level, bartizan, or named footprint region.
  - Pitch or height.
  - Overhang.
  - Ridge/axis where relevant.
  - Apex position for conical roofs.
  - Material slot.

- **Material slots**
  - Walls.
  - Roof.
  - Floors.
  - Trim.
  - Stairs.
  - Door/window frames.

## Scene Persistence

Save semantic data, not only baked mesh triangles.

Needed save/load behavior:

- Round tower footprint reloads as editable footprint/walls.
- Floor count and heights reload.
- Curved stairs reload with editable parameters.
- Bartizans reload attached to the same floor/wall.
- Conical roofs reload as roof definitions.
- Doors/windows reload attached to wall segments.
- Material slots reload and regenerate mesh materials.

Validation should fail loudly for:

- Stair endpoints with missing floors.
- Bartizan attached to a missing wall/floor.
- Roof target that no longer exists.
- Conical roof with too few footprint points.
- Openings outside wall segment bounds.
- Self-crossing footprint.

## Mesh Generation

Architecture mesh generation should support:

- Circular/radial wall segments from polygon footprints.
- Multi-floor wall bands.
- Floor slabs for each level.
- Curved or spiral stair mesh with readable treads.
- Bartizan wall/floor meshes attached to the tower.
- Conical roof mesh from circular or polygon footprint.
- Smaller conical roof meshes for bartizans.
- Door/window cutouts on segmented tower walls.
- Trim meshes around openings if available.

Conical roof generation:

1. Resolve target footprint loop.
2. Offset footprint outward by overhang.
3. Compute apex:
   - Default at footprint centroid.
   - Height from pitch or explicit roof height.
4. Emit triangles from each footprint edge to apex.
5. Add underside/edge cap if needed for readability.
6. Assign roof material slot.

Stair generation:

1. Resolve start/end floor heights.
2. Compute total rise.
3. Derive step count from target riser height.
4. Sweep around center by configured angle.
5. Emit treads and optional central column/rail preview.
6. Validate that stairs fit inside the footprint or warn visibly.

## Collision And Playtest

The scenario is not complete if the tower only looks correct.

Needed collision behavior:

- Tower walls block the player.
- Door openings are passable.
- Floor slabs are walkable.
- Stairs are walkable enough for playtest.
- Windows are visual openings, and collision matches the intended window state.
- Roofs can be visual-only initially, but unsupported collision should be clear.

Fail-fast cases:

- Missing collision for floor slabs.
- Doorway visible but blocked by collision.
- Stairs visible but not walkable when playtest says they should be.

## Editor UX Work

Architecture mode should expose a coherent building workflow.

Recommended top strip:

- Display
- Plan
- Build
- Roof
- Materials

Plan mode:

- Rectangle footprint.
- Polygon footprint.
- Round tower footprint.
- Add wing.
- Close footprint.
- Edit footprint points.
- Show dimensions, segment count, and close hint.

Build mode:

- Floor count.
- Floor height.
- Wall thickness.
- Split wall.
- Push/pull wall.
- Add tower/bartizan.
- Add stairs.
- Add door/window shortcuts.

Roof mode:

- Roof target picker: main tower, bartizan 1, bartizan 2.
- Presets: flat, shed, gable, hip, conical, custom.
- Pitch/height.
- Overhang.
- Apex/center handle for conical roofs.
- Clear roof.
- Validation messages in the panel and bottom strip.

Materials mode:

- Wall material slot.
- Roof material slot.
- Floor material slot.
- Trim material slot.
- Stair material slot.
- Optional face paint escape hatch.

Display mode:

- Orbit/zoom.
- Lighting presets.
- Toggle overlays: floors, roof handles, openings, stairs, collision.

## Editor Commands

Add command/control coverage so the scenario can be run by tools.

Candidate commands:

- `architecture.new-building`
- `architecture.footprint-round`
- `architecture.footprint-point`
- `architecture.footprint-close`
- `architecture.floor-count`
- `architecture.floor-height`
- `architecture.add-stairs`
- `architecture.add-bartizan`
- `architecture.add-opening`
- `architecture.roof-preset`
- `architecture.roof-cone`
- `architecture.roof-target`
- `architecture.material-slot`
- `architecture.display-mode`

Each command should return JSON with:

- `ok`
- `command`
- relevant object/building id
- changed semantic values
- status text
- validation errors when applicable

## Viewport Overlays

Needed overlays:

- Footprint points and closed-loop preview.
- Round footprint segment preview.
- Wall height/floor bands.
- Floor labels: `1`, `2`, `3`.
- Stair start/end markers and climb direction.
- Bartizan attachment preview.
- Roof footprint, overhang outline, apex, and pitch guide.
- Door/window cut previews.
- Collision preview for floor/wall/stair.

Avoid showing authored-looking geometry for mere hints unless the panel clearly
labels it as a preview.

## Suggested Implementation Slices

### Slice 1: UX Shell

- Add Architecture submodes: Display, Plan, Build, Roof, Materials.
- Reorganize left panel into step-based tasks.
- Add roof-focused controls even if initially limited to existing roof presets.
- Add screenshot scenario notes.

Verify:

```sh
zig build test
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"screenshot_editor","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
```

### Slice 2: Round Tower Footprints

- Add radial polygon footprint creation.
- Store the footprint as semantic building data.
- Generate segmented tower walls.
- Add command coverage for round footprints.

Verify:

```sh
zig build test
./zig-out/bin/friendly_engine_tools architecture.footprint-round
```

### Slice 3: Multi-Floor Buildings

- Add floor count and floor height to building data.
- Generate floor slabs and multi-floor wall bands.
- Add floor labels/overlays.
- Save/reload floors.

Verify:

```sh
zig build test
./zig-out/bin/friendly_engine_tools architecture.floor-count 3
```

### Slice 4: Conical Roofs

- Add `conical` roof kind.
- Generate conical roof mesh from target footprint.
- Add roof target selection for main tower and features.
- Save/reload conical roofs.

Verify:

```sh
zig build test
./zig-out/bin/friendly_engine_tools architecture.roof-cone
```

### Slice 5: Curved Stairs

- Add stair semantic data.
- Generate curved/spiral stair mesh.
- Connect start/end floors.
- Add collision or explicit visual-only validation.

Verify:

```sh
zig build test
./zig-out/bin/friendly_engine_tools architecture.add-stairs
```

### Slice 6: Bartizans

- Add attached feature data for bartizans.
- Generate projecting turret rooms.
- Attach to floor/wall.
- Add smaller conical roof target.
- Save/reload.

Verify:

```sh
zig build test
./zig-out/bin/friendly_engine_tools architecture.add-bartizan
```

### Slice 7: Full Scenario Smoke

- Run the complete wizard tower scenario.
- Capture plan/build/roof/display screenshots.
- Save/reload.
- Playtest from tower entrance.

Verify:

```sh
zig build test
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"screenshot_editor","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"perf_describe","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
```

## Open Questions

- Should bartizans be stored as building features or as child buildings attached
  to a parent building?
- Should conical roofs support an off-center apex for crooked fantasy roofs?
- Should spiral stairs be part of Architecture mode or reusable Prop assets with
  semantic floor connectors?
- How exact does curved-wall door/window cutting need to be for the first pass?
- Should roof collision exist immediately, or should roofs begin as visual-only
  with a clear validation label?
