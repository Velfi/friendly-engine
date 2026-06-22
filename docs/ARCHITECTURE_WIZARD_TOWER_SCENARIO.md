# Architecture Scenario: Wizard Tower

**Scenario id**: `architecture-wizard-tower`

**Version**: 1

## Intent

A user can create a large fantasy wizard tower in Architecture mode without
dropping into generic mesh editing. The scenario stresses irregular building
shape, vertical floors, curved circulation, projecting substructures, semantic
openings, and conical roofs.

The finished building should read immediately as a wizard tower: a tall main
tower, three usable floors, curving stairs, one or two bartizans, narrow windows,
and conical roofs.

## Starting State

- Use the current `friendly-engine` project.
- Start in the editor with no special fixtures.
- Use the GPU editor path when available; use `--software` only when GPU is not
  usable on the test machine.
- Begin from a new disposable scene named `architecture_wizard_tower_loop`.
- Start in Architecture mode.

## Loop Trigger

Rerun this scenario after changes to Architecture mode, semantic building data,
floorplan drawing, roof generation, stairs, wall features, openings, material
assignment, collision, save/load, play-in-editor, or viewport tool overlays.

## Target Building

- Main tower: round or near-round footprint, roughly 8-10 meters diameter.
- Floors: 3 floors, each roughly 3.5-4 meters tall.
- Circulation: one curving or spiral stair path connecting all floors.
- Bartizans: 1-2 small turret rooms projecting from the upper floors.
- Roofs: one large conical roof on the main tower, smaller conical roofs on
  bartizans.
- Openings: one ground-level door and several narrow windows distributed around
  the tower.
- Materials: stone walls, darker conical roof material, simple trim around
  doors/windows if available.

## Steps

1. Create a new scene.
   - Expected: the editor makes a clean scene without requiring file-system
     knowledge.
   - Capture: full editor screenshot after the blank scene opens.

2. Enter Architecture mode and start a new building.
   - Expected: the UI frames this as creating a building, not editing loose
     objects.
   - Check: Plan, Build, Roof, and Materials tasks are discoverable.

3. Draw the main tower footprint.
   - Use a circle, radial polygon, or near-round footprint tool.
   - Target an 8-10 meter diameter.
   - Expected: the footprint closes cleanly, shows diameter/segment feedback,
     and remains editable.
   - Capture: top-down or angled viewport screenshot of the footprint.

4. Raise the tower to three floors.
   - Set floor count to 3.
   - Set floor height around 3.5-4 meters.
   - Expected: the result is one semantic multi-floor building, not three
     unrelated cylinders.
   - Check: floors are visible, selectable, and editable.

5. Add curving stairs.
   - Add a spiral or curved stair path inside the tower.
   - Connect floor 1 to floor 2 and floor 2 to floor 3.
   - Expected: stairs snap to floor elevations and show climb direction.
   - Check: landings or endpoints align to floor heights.

6. Add a ground-level door.
   - Place one exterior door at the base of the tower.
   - Expected: the opening cuts the correct curved/segmented wall and produces
     matching visible and collision geometry.

7. Add narrow windows.
   - Add at least two windows per floor.
   - Offset them around the tower circumference.
   - Expected: windows stay attached to wall segments, respect sill/height
     settings, and remain editable.

8. Add one or two bartizans.
   - Attach small projecting turret rooms to floor 2 or floor 3.
   - Place at least one on a diagonal or non-cardinal side if possible.
   - Expected: bartizans attach to the main tower, inherit sensible floor
     height, and become part of the same building intent.
   - Check: intersections with the main tower are clean enough to read.

9. Add conical roofs.
   - Apply a large conical roof to the main tower.
   - Apply smaller conical roofs to each bartizan.
   - Expected: roof bases match their footprints, pitch/overhang are adjustable,
     and no obvious holes or inverted faces appear.
   - Capture: Roof mode screenshot with roof handles or parameters visible.

10. Apply materials.
    - Assign stone to walls.
    - Assign slate, dark shingles, or another roof material to conical roofs.
    - Assign trim if available.
    - Expected: materials are assigned by architectural role rather than by
      manual triangle selection.

11. Display review.
    - Switch to Display mode.
    - Orbit around the tower.
    - Toggle lighting and overlays.
    - Expected: the silhouette reads as a wizard tower from multiple angles.
    - Capture: final full editor screenshot.

12. Save, reload, and playtest.
    - Save the scene.
    - Reopen it.
    - Start playtest near the tower entrance.
    - Expected: tower geometry, openings, stairs, roofs, and materials persist.
      The player can enter the tower and use the stairs or at least verify their
      collision/readability.

## Pass Conditions

- The tester can complete the tower without editing KDL or source files.
- The main tower, floors, stairs, bartizans, and roofs remain one coherent
  semantic building or a clearly grouped building assembly.
- Curving stairs visually connect all three floors.
- Conical roofs fit the main footprint and bartizan footprints.
- Door and window openings cut the intended wall segments.
- Materials are assigned by role: wall, roof, trim, floor.
- Save/reload preserves editable Architecture intent.
- Failures identify the object, tool, or missing setup that caused them.

## Friction Prompts

- Which step first required guessing?
- Did the UI make it clear whether the tester was editing Plan, Build, Roof, or
  Materials?
- Did the tower footprint feel like a first-class shape or a workaround?
- Did curved stairs feel semantic, or like placing unrelated geometry?
- Were bartizans easy to attach to the tower at the intended floor?
- Did conical roof creation understand round and projecting footprints?
- Did any action require generic mesh edit tools?
- Did save/reload preserve editability, not only triangles?

## Metrics

Record these when practical:

- Time to create the main footprint.
- Time to raise the tower to three floors.
- Time to place stairs that connect all floors.
- Time to add one bartizan.
- Time to add all conical roofs.
- Number of undo operations.
- Number of times the tester opened the wrong panel or tool.
- Number of invalid roof/stair/opening attempts.
- Number of playtest attempts before entering the tower successfully.

## Artifacts

Keep or link:

- Screenshot after blank scene creation.
- Screenshot after main tower footprint.
- Screenshot after three floors are visible.
- Screenshot after stairs are placed.
- Screenshot after bartizans are attached.
- Screenshot in Roof mode with conical roof controls visible.
- Final Display mode screenshot.
- Playtest screenshot near the entrance or inside the tower.
- `perf_describe` MCP output during editing.
- Saved scene file path.
