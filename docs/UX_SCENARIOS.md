# UX Scenarios

This document records repeatable editor scenarios for playtesting UX changes.
Run a scenario before and after a focused change, compare the notes, then repeat.

The goal is not to prove the editor works once. The goal is to make the same
workflow easier, clearer, and faster over time.

For LLM-executed authoring loops, prefer markdown MCP scenarios under
`scenarios/`. See `MCP_SCENARIOS.md` for the scenario contract. Those scenarios
are executable briefs that call MCP tools; they should not be replaced by
bespoke procedural Zig generators.

## How To Run A Scenario

1. Start from a clean project or a named fixture project.
2. Record the date, build, platform, renderer, and scenario version.
3. Run the steps exactly enough to compare runs, but note any natural shortcuts.
4. Capture the editor state at important checkpoints.
5. Record friction while it is fresh.
6. Pick one or two improvements for the next loop.
7. Run the same scenario again after the change.

Use editor control for visual proof when the editor is running:

```sh
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"screenshot_editor","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"screenshot_viewport","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
printf '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"perf_describe","arguments":{}}}\n' | ./zig-out/bin/friendly_engine_mcp
```

Prefer those outputs over OS-level screenshots. Store notes in the run log below
or copy the template into a dated issue or work note.

## Scenario Format

Each scenario should include:

- **Intent**: what user outcome the scenario represents.
- **Starting state**: project, scene, renderer, and any fixtures.
- **Loop trigger**: what kind of code or design change should rerun it.
- **Steps**: the human actions to perform.
- **Pass conditions**: observable signs that the UX is good enough for this run.
- **Friction prompts**: questions to answer while testing.
- **Artifacts**: screenshots, diagnostics, scene files, or notes to keep.

## Architecture Mode: House Blockout To Playtest

**Scenario id**: `architecture-house-blockout-playtest`

**Version**: 1

**Intent**: A user can create a simple playable house from an empty scene using
Architecture mode, then immediately test it with a basic FPS-style controller.

**Starting state**:

- Use the current `friendly-engine` project.
- Start in the editor with no special fixtures.
- Use the GPU editor path when available; use `--software` only when GPU is not
  usable on the test machine.
- Begin from a new scene named `architecture_mode_house_loop` or another clearly
  disposable scene name.

**Loop trigger**:

Rerun this scenario after changes to Architecture mode, blockout geometry,
local CSG, face editing, material application, physics authoring, gameplay
spawners, play-in-editor, scene save/load, or viewport tool hints.

### Steps

1. Create a new scene.
   - Expected: the editor makes the scene without requiring file-system knowledge.
   - Capture: full editor screenshot after the blank scene opens.

2. Create a new ground plane with collision.
   - Expected: the ground is visible, selected, named clearly, and has an obvious
     collision state in the inspector.
   - Capture: viewport screenshot and any physics/collision inspector state.

3. Create a house floorplan by drawing cells as 2D shapes in the 3D world.
   - Draw at least four rooms: entry, living room, bedroom, and bathroom.
   - Expected: drawing happens on the grid with snap feedback and readable room
     boundaries before committing.
   - Note whether the tool feels like drawing a floorplan or placing unrelated
     boxes.

4. Extrude the floorplan into rooms.
   - Expected: room walls rise from the floorplan in one clear action or a small
     number of obvious actions.
   - Check that wall height is visible and editable.
   - Capture: viewport screenshot from outside and inside the rooms.

5. Cut doors and windows.
   - Add at least one exterior door, two interior doors, and two windows.
   - Expected: openings cut through the correct walls, remain editable, and make
     collision openings that match the visible geometry.
   - Note whether door/window placement needs tool switching, inspector hunting,
     or camera gymnastics.

6. Add a roof.
   - Expected: the roof aligns to the wall footprint, is visible from outside,
     and does not block interior navigation unless intentionally configured.
   - Note whether roof creation feels like an Architecture task or a generic mesh
     workaround.

7. Create a new spawner for a basic FPS-style player controller.
   - Place the spawner near the entry.
   - Expected: the spawner has a clear type, orientation, and controller binding.
   - Check that invalid setup fails loudly, for example missing controller or
     collision settings.

8. Run the game and allow the tester to play.
   - Expected: play starts from the spawner, walking collides with the ground and
     walls, doors are passable, windows are visibly openings, and the exit path
     from play mode is obvious.
   - Capture: viewport/editor screenshot before play and diagnostics after play
     starts if available.

9. Quit the game and report progress.
   - Expected: quitting returns to the editor with the scene intact and no hidden
     mode state.
   - Record what worked, what blocked progress, and what felt slow.

10. Improve one or two things, then repeat the same scenario.
    - Expected: the next run has fewer blockers or less friction in the same
      steps, not just a different workaround.

### Pass Conditions

- A tester can complete the scenario without editing KDL or source files by hand.
- The scene can be saved, closed, reopened, and still has editable Architecture
  intent.
- The visible house roughly matches the collision used in play mode.
- The tester always knows the active tool, selected object, snap/grid state, and
  whether they are editing or playing.
- Failures identify the object, tool, or missing setup that caused them.

### Friction Prompts

- Which step first required guessing?
- Which step required the most camera movement?
- Which action needed more than one undo to recover?
- Which controls felt generic instead of Architecture-specific?
- Which state was invisible until it failed?
- Which labels were unclear, too long, or too far from the thing they controlled?
- Which action should become a single command, preset, or direct-manipulation
  gesture?

### Metrics

Record these when practical:

- Time to create the blank scene.
- Time to create ground with collision.
- Time to finish the first closed floorplan.
- Time from floorplan to walkable rooms.
- Number of undo operations.
- Number of times the tester opened the wrong panel or tool.
- Number of play attempts before spawning inside the house successfully.
- Any editor errors, validation messages, or crashes.

### Artifacts

Keep or link:

- Editor screenshot after the blank scene opens.
- Viewport screenshot after ground creation.
- Viewport screenshot after floorplan drawing.
- Viewport screenshots after extrusion and openings.
- Viewport screenshot after roof placement.
- Screenshot or note showing the spawner configuration.
- `perf_describe` MCP output during editing and, if available, during play.
- Saved scene file path.

## Architecture Mode: Wizard Tower

**Scenario id**: `architecture-wizard-tower`

The full scenario lives in
[ARCHITECTURE_WIZARD_TOWER_SCENARIO.md](ARCHITECTURE_WIZARD_TOWER_SCENARIO.md).
The implementation plan lives in
[ARCHITECTURE_WIZARD_TOWER_TECHNICAL.md](ARCHITECTURE_WIZARD_TOWER_TECHNICAL.md).

Use this scenario to test whether Architecture mode can create a large fantasy
tower with a round footprint, three floors, curving stairs, bartizans, conical
roofs, openings, materials, save/reload, and playtestable collision.

## World Mode: Authored Village Assembly

**Scenario id**: `world-authored-village-assembly`

**Version**: 1

**Intent**: A user or LLM can author a countryside village as an editable
asset-first workflow: create the full prop palette, author each house as its own
Architecture object, then assemble terrain, roads, hedgerows, paths, props, and
landmarks into the final village through reusable MCP primitives.

**Starting state**:

- Use the current `friendly-engine` project.
- Start with a disposable scene or a markdown scenario under `scenarios/`.
- Use MCP primitive tools only; do not rely on a named world-generation preset.

**Loop trigger**:

Rerun this scenario after changes to World mode, Prop mode catalog assets,
Architecture primitives, terrain sculpting, road/spline placement, hedgerows,
fences, prop instancing, scene hierarchy, or LLM-facing editor commands.

### Steps

1. Create the village scene from a markdown scenario.
   - Expected: the scene records enough authored objects to inspect terrain,
     roads, buildings, props, and landmarks independently.
   - Capture: full editor screenshot after the first authoring pass completes.

2. Inspect the upfront prop palette.
   - Expected: every prop asset used by the village exists before the village is
     assembled and has a `prop_palette.asset:*` component.
   - Check that missing catalog entries fail loudly instead of silently using a
     substitute.

3. Inspect Architecture objects one by one.
   - Expected: each house, farm building, barn, and shop is an editable
     Architecture object with a unique `architecture.asset:house_N` component.
   - Confirm cottages differ in footprint, roof pitch/overhang, openings, and
     detail placement.

4. Inspect terrain assembly.
   - Expected: terrain, roads, paths, hedgerows, field strips, fences, green
     details, and scattered vegetation appear after the prop and architecture
     phases and include `workflow.phase:terrain_assembly` metadata.

5. Validate navigation and access.
   - Expected: doors face roads or paths, generated navigation markers are
     reachable, and fences or hedgerows do not block all entrances.

6. Save, reopen, and inspect hierarchy.
   - Expected: prop palette references, Architecture intent, terrain assembly
     markers, and village parent/child relationships survive reload.

### Pass Conditions

- The generated scene exposes the order: prop palette first, unique Architecture
  buildings second, terrain/village assembly third.
- All required props are represented by real prop asset instances before they
  are placed as village details.
- Each house is individually editable in Architecture mode and visually distinct.
- Roads, hedgerows, fences, paths, and terrain do not flatten the building work
  into anonymous meshes.
- Validation reports zero blocked doors, disconnected paths, overlaps, or
  missing parents.

### Friction Prompts

- Could you tell where the prop palette ended and placed village props began?
- Which generated house felt least unique?
- Did Architecture objects remain easy to select after terrain and props were
  added?
- Were roads and hedgerows editable world features or just decorative boxes?
- Which generated metadata would help an LLM make the next targeted edit?

### Artifacts

Keep or link:

- Full editor screenshot after generation.
- Viewport screenshot focused on the prop palette.
- Viewport screenshots of at least three different houses.
- Viewport screenshot of terrain, roads, hedgerows, and green assembly.
- `perf_describe` MCP output.
- Saved scene file path.

## Prop Mode: Library To Display Inspection

**Scenario id**: `prop-library-to-display-inspection`

**Version**: 1

**Intent**: A user can create, find, organize, open, inspect, and safely close a
prop without entering geometry edit mode.

**Starting state**:

- Use the current `friendly-engine` project.
- Start in the editor with no special fixtures.
- Begin in Prop mode with the Library tab visible.

**Loop trigger**:

Rerun this scenario after changes to Prop mode library management, prop asset
documents, Display mode camera controls, lighting presets, prop validation,
search, sorting, tags, deletion, or save/close behavior. See
[PROP_MODE_UX.md](PROP_MODE_UX.md) for the target model.

### Steps

1. Create a new prop named `Test Sign Plate`.
   - Choose the `2D Shape` or closest available recipe.
   - Choose paint quality `2x`.
   - Add tags `sign` and `test`.
   - Expected: the prop appears in the Library with stable name, tags, quality,
     and unsaved/saved state.

2. Search for `sign`, then clear search.
   - Expected: filtering is immediate and does not lose selection.

3. Sort the Library by modified time, then by name.
   - Expected: the new prop stays easy to find and selected row state remains
     readable.

4. Rename the prop to `Workshop Sign Plate`.
   - Expected: the display name changes, the stable id/reference behavior is
     clear, and validation does not silently change existing references.

5. Open the prop.
   - Expected: the viewport frames it in an isolated stage and starts in Display
     mode.
   - Capture: full editor screenshot after open.

6. Orbit, zoom, and frame the prop.
   - Expected: drag orbits, wheel zooms, and frame returns the prop to a readable
     view without changing the prop.

7. Cycle lighting presets and scale references.
   - Expected: lighting changes are visible, missing presets fail loudly, and the
     prop remains centered.

8. Toggle collider and bounds preview.
   - Expected: previews are legible and do not imply they are editable in Display
     mode.

9. Close the prop and reopen it from Recent.
   - Expected: no hidden world-scene edit occurred, and the same prop opens in
     Display mode.

10. Attempt delete or archive.
    - Expected: destructive actions show impacted instance counts when relevant
      and refuse invalid project state.

### Pass Conditions

- A tester can complete the scenario without editing KDL or source files by hand.
- Opening a prop isolates it from the world scene.
- Display mode supports inspection but does not allow accidental geometry,
  paint, collider, or variant edits.
- Library search, sort, rename, tag, archive, and delete states are visible.
- Failures identify the prop, reference, preset, or asset that caused them.

### Friction Prompts

- Which management action first required guessing?
- Did opening a prop feel separate from placing props in the world?
- Was Display mode clearly non-editing?
- Which prop identity was clearer: display name, id, tags, or preview?
- Did any destructive action feel too easy or too vague?

### Metrics

Record these when practical:

- Time to create the prop.
- Time to find the prop through search.
- Time to inspect it under three lighting presets.
- Number of accidental edit attempts in Display mode.
- Any editor errors, validation messages, or crashes.

### Artifacts

Keep or link:

- Editor screenshot after new prop creation.
- Editor screenshot after opening in Display mode.
- Viewport screenshots for at least two lighting presets.
- `perf_describe` MCP output during Display mode.
- Prop asset document path.

## Prop Mode: 2D Shapes To Assembled Prop

**Scenario id**: `prop-2d-shapes-to-assembled-prop`

**Version**: 1

**Intent**: A user can create a prop by sketching simple 2D shapes and lines,
then turning those inputs into 3D pieces with extrude, revolve, chain, bend, and
merge operations.

**Starting state**:

- Use the current `friendly-engine` project.
- Start in the editor with no special fixtures.
- Begin from a new scene named `prop_creation_shape_loop` or another clearly
  disposable scene name.
- Use MCP primitive and modifier tools only. Missing source-shape, revolve,
  chain, bend, merge, collider, or material commands should be logged as missing
  reusable primitives rather than replaced with a Zig scenario command.

**Loop trigger**:

Rerun this scenario after changes to Prop mode, primitive placement, shape
sketching, face/edge editing, mesh extrusion, revolve tools, line chains, bend
deformers, merge/combine behavior, collider generation, material assignment, or
prop save/load.

### Steps

1. Create a new scene and switch to Prop mode.
   - Expected: the active mode and tool are visible without reading source or KDL.
   - Capture: full editor screenshot after the blank scene opens.

2. Draw a closed 2D shape for the main prop plate.
   - Use a simple rectangle, pentagon, or shield-like outline.
   - Expected: points snap cleanly, the closing edge is obvious, and the shape can
     be selected as a single editable source.

3. Extrude the closed shape into a thin 3D plate.
   - Expected: extrusion depth is visible and editable, face normals are correct,
     and undo returns to the source shape.
   - Capture: viewport screenshot showing the source and extruded result if both
     remain visible.

4. Draw a 2D side profile and revolve it into a rounded detail.
   - Expected: the axis of revolution is visible, segment count is editable, and
     invalid self-crossing profiles fail loudly.

5. Draw an open line chain and turn it into a tube, rail, or trim strip.
   - Expected: each line segment remains editable, corners join cleanly, and the
     generated mesh follows the chain.

6. Bend or arc part of the chain.
   - Expected: the bend control has a clear handle, the result preserves thickness,
     and the user can recover with one undo.

7. Merge the extruded, revolved, and chained parts into one prop assembly.
   - Expected: the result is selectable as one prop while preserving enough source
     intent to edit or rebuild individual operations.

8. Confirm the operation flow is visible without reading object names.
   - Expected: each source guide has a nearby arrow toward the generated prop
     work, and the assembled prop still fits in the default scenario camera.
   - Capture: viewport screenshot and `objects_list`/`editor_describe` JSON.

9. Add a collider and material.
   - Expected: collider preview matches the merged prop, material assignment is
     visible, and missing collider/material setup is reported on the object.

10. Save, close, and reopen the scene.
   - Expected: the prop assembly and its operation intent survive reload.

11. Improve one or two things, then repeat the same scenario.
    - Expected: the next run has fewer blockers or less friction in the same
      steps, not just a different workaround.

### Pass Conditions

- A tester can complete the scenario without editing KDL or source files by hand.
- Extrude, revolve, chain, bend, and merge operations have visible, selectable
  results.
- The merged prop can be moved, materialed, and given a collider as one assembly.
- The scene can be saved, closed, reopened, and still communicates editable prop
  intent.
- Failures identify the source shape, operation, or parameter that caused them.

### Friction Prompts

- Which operation first required guessing?
- Which source shape or line was hardest to select after generating geometry?
- Which generated mesh needed cleanup before it looked usable?
- Which action needed more than one undo to recover?
- Which controls felt generic instead of Prop-specific?
- Which state was invisible until it failed?

### Metrics

Record these when practical:

- Time to finish the first closed shape.
- Time from closed shape to extruded plate.
- Time from profile to revolved detail.
- Time from line chain to bent tube.
- Number of undo operations.
- Number of times the tester opened the wrong panel or tool.
- Any editor errors, validation messages, or crashes.

### Artifacts

Keep or link:

- Editor screenshot after entering Prop mode.
- Viewport screenshot after shape drawing.
- Viewport screenshot after extrusion.
- Viewport screenshot after revolve.
- Viewport screenshot after chain and bend.
- Viewport screenshot after merge and collider preview.
- `perf_describe` MCP output during editing.
- Saved scene file path.

## Run Log Template

```md
### YYYY-MM-DD: architecture-house-blockout-playtest v1

- Build:
- Platform:
- Renderer:
- Tester:
- Scene:
- Change under test:

Step results:
- 1. New scene:
- 2. Ground with collision:
- 3. Floorplan:
- 4. Extrude rooms:
- 5. Doors/windows:
- 6. Roof:
- 7. FPS spawner:
- 8. Playtest:
- 9. Quit/report:

Metrics:
- Blank scene time:
- Ground collision time:
- Floorplan time:
- Walkable rooms time:
- Undo count:
- Wrong panel/tool count:
- Play attempts:

Friction:
- Blockers:
- Slow moments:
- Confusing labels/state:
- Bugs:

Artifacts:
- Editor screenshot:
- Viewport screenshots:
- Diagnostics:
- Scene file:

Next loop:
- Improvement 1:
- Improvement 2:
```
