# UI Design Goals

This document is the canonical UI and UX goal statement for Friendly Engine.
Detailed editor layout and workflow guidance lives in [EDITOR_UI.md](EDITOR_UI.md);
user-facing wording rules live in [UI_COPY.md](UI_COPY.md).

Friendly Engine's editor should make simple 3D game creation faster, clearer,
and more semantic than a generic 3D content suite. The editor should help users
move from game intent to playable space without losing sight of what they are
editing or why it matters to the game.

## Principles

### Faster General Blockout

General blockout should be quicker and easier than similar 3D editors.

Example: a user creates a small room by dragging a rectangle on the grid,
pulling walls up, placing a doorway, adding a player start, and pressing Play.
They should not need to align six independent cube meshes, configure collision
by hand, or dig through generic transform panels before the space is testable.

Design checks:

- Can the user create broad playable forms before editing fine details?
- Are snap, dimensions, and collision intent visible while blocking out?
- Is the shortest path to Play obvious from the blockout workflow?

### Screenshot-Obvious State

A screenshot should reveal what is happening without requiring memory of the
previous interaction.

Example: from a single editor screenshot, another developer or LLM should be
able to tell the active mode, active tool, selection scope, selected object or
marker, snap/grid state, validation state, play/edit state, and whether the
scene has unsaved changes.

Design checks:

- Does the screenshot answer "what mode am I in?" and "what will my next click do?"
- Are errors and invalid setup visible near the relevant object or tool?
- Are semantic object types visible, not only mesh names or ids?

### Start General, Move Specific

The editor should encourage broad intent first, then refinement.

Example: in Architecture, the user draws a floorplan, extrudes it into rooms,
then adjusts individual walls, openings, materials, and gameplay markers. They
should not start by editing isolated vertex coordinates before the room exists.

Design checks:

- Do tools flow from scene/world intent to shape to details?
- Are common broad actions more prominent than advanced per-element tweaks?
- Can invalid partial work remain editable while clearly reporting why it is not ready?

### Understand Complex Scenes

The editor should help users understand scenes as game spaces, not as long lists
of anonymous objects.

Example: in a village scene, the hierarchy, filters, overlays, labels, and
inspectors make it easy to distinguish terrain, roads, buildings, props, spawn
points, objectives, triggers, patrol paths, audio, and cameras.

Design checks:

- Can users filter and group by semantic role?
- Do overlays and labels clarify important game intent without cluttering the viewport?
- Does validation identify the object, layer, marker, asset, or system that needs attention?

### Find Game Elements Through Search

Search should reveal game concepts across the editor, command palette, MCP
describe output, and scene/object inspection.

Example: searching for "spawn" should find Player Start and Spawn Point marker
creation, existing spawn markers, relevant commands, and MCP-visible marker
data. `editor_describe` should report `marker: player_start`, not just a mesh id.

Design checks:

- Are commands named after user intent and game concepts?
- Do MCP tools expose the same semantic state visible in the editor?
- Can users search for concepts like objective, trigger, patrol, road, material, or prop?

### Expose The Semantic Game World

The editor should preserve and expose game meaning so users can modify and
extend systems, not only manipulate triangles.

Example: a trigger volume is edited as a trigger, a road as a road path, a
building as architecture intent, a patrol point as patrol data, and a prop as a
reusable authored asset. Visible meshes are outputs of intent, not replacements
for it.

Design checks:

- Is authored intent persisted separately from disposable render geometry?
- Can users and LLMs inspect, modify, and validate semantic objects directly?
- Are runtime-facing game concepts clearly separate from editor-only overlays?

## Review Checklist

Use this checklist before merging UI changes:

- The viewport remains the primary workspace.
- The active mode, tool, scope, selection, and validation state are obvious.
- The workflow starts with broad creation before detailed editing.
- Search and MCP describe output expose the same game concepts the UI shows.
- Semantic intent is preserved when saving, loading, playing, and describing scenes.
- The UI is attractive through clarity, spacing, hierarchy, and restraint, not decoration.
