# Editor UI Vision

This document owns detailed editor layout, workflows, and interaction guidance.
Canonical UI and UX design goals live in [UI.md](UI.md). Implementation
sequencing lives in [ROADMAP.md](ROADMAP.md).

Friendly Engine's editor should make simple 3D game creation feel immediate, legible, and calm. The benchmark is not raw feature count. The benchmark is whether a new user can block out a room, texture it, place objects, test the game, and understand what happened without reading a manual.

The editor should feel closer to a good level design instrument than a generic content suite: fast like TrenchBroom, readable like a modern inspector, and small enough for an LLM or developer to reason about.

## Design Goals

- Make the viewport the main workspace.
- Keep every visible control tied to the current task.
- Prefer direct manipulation over modal forms.
- Put creation, selection, editing, and testing on one continuous path.
- Make state obvious: selected object, active tool, snap, axis lock, grid size, and unsaved changes.
- Fail loudly when something cannot be done. Do not hide errors behind fallback behavior.
- Keep labels short, concrete, and neutral.

## First Impression

The first screen should say: this is where you build a game.

Use a full-window editor layout with no welcome wall once a project is open. The current screenshot already has the right bones: project identity, mode tabs, creation tools, outliner, viewport, and properties. The next step is to reduce visual noise and turn those pieces into a confident workspace.

The editor should open with:

- A large central 3D viewport.
- A compact top bar for project state, save, play, and mode.
- A left rail for scene structure and asset placement.
- A right inspector for the selected item.
- A bottom strip for status, errors, coordinates, and quick hints.

## Layout

### Control Placement

Use the densest placement that keeps the user's intent clear. New inputs should
earn their place by matching the scope of the thing they affect.

| Place | Use For | Avoid |
|-------|---------|-------|
| OS menubar | App-level commands, file/project lifecycle, window commands, undo/redo, help, and rarely used preferences | Tool settings, selected-object fields, mode-specific actions, and anything the user needs while dragging in the viewport |
| Top bar | Global editor state and high-frequency commands that should stay visible across modes | Selected-object properties, long forms, asset details, and controls that only matter to one inspector section |
| Viewport tool bar | Active tool choices and immediate editing modifiers for the current mode | Project settings, persistent object metadata, or controls that do not affect the next click/drag |
| Left inspector | Browsing, finding, adding, and organizing things: scene hierarchy, assets, prefabs, primitives, filters, visibility, and locks | Per-selection property editing or global app state |
| Right inspector | Editing the selected object, face, material, component, or tool target | Creation catalogs, project-wide commands, or controls that affect unrelated selections |
| Bottom strip | Passive state, errors, coordinates, counts, progress, and one-line hints | Primary commands, forms, or controls that require comparison and editing |

When placing a new user-facing input, ask these questions in order:

1. Does it affect the app, project, window, or command system regardless of mode?
   Put it in the OS menubar. Mirror only the most common command in the top bar
   when constant visibility helps.
2. Does it affect the whole editor session and need to be visible while working?
   Put it in the top bar.
3. Does it change what the next viewport click, drag, or key press does?
   Put it in the viewport tool bar for the active mode.
4. Does it choose what object, asset, prefab, or primitive the user is working
   with? Put it in the left inspector.
5. Does it edit the currently selected thing? Put it in the right inspector.
6. Is it status, validation, progress, or a hint? Put it in the bottom strip.

Prefer compact controls: icon buttons with tooltips for familiar actions,
segmented controls for small mode sets, checkboxes or toggles for binary state,
small numeric fields for dimensions, and menus for longer option sets. Keep
labels visible where precision matters, but remove repeated nouns when the
section title already supplies context.

Dense does not mean crowded. Keep related controls in short rows, align fields
on a predictable grid, and collapse advanced sections before shrinking common
controls. Do not duplicate an input in multiple panels unless one copy is a
read-only status summary.

### Top Bar

The top bar is for global context and commands:

- Project name.
- Current scene name.
- Save state.
- Play button.
- Build or run target when available.
- Mode switcher: World, Layout, Architecture, Prop, Life.
- Search or command field.

Do not show the full project path unless the user asks for project details. Long paths compete with the work area.

### Tool Bar

The active mode owns the tool bar. It should change based on what the user is doing:

- World: Terrain, Paint, Roads, Scatter, Atmosphere, Measure.
- Layout: Select, Move, Rotate, Scale, Duplicate, Group.
- Architecture: Box, Plane, Cylinder, Ramp, Arch, Doorway, Stairs (blockout brush ops).
- Prop: Display, Edit, Draw, Extrude, Revolve, Solidify, Paint, Collider.
- Life: Select, Pose, Keyframe, Record, Playback, Clips, Bones, Curves.

Use icons where the shape is familiar and pair them with tooltips. Use text labels only when an icon would be ambiguous.

### Viewport

The viewport is the editor's center of gravity.

It should include:

- A readable grid with major and minor lines.
- A small orientation gizmo.
- Transform gizmos with clear axis colors.
- Snap preview before commit.
- Hover outlines before selection.
- Selection outlines that are visible against light and dark materials.
- Object labels only when useful, not always-on clutter.
- A camera speed control.
- A quick toggle for game view.

The viewport should support fast blockout habits:

- Drag on grid to create.
- Drag faces to resize.
- Hold modifier to duplicate.
- Snap by default.
- Type numbers after a drag for exact dimensions.
- Press play without leaving the editor.

### Left Rail

The left rail should combine structure and creation without becoming a junk drawer.

Use tabs:

- Scene: hierarchy, filters, visibility, lock state.
- Add: primitives, prefabs, lights, cameras, trigger volumes.
- Assets: textures, materials, meshes, audio.

The Scene tab should support search, rename, duplicate, delete, hide, lock, and drag reordering. Every row should have a clear selected state and a small type icon.

### Inspector

The inspector should explain the selected thing without making the user hunt.

Recommended sections:

- Name and type.
- Transform.
- Geometry or mesh.
- Material.
- Physics.
- Gameplay components.
- Advanced.

Use section disclosure when the inspector grows. Keep common fields open and advanced fields closed. Numeric fields should support dragging, typing, reset, and copy/paste.

### Bottom Strip

The bottom strip should be quiet until it matters.

Show:

- Current tool hint.
- Snap and grid size.
- Cursor world position.
- Selection count.
- Error count.
- Background task state.

Errors should be clickable and should point to the relevant object, asset, file, or system.

## Interaction Model

The editor should have five primary modes:

| Mode | Purpose | Main Promise |
|------|---------|--------------|
| World | Author large spaces | Layered terrain, roads, scatter, atmosphere |
| Layout | Arrange things | Select and transform without surprise |
| Architecture | Build space | Make playable shapes quickly |
| Prop | Make reusable props | Create, inspect, paint, and validate one prop at a time |
| Life | Pose and animate | Keyframes, clips, and playback |

Modes should change tools, cursors, and inspector sections, but they should not trap the user. Selection, undo, save, and play should work everywhere.

## Core Workflows

### Block Out A Room

1. Enter Architecture.
2. Drag a floor rectangle on the grid.
3. Choose wall height or drag up.
4. Add wall, doorway, ramp, or stair pieces from the tool bar.
5. Snap and alignment stay visible while dragging.
6. Press Play to test scale immediately.

### Texture A Space

1. Enter Prop (or Architecture material tool).
2. Pick a material from the left rail.
3. Click a face to apply.
4. Use Fit, Align, Rotate, and Scale in the tool bar.
5. See texture scale in world units.

### Make A Prop

Prop Mode is specified in [PROP_MODE_UX.md](PROP_MODE_UX.md). It uses an
isolated prop workshop rather than the world scene: browse and manage props in
the left rail, open one prop in Display mode, then switch to Edit mode for
drawing shapes, extruding, revolving, solidifying, painting, collider setup, and
variant work.

### Animate In Life Mode

1. Enter Life.
2. Add or select a clip.
3. Pose objects with the Pose tool; enable Auto Key or Record to capture keys.
4. Scrub the timeline and press Playback to preview.

### Inspect And Fix

1. Select an object in the viewport or Scene tab.
2. Inspector shows only relevant fields first.
3. Errors appear next to the section that caused them.
4. Clicking an error focuses the broken object or field.

### Ask An LLM To Change The Editor

The editor should expose enough structure that an LLM can reason about it:

- UI panels have stable names.
- Commands have stable names.
- Tool state is inspectable.
- Scene selection is inspectable.
- UI copy lives near the feature that owns it.
- Each panel can be understood in a small source file.

## Visual Direction

The editor should look professional, not decorative.

Use:

- Dark neutral canvas.
- Clear panel boundaries.
- A restrained accent color for active state.
- High-contrast text.
- Larger hit targets than the current screenshot.
- Consistent spacing.
- Monospace only for paths, coordinates, and code-like values.

Avoid:

- Long labels that clip.
- Multiple button styles in one row.
- Always-visible instructional paragraphs.
- Repeating the same state in several places.
- Dense borders around every small field.
- Decorative gradients or ornamental panels.

## Copy Rules

Follow [UI_COPY.md](UI_COPY.md).

Preferred labels:

- `Save`
- `Play`
- `World`
- `Layout`
- `Architecture`
- `Prop`
- `Life`
- `Scene`
- `Add`
- `Assets`
- `Inspector`
- `Transform`
- `Material`
- `Physics`
- `Snap`
- `Grid`

Avoid:

- `Close project` when `Close` is enough in context.
- `Save scene` when the top bar already shows the active scene.
- Sentences inside persistent panels.
- Hidden abbreviations unless they are industry standard.

## Accessibility And Comfort

Ease of use includes physical comfort.

- Target size should be at least 28 px for pointer controls.
- Text should remain readable at common desktop resolutions.
- Keyboard focus should be visible.
- Color should not be the only state indicator.
- Sliders and number fields should also accept typed values.
- Undo and redo should cover every editing action.
- The editor should remember panel sizes per project.

## Implementation Checkpoints

Shipped:

1. [x] Clean top bar: project, scene, save, play, modes.
2. [x] Mode-owned tool bar with stable command IDs.
3. [~] Viewport overlays: selection, snap, orientation, grid size.
4. [x] Scene/Add/Assets left rail tabs.
5. [x] Inspector sections with transform first.
6. [x] Bottom strip with tool hint and error count.
7. [ ] Command palette for discoverability.
8. [~] Play-in-editor loop.
9. [~] LLM-readable UI tree and command catalog (`describe` ships command IDs; UI tree inspector is not built yet).

Each slice should be usable on its own. Avoid placeholder panels that do not do anything.

## Definition Of Award Winning

The editor succeeds when it makes hard work feel obvious:

- A beginner can create and test a small 3D room in five minutes.
- A level designer can block out space without fighting the UI.
- A programmer can add a tool without touching unrelated panels.
- An LLM can inspect the UI structure and make a scoped change.
- Errors are precise, visible, and actionable.
- The viewport remains the star.
