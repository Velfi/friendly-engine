# UI Screenshot Review After Fixes - 2026-06-22

Fresh capture: `/Users/zelda/Documents/friendly-engine/.friendly-engine/ui-screenshots/20260622T121951Z/manifest.json`

Contact sheets: `/Users/zelda/Documents/friendly-engine/.friendly-engine/ui-screenshots/20260622T121951Z/review-contact-sheets/`

## Summary

The new capture is substantially more useful for documentation and regression review than the first pass. Each full-editor screenshot now carries a viewport HUD that identifies the active mode, active tool, next action, selection scope, snap/grid state, file state, validation count, view mode, shading mode, and play state. This directly fixes the largest screenshot-review problem: many states no longer require reading tiny toolbar icons or inferring state from nearly identical geometry.

The MCP manifest is also improved. All 63 captured states now include top-level `mode`, `mode_label`, `tool`, `tool_label`, `left_tab`, `left_tab_label`, `selection_scope`, `snap`, and `file_state` fields, so downstream docs/tests can group and label states without digging through nested editor payloads.

The remaining issues are mostly fixture and affordance gaps. Prop render captures still lack a visible prop/model large enough to prove wireframe, solid, material-preview, and rendered differences. Life and many architecture captures are legible as state captures, but not yet as behavioral examples because the scene content is sparse and most tool-specific overlays are not exercised.

## Improvements

- Active state is now prominent in the viewport, not only in small toolbar tabs.
- Mode/tool names are legible at contact-sheet scale.
- Next-action guidance is visible per tool, which helps documentation explain what a screenshot is showing.
- Snap/grid, file clean/dirty state, validation status, view mode, shading mode, and play state now have a single consistent visual location.
- Full-editor screenshots and manifest labels agree across all 63 states.
- The screenshot tool can run against the freshly built editor binary without the duplicate project-module startup crash.

## Remaining Issues

| Area | Status | Notes |
| --- | --- | --- |
| Mode and tab captures | Improved | The HUD makes the active mode/tool obvious. Left-tab captures still depend on side-panel content for the tab-specific difference. |
| World tools | Improved | Terrain, paint, roads, scatter, atmosphere, ocean, water, and measure are now clearly named. Tool-specific viewport previews are still limited. |
| Road sub-tools | Partial | Draw/select/shape/join/surface and point/freehand are labeled, but the viewport does not yet show distinct road-edit affordances for each state. |
| Layout tools | Improved | Select/move/rotate/scale are now distinguishable by HUD text. A future fixture should select an object and show the relevant transform handle. |
| Architecture tools | Improved | Brush/floor/wall/door/window/curve/add/subtract/ramp/vertex/edge/face/extrude/inset/material are labeled. The viewport still needs richer prepared geometry to show why each tool matters. |
| Prop tools | Partial | Tool labels are clear, but most captures show an almost empty or tiny preview. This weakens documentation value for create/asset/primitive/edit/material/collider/variants. |
| Prop render modes | Still weak | Wireframe/solid/material-preview/rendered remain visually hard to distinguish because the captured prop content is too small or absent. |
| Life tools | Partial | Select/pose/keyframe/record/playback/clips/bones/curves are labeled. The viewport needs a rig or animation fixture before these can serve as behavior screenshots. |
| Validation/unsaved/play indicators | Improved | These are now exposed in the HUD. The current state matrix mostly captures clean/non-playing states, so dirty/play/invalid examples still need explicit scenario coverage. |

## Recommended Next Pass

1. Add screenshot fixture commands that prepare richer per-mode content before capture:
   - selected transform target for layout tools,
   - editable architecture blockout with faces/edges/openings,
   - visible prop mesh with material/collider/variant data,
   - rigged or animated object for life tools.
2. Add state-specific viewport overlays where a tool has a unique interaction model, especially road sub-tools and prop render modes.
3. Extend the screenshot script with explicit dirty, validation-error, play-running, and snap-off scenarios.
4. Prefer documentation contact sheets generated from full-editor screenshots, with viewport-only captures retained for low-level rendering tests.

## Verdict

The first-order UI documentation gap is fixed: screenshots now identify what state they are showing. The next improvement should focus on demonstrative content and interaction affordances, so each tool screenshot proves behavior instead of only proving that the tool can be selected.
