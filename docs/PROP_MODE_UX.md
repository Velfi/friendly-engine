# Prop Mode UX

Prop Mode is the prop workshop. It is where authors create, browse, texture,
test, and maintain reusable game props one at a time. It is deliberately
separate from World, Layout, and Architecture mode: opening a prop moves the
editor into an isolated asset space with its own camera, lighting, origin,
validation, and save lifecycle.

The goal is not to become Blender. The goal is to make small game-ready props
fast: crates, doors, lamps, chairs, signs, trims, handles, pickups, simple
machines, and modular details.

## Product Promise

- Create a new prop in seconds.
- Find, rename, tag, sort, duplicate, archive, and delete props without file
  system knowledge.
- Open one prop into a calm isolated workspace.
- Start in Display mode so opening a prop is safe and inspectable.
- Switch to Edit mode only when changing geometry, paint, collider, or variants.
- Draw simple 2D sources, turn them into 3D pieces, and keep the source intent
  editable.
- Texture paint directly on the model without managing UVs.
- Choose paint quality explicitly: `1x`, `2x`, or `4x`.
- Fail loudly when geometry, paint, collider, or save data is invalid.

## Mental Model

Prop Mode has two levels:

| Level | Purpose | Main UI |
|-------|---------|---------|
| Library | Manage the project's reusable props | list, search, filters, tags, sort, actions |
| Workshop | Edit one opened prop in isolation | display stage, edit tools, operation stack |

The Library answers "what prop am I working on?" The Workshop answers "what is
this prop and how is it built?"

Opening a prop never edits placed instances directly. Placed instances update
from the saved prop asset. A changed prop should show an affected-instance count
before save when instances exist in the current project.

## Default Layout

Use the normal editor chrome:

- Top bar: project, save state, play, mode tabs, command search.
- Left rail: Prop Library and creation shortcuts.
- Viewport: isolated prop stage.
- Right inspector: selected prop, source, operation, face, paint layer, collider,
  or validation detail.
- Bottom strip: active tool hint, prop path/id, unsaved state, validation count,
  instance impact count.

### Left Rail

Left rail tabs in Prop Mode:

- `Library`: searchable prop list.
- `Create`: new prop recipes and import entry points.
- `Materials`: paint materials, palettes, stencils.
- `Recent`: recently opened props.

`Library` is the default tab when no prop is open. It supports:

- Search by name, id, tag, material, and validation status.
- Sort by `Name`, `Modified`, `Tag`, `Use Count`, and `Errors`.
- Tag filters with multi-select chips.
- Row actions: open, rename, duplicate, tag, archive, delete.
- Bulk actions for tag, archive, and delete.

Deletion should be a two-step destructive action when the prop has placed
instances. The dialog must show the number of impacted instances and refuse to
delete if a referenced prop would leave world data invalid unless the user also
chooses a replacement prop.

### Viewport

The viewport is an isolated stage:

- Origin marker at the prop pivot.
- Soft ground/contact plane that can be hidden.
- Optional scale references: player, meter cube, door frame.
- Orientation gizmo.
- Focus and reset camera commands.
- Lighting preset menu.
- Display/Edit segmented control in the viewport toolbar.

The prop is framed automatically on open. Display mode camera controls are
simple:

- Drag orbits.
- Wheel zooms.
- Middle drag pans if available.
- Double-click focuses.
- `F` frames the prop.

### Right Inspector

Inspector sections depend on selection:

- Prop selected: name, id, tags, pivot, bounds, quality, save state, instances.
- Source selected: points, plane, snap, dimensions, close/open state.
- Operation selected: operation parameters and generated result status.
- Face selected: material, paint layer, solidify/extrude controls.
- Collider selected: shape, fit, preview, validation.
- Validation selected: exact error and repair action.

Common sections should stay short and open. Advanced geometry and file details
stay collapsed.

## Display Mode

Display mode is the first state after opening a prop. It is for looking, not
editing.

Display mode toolbar:

- Lighting: `Studio`, `Game`, `Dim`, `Backlit`, `Unlit Check`.
- Background: `Dark`, `Light`, `World`.
- Scale: `None`, `Player`, `Meter`, `Door`.
- Motion: turntable toggle.
- Collider preview toggle.
- Bounds preview toggle.

Display mode should allow selecting validation messages and viewing metadata,
but it should not allow geometry, paint, collider, or tag changes except through
explicit Library actions. This makes opening a prop safe.

Lighting presets should be project data, not hidden editor constants. Missing
lighting preset data should fail with a clear error instead of falling back.

## Edit Mode

Edit mode changes the toolbar and enables direct manipulation.

Top-level Edit tools:

- `Select`: choose sources, operations, faces, edges, vertices, pieces.
- `Draw`: sketch closed shapes, open chains, and revolve profiles.
- `Extrude`: give closed sources or selected faces depth.
- `Revolve`: spin a side profile around an axis.
- `Solidify`: turn 2D faces into thickness.
- `Paint`: texture paint on the prop.
- `Collider`: fit and edit collision.
- `Variants`: create and compare variations.

Viewport quality controls in Edit mode:

- `Wire`: wireframe with source/operation overlays.
- `Unlit`: flat material color and paint layers without lighting.
- `Full`: normal game rendering.

These are explicit render modes. If GPU wireframe or unlit paths are missing,
the mode should show an actionable error.

## Creation Workflow

### New Prop

New Prop flow:

1. Click `New`.
2. Choose a starting recipe: `Blank`, `Box`, `Cylinder`, `2D Shape`, `Revolve`,
   `Imported Mesh`.
3. Enter name and optional tags.
4. Choose paint quality: `1x`, `2x`, or `4x`.
5. Create opens the prop in Display mode.

The new prop gets a stable id derived from the name, with a visible rename path.
The id should not silently change after references exist.

### Draw And Extrude

For hard-surface props, the fastest path is drawing a 2D source and giving it
depth.

Interaction:

- Click points on the active drawing plane.
- Snap is visible before each point is placed.
- Hovering the first point previews closing the shape.
- Enter commits the source.
- Drag depth handle or type depth to extrude.
- The source remains visible in Wire mode and selectable in the operation stack.

Closed shapes can extrude into solids. Open chains can become tubes, rails, trim,
or bevel strips.

### Revolve

Revolve uses a side profile and a visible axis.

Interaction:

- Draw an open or closed side profile.
- Drag the axis or choose `X`, `Y`, `Z`.
- Segment count is editable.
- Angle defaults to 360 degrees but can be partial.
- Self-crossing or zero-radius profiles fail before mesh generation.

### Solidify

Solidify turns a 2D face or source surface into a solid object.

Interaction:

- Select a face or closed 2D source.
- Choose `Solidify`.
- Drag thickness handle or type thickness.
- Choose direction: `Both`, `Front`, `Back`.
- Toggle rim caps.

Solidify is an operation, not a destructive one-way conversion. The face/source
and thickness should survive save/reload.

## Texture Painting

Prop painting must not require authors to see or manage UVs.

Each prop owns a generated paint atlas. The editor chooses and maintains the UV
unwrap internally. Authors interact with:

- Paint quality: `1x`, `2x`, `4x`.
- Brush: size, opacity, hardness.
- Material/color slot.
- Stencil: none, checker, stripes, edge wear.
- Layers: base, detail, dirt, edge wear, emission where supported.

Quality should be explained by data, not prose:

| Quality | Use | Cost |
|---------|-----|------|
| `1x` | small or distant props | smallest texture |
| `2x` | common gameplay props | balanced texture |
| `4x` | hero or close-up props | largest texture |

Changing quality should show the new texture size and ask for confirmation when
it would discard paint detail. Increasing quality can resample. Decreasing
quality should be explicit because detail may be lost.

Paint mode viewport behavior:

- Brush cursor projects onto visible surface.
- Backface painting is off by default.
- Symmetry can be enabled per axis.
- Wire overlay can be enabled while painting.
- Missing paint atlas or failed unwrap blocks painting with a clear error.

## Operation Stack

Prop geometry should preserve intent. Instead of only storing a baked mesh, a
prop stores an operation stack:

- Sources: 2D shapes, open chains, profiles, imported meshes.
- Operations: extrude, revolve, solidify, bevel, inset, mirror, array, bend,
  merge.
- Outputs: generated mesh pieces and final assembly.

The right inspector should show the stack as short rows:

```text
Shape Shield
  Extrude 0.12 m
Profile Knob
  Revolve 24 segments
Chain Trim
  Tube 0.04 m
Merge Assembly
```

Rows are selectable. Selecting a row reveals handles in the viewport and fields
in the inspector. Invalid rows remain visible with an error state; generated
outputs after an invalid row are marked stale instead of silently rebuilding with
missing data.

## Save And Validation

Each prop asset needs validation before save:

- Stable id and display name.
- At least one visible mesh output.
- No invalid operation rows.
- Paint atlas exists when painted materials are used.
- Collider exists or the prop is marked `No Collider`.
- Pivot and bounds are valid.
- Referenced materials exist.

Validation errors are shown in the bottom strip and in an inspector section.
Clicking an error selects the failing source, operation, face, material, or
collider.

Save behavior:

- Display mode can save metadata changes from Library actions.
- Edit mode saves geometry, paint, collider, variants, and metadata.
- Saving a changed prop reports impacted placed instances.
- Runtime and world bake should consume the saved prop asset, not open editor
  state.

## Data Shape

The first production data model can be simple and explicit:

```text
props/
  <prop-id>.kdl
  meshes/<prop-id>.fmesh
  paint/<prop-id>-base.png
  paint/<prop-id>-detail.png
```

The prop document owns:

- id
- label
- tags
- paint quality
- mesh path
- generated paint atlas paths
- collider intent
- pivot
- bounds
- variant list
- operation stack
- validation version

The baked mesh is a cacheable output of the operation stack. Loading a prop
should fail if the document references a missing required mesh, paint atlas, or
material.

## Commands

Initial command catalog additions:

- `prop.new`
- `prop.open`
- `prop.close`
- `prop.rename`
- `prop.duplicate`
- `prop.tag`
- `prop.archive`
- `prop.delete`
- `prop.display`
- `prop.edit`
- `prop.view.wire`
- `prop.view.unlit`
- `prop.view.full`
- `prop.light.next`
- `prop.draw.shape`
- `prop.draw.chain`
- `prop.draw.profile`
- `prop.extrude`
- `prop.revolve`
- `prop.solidify`
- `prop.paint`
- `prop.quality.1x`
- `prop.quality.2x`
- `prop.quality.4x`
- `prop.collider.fit`
- `prop.validate`
- `prop.save`

Use short visible labels that follow `UI_COPY.md`: `New`, `Open`, `Rename`,
`Tag`, `Delete`, `Display`, `Edit`, `Wire`, `Unlit`, `Full`, `Draw`, `Extrude`,
`Revolve`, `Solidify`, `Paint`, `Collider`, `Validate`, `Save`.

## Implementation Slices

### P1: Library And Open Prop

- Replace the current asset list with a prop library model.
- Add create, open, rename, tag, sort, search, duplicate, archive, delete.
- Open prop assets into isolated Prop Workshop state.
- Default to Display mode.
- Show affected instance count for open prop assets.

Done when a user can manage prop assets without touching files and opening a
prop does not edit the world scene.

### P2: Display Stage

- Add isolated camera controls: orbit, zoom, pan, frame.
- Add lighting presets and scale references.
- Add collider and bounds previews.
- Add Display/Edit segmented control.

Done when opening a prop feels like inspecting one asset on a turntable.

### P3: Edit Render Modes

- Add Wire, Unlit, and Full render modes.
- Surface missing renderer support as errors.
- Keep operation/source overlays readable in Wire and Unlit.

Done when authors can inspect shape, paint, and final game rendering without
changing tools.

### P4: Shape Sources And Operations

- Add 2D source shape data.
- Add extrude and solidify operations.
- Add revolve profile and axis operation.
- Add operation stack inspector.
- Save/reload operation intent.

Done when the `prop-2d-shapes-to-assembled-prop` scenario can be completed from
the UI.

### P5: UV-Free Paint Quality

- Add generated paint atlas per prop.
- Add quality enum: `1x`, `2x`, `4x`.
- Add paint brush projection onto generated UVs.
- Add quality resize/confirmation behavior.

Done when authors can paint a prop directly and save/reload paint without
opening a UV editor.

### P6: Collider, Variants, And Runtime Link

- Add collider intent and fit commands.
- Add variant rows that share the base operation stack where possible.
- Ensure placed prop instances update from saved prop assets.
- Ensure world bake and runtime loading fail loudly on missing prop data.

Done when prop assets are reusable game objects, not just editor meshes.

## Playtest Scenario Updates

Add or extend scenarios for:

- Library management: create, rename, tag, sort, search, duplicate, delete.
- Display inspection: open prop, change lighting, orbit, zoom, check collider.
- Shape creation: draw, extrude, revolve, solidify, merge.
- Paint quality: paint at `1x`, increase to `2x`, paint detail, attempt
  downgrade.
- Runtime link: place prop in Layout mode, edit asset in Prop mode, verify
  placed instance updates after save.

## Open Decisions

- Whether archived props remain visible by default in Library search.
- Whether prop tags are project-local strings or a small typed taxonomy.
- Whether variants are independent operation stacks or parameter overrides.
- Whether paint layers are always present or allocated on first use.
- Whether prop workshop changes autosave drafts or require explicit save.
