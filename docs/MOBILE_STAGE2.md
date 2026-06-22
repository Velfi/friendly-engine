# Mobile Stage 2 Scaffolding

Stage 2 (iOS and Android) is not implemented. This document records extension points and gaps.

## Build Targets

Mobile executable targets are not wired in `build.zig` yet. Desktop Stage 1 targets remain:

- `friendly_engine_client`
- `friendly_engine_editor`
- `friendly_engine_server`

Planned mobile targets will reuse `runtime_shared` and `friendly_engine` modules with platform window/input shims.

## Platform Gaps

| Area | Desktop today | Mobile gap |
|------|---------------|------------|
| Window lifecycle | SDL3 desktop window | UIKit/Activity lifecycle hooks |
| GPU backend | SDL3 GPU (Metal/Vulkan/D3D12) | Metal (iOS), Vulkan (Android) via SDL3 mobile |
| Input | Keyboard/mouse | Touch, safe areas, on-screen controls |
| File IO | Project folder on disk | Sandboxed app storage, asset packaging |
| World streaming | Synchronous `.fcell` read | Async IO and memory budgets |

## Explicit Failures

Unsupported desktop-only editor features should fail loudly on mobile rather than silently degrade:

- Project Manager import paths outside app sandbox
- Editor subprocess `zig build` world bake from device projects
- FreeType/SDL menubar integrations where unavailable

## Next Steps After Platform Validation (Stream A)

1. Add iOS/Android SDL3 build steps with smoke `main` that opens a window and renders one frame.
2. Port `desktop_backend.zig` window creation to shared `platform_window.zig`.
3. Document device setup and CI smoke expectations in this file.
