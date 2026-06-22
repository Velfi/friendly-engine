# UI Screenshot Review 2026-06-22

Review target: `.friendly-engine/ui-screenshots/20260622T115010Z/manifest.json`

Review basis: [UI.md](UI.md), especially screenshot-obvious state, broad-to-specific workflow, semantic game-world exposure, and MCP/search alignment.

## Summary

The editor has the basic shell that `UI.md` calls for: a primary viewport, mode tabs, tool strips, left rail, right inspector, bottom status, and MCP-captured evidence. It only partially conforms overall because most screenshots require careful memory or zooming to understand the active tool, selection scope, validation state, and next click.

The biggest repeated gaps are:

- Active state is present but too small. Mode/tool chips are visible, but the screenshots do not read clearly at a glance.
- Selection scope, selected object, snap/grid, validation, and unsaved/play state are too subtle or absent.
- Many tools are visually indistinguishable in the viewport, so they do not answer "what will my next click do?"
- Tool prerequisites and invalid setup are not shown near the relevant viewport/tool target.
- Semantic object identity is weak. Scene rows and inspector data often show file-ish or mesh-ish names rather than gameplay roles.
- `editor_describe` lacks top-level `mode` and `tool` fields in the captured manifest, even though `UI.md` asks MCP output to expose the same concepts as the UI.
- Viewport-only screenshots are useful for render regression but do not satisfy `UI.md` state review by themselves because they omit mode/tool/scope UI.

## Row-By-Row Review

| State | Conforms? | Missing for UI.md |
|---|---:|---|
| mode: world | Partial | Mode is visible, but tool/scope/selection/validation/unsaved state are too small. The viewport does not show broad world-authoring intent or next-click behavior. |
| mode: layout | Partial | Mode and selected transform gizmo are visible, but selection scope and selected object identity are weak; no clear snap/grid or validation readout at screenshot scale. |
| mode: architecture | Partial | Architecture mode is visible and closer to blockout intent, but there is no strong floorplan/wall preview or prominent broad-first action cue. |
| mode: prop | Partial | Prop workshop is visibly different, but the stage is nearly empty and selected/open prop intent is unclear. Needs a larger active prop/readiness banner and validation state. |
| mode: life | Partial | Life mode is visible, but animation purpose is not obvious from the viewport. Needs timeline/clip/pose state and selected rig/actor semantics. |
| left-tab: scene | Partial | Active Scene tab is visible, but rows are dense and not semantically grouped enough. Needs stronger type icons, filters, validation badges, and selected object clarity. |
| left-tab: add | Partial | Add catalog is visible, but broad creation categories and next placement target are small. Needs stronger "click to place/draw" affordance and semantic primitives. |
| left-tab: world | Partial | World tab exposes layers, but semantic grouping and validation are quiet. Needs clearer region/terrain/road/scatter roles and dirty/error state. |
| left-tab: assets | Partial | Asset list is visible, but it reads like raw filenames. Needs type grouping, search prominence, material/mesh/audio icons, and placement affordances. |
| world-tool: terrain | Partial | Tool label and inspector exist, but viewport does not show terrain brush radius, affected cell, height preview, or next click action clearly. |
| world-tool: paint | No | Looks almost identical to Terrain. Needs paint brush preview, selected material swatch, opacity/radius, and visible terrain paint target. |
| world-tool: roads | Partial | Existing road lines are visible, but active road operation is not. Needs road-node/edge affordances and a clear draw/select/shape submode readout. |
| world-tool: scatter | No | Viewport and inspector do not communicate scatter placement. Needs scatter brush/area preview, selected scatter set, density, and validation near target. |
| world-tool: atmosphere | Partial | Inspector changes, but viewport does not clearly show atmosphere editing state. Needs sky/sun/fog preview controls and visible current atmospheric target. |
| world-tool: ocean | Partial | Ocean settings are visible in inspector, but the viewport does not show ocean boundary/exclusion intent. Needs ocean/exclusion overlay and clearer readiness. |
| world-tool: water | Partial | Water settings are present, but no local water volume or placement preview is visible. Needs polygon/volume preview and swim/link state. |
| world-tool: measure | No | Tool label exists, but no ruler/cursor/measurement affordance is visible. Needs start point, current distance, snap, and expected next click. |
| world-road-tool: draw | Partial | Road context is visible, but draw mode is only small text. Needs ghost point/segment preview and "click to add road point" near viewport. |
| world-road-tool: select | Partial | Existing road geometry is visible, but selectable targets are not highlighted. Needs road node/edge hover affordances and selected road details. |
| world-road-tool: shape | Partial | Shape mode does not visibly differ from select/draw. Needs editable handles, smoothing/straightening target preview, and invalid target state. |
| world-road-tool: join | No | Join mode is not screenshot-obvious. Needs endpoint highlights, compatible join targets, and explanation when no join target is selected. |
| world-road-tool: surface | Partial | Surface inspector is visible, but viewport lacks material/surface preview. Needs road surface swatch, paint/assign target, and affected road highlight. |
| world-road-draw: point | Partial | Point mode is named, but the viewport does not show point-by-point insertion affordances strongly enough. |
| world-road-draw: freehand | Partial | Freehand mode looks nearly the same as point mode. Needs stroke path preview and sampling/smoothing state. |
| layout-tool: select | Partial | Select is visible, but selected object semantics are weak. Needs stronger selected row/object relationship, scope, hover target, and validation state. |
| layout-tool: move | Partial | Move gizmo is visible, but active axis/snap/grid values and selected object identity are too subtle. |
| layout-tool: rotate | Partial | Rotate tool label exists, but no rotate-specific gizmo is visible in the screenshot. Needs rotation rings/axis and numeric angle hint. |
| layout-tool: scale | Partial | Scale tool label exists, but no scale-specific handles are obvious. Needs scale gizmo, pivot, snapping, and dimensions. |
| architecture-tool: brush | Partial | Brush mode is visible and status says drag to shape blockout, but the viewport lacks a brush rectangle/height/snap preview. |
| architecture-tool: floor | Partial | Floor dimensions are shown in the toolbar, but no floor placement preview is visible. Needs drag rectangle, dimensions, and collision/readiness state. |
| architecture-tool: wall | Partial | Wall dimensions are shown, but there is no wall path preview or target edge. Needs height/thickness cue in viewport. |
| architecture-tool: door | Partial | Door mode is visible, but there is no wall target or invalid "select/place on wall" cue near the viewport. |
| architecture-tool: window | Partial | Same as Door. Needs valid wall target highlighting, height/width preview, and invalid setup feedback. |
| architecture-tool: curve | Partial | Curve mode is visible, but no curve/path handles or point placement affordance are visible. |
| architecture-tool: add | Partial | Add mode is named, but it overlaps conceptually with Brush/Add and needs clearer broad blockout operation preview. |
| architecture-tool: subtract | Partial | Subtract mode is named, but no cut volume or affected solid preview is visible. |
| architecture-tool: ramp | Partial | Ramp mode is named, but there is no ramp ghost, slope/dimensions, or placement target. |
| architecture-tool: vertex | Partial | Vertex mode is visible, but no editable vertices or invalid "no editable object" state are called out. |
| architecture-tool: edge | Partial | Edge mode is visible, but no edge handles/selection target are shown. |
| architecture-tool: face | Partial | Face mode is visible, but no face hover/selection surfaces are highlighted. |
| architecture-tool: extrude | Partial | Extrude mode is visible, but no selected face or "select face first" validation appears. |
| architecture-tool: inset | Partial | Inset mode is visible, but no selected face/inset preview or invalid setup message appears. |
| architecture-tool: material | Partial | Material tool shows swatches, but material target/selected face and world-unit texture scale are not obvious. |
| prop-tool: select | Partial | Display/select state is visible, but the opened prop is tiny and semantic asset identity is weak. Needs larger prop framing and validation summary. |
| prop-tool: create | Partial | Create state is visible, but the stage does not show shape-start affordance strongly enough. Needs base primitive/profile preview and first action cue. |
| prop-tool: asset | Partial | Asset tool looks like Create/Primitive. Needs explicit asset-placement/selection state and selected asset preview. |
| prop-tool: primitive | Partial | Primitive mode is visible, but no primitive ghost, dimensions, or insertion target is shown. |
| prop-tool: edit | Partial | Edit mode has operation-stack text, but the active editable source/operation and handles are too small or absent. |
| prop-tool: material | Partial | Best prop screenshot: paint target ring is visible. Still missing selected material/brush settings at a readable scale and face/UV target identity. |
| prop-tool: collider | Partial | Collider mode is visible, but no collider preview or physics intent is visible in the viewport. |
| prop-tool: variants | Partial | Variants mode is visible, but no variant list/comparison or active variant state stands out. |
| prop-render: wireframe | No | Render modes are visually indistinguishable because no meaningful prop geometry is visible. Needs a prop with visible edges/material and mode-specific viewport proof. |
| prop-render: solid | No | Same issue as wireframe. Needs rendered subject that changes visibly with solid mode. |
| prop-render: material-preview | No | Same issue as wireframe. Needs material preview on visible geometry. |
| prop-render: rendered | No | Same issue as wireframe. Needs lit/rendered subject and a clear active render-mode indicator. |
| life-tool: select | Partial | Life mode and Select chip are visible, but no actor/rig/clip context is obvious. |
| life-tool: pose | No | Pose mode is not screenshot-obvious. Needs skeleton/pose controls, selected bone/actor, and transform handles. |
| life-tool: keyframe | No | Keyframe mode lacks visible timeline/keyframe target. Needs clip, frame/time, selected property, and key readiness. |
| life-tool: record | No | Record mode lacks recording state, armed target, and timeline cue. Needs clear record/stop affordance and safety state. |
| life-tool: playback | No | Playback mode lacks playhead/timeline/clip state. Needs visible playback controls and current frame. |
| life-tool: clips | Partial | Clips tool is named, but no clip list or active clip state is prominent. |
| life-tool: bones | No | Bones mode does not show bones. Needs skeleton/bone overlay, selected bone, and invalid no-rig state. |
| life-tool: curves | No | Curves mode does not show animation curves. Needs curve editor or explicit no-curve state. |

## Recommended Fix Order

1. Add a large, consistent state readout near the viewport: mode, tool, selection scope, selected object/semantic type, snap/grid, validation count, unsaved/play state.
2. Give every tool a viewport affordance: cursor hint, ghost geometry, brush radius, handles, target highlight, or explicit invalid-state overlay.
3. Promote semantic labels over raw mesh/file data in Scene, Assets, inspector, and `editor_describe`.
4. Add top-level `mode`, `tool`, `left_tab`, `selection_scope`, and validation fields to `editor_describe`.
5. Re-capture documentation screenshots with prepared content per mode: road graph for road tools, editable building for Architecture, visible prop with materials/collider for Prop render/tools, and an actor/clip for Life.
