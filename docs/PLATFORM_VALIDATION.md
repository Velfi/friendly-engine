# Stage 1 Platform Validation

Use this checklist to validate the Stage 1 desktop promise: macOS with Metal,
Linux with Vulkan, and Windows with D3D12.

Run each platform on that platform. Do not mark Linux or Windows complete from
macOS cross-builds or documentation review. If a machine cannot open windows or
does not have the required GPU API, record that as blocked with the failure
notes below.

## Report Format

After a platform run, add a short entry under `Latest review` in
[PROGRESS.md](../PROGRESS.md):

```md
- Platform validation, <platform>, <date>:
  - Host: <OS version>, <CPU/GPU>, <driver/runtime version if known>
  - Verified: `<command>` -> <pass criteria observed>
  - Failed: `<command>` -> <error summary and captured log path>
  - Blocked: `<command>` -> <missing platform, driver, display, or dependency>
  - Notes: <window opened, renderer banner, visual issue, crash, or follow-up>
```

Keep the entry factual. A failed run is useful when it includes the exact
command, terminal output, screenshots if visual output is wrong, and the point
where behavior diverged from the expected result.

## Common Commands

Run from the repository root:

```sh
zig build test
zig build check
zig build run-tools -- describe
zig build run-client -- --headless --frames 3
zig build run-client -- --software --frames 120
zig build run-editor -- --software --frames 5
```

Expected pass criteria:

- `zig build test` exits 0.
- `zig build check` exits 0 and prints the LLM-friendly surface check summary.
- `zig build run-tools -- describe` exits 0 and prints JSON for runtime
  targets, modules, components, and request commands.
- `zig build run-client -- --headless --frames 3` exits 0, prints a scene
  summary, and prints `friendly-engine client runtime initialized`.
- `zig build run-client -- --software --frames 120` exits 0 and prints
  `software renderer enabled`.
- `zig build run-editor -- --software --frames 5` exits 0, opens the editor
  briefly, and prints `friendly-engine editor: software viewport renderer
  enabled`.

Capture failure notes for:

- Zig version or dependency resolution errors.
- Missing C toolchain, SDL3 build issues, or missing `freetype2`.
- Headless runtime crashes before the fixed frame count completes.
- Software renderer/editor startup errors.
- Any fallback-like behavior where a command appears to pass after silently
  changing renderer mode.

## macOS Metal

Run this section only on macOS with a display available.

```sh
sw_vers
system_profiler SPDisplaysDataType | sed -n '1,80p'
zig build test
zig build check
zig build run-tools -- describe
zig build run-client -- --headless --frames 3
zig build run-client -- --software --frames 120
zig build run-client -- --frames 120
zig build run-editor -- --software --frames 5
zig build run-editor -- --frames 30
```

Expected pass criteria:

- Common command criteria pass.
- `zig build run-client -- --frames 120` opens a GPU window and prints
  `friendly-engine client: Metal GPU renderer enabled (SDL3 GPU API)`.
- `zig build run-editor -- --frames 30` opens the editor and prints
  `friendly-engine editor: Metal GPU viewport enabled (SDL3 GPU API)`.
- The client/editor windows close after the requested frame count without a
  crash, hang, or GPU validation error.

Capture failure notes for:

- macOS version and GPU model.
- Metal framework/link errors.
- SDL3 GPU device creation failures.
- Window creation failures, blank windows, incorrect viewport clearing, or
  frame-limit hangs.
- Whether `--software` still passes when Metal fails.

## Linux Vulkan

Run this section only on Linux with a Vulkan-capable driver and display session.
Do not mark this complete from macOS.

```sh
uname -a
vulkaninfo --summary
zig build test
zig build check
zig build run-tools -- describe
zig build run-client -- --headless --frames 3
zig build run-client -- --software --frames 120
zig build run-client -- --frames 120
zig build run-editor -- --software --frames 5
zig build run-editor -- --frames 30
```

Expected pass criteria:

- Common command criteria pass.
- `vulkaninfo --summary` exits 0 and reports the active Vulkan driver/GPU.
- `zig build run-client -- --frames 120` opens a GPU window and prints
  `friendly-engine client: Vulkan GPU renderer enabled (SDL3 GPU API)`.
- `zig build run-editor -- --frames 30` opens the editor and prints
  `friendly-engine editor: Vulkan GPU viewport enabled (SDL3 GPU API)`.
- The client/editor windows close after the requested frame count without a
  crash, hang, or Vulkan validation/runtime error.

Capture failure notes for:

- Distribution/version, session type (X11 or Wayland), GPU model, and Vulkan
  driver version.
- Missing Vulkan loader/development package errors.
- SDL3 window or GPU device creation failures.
- Blank frames, incorrect viewport output, swapchain errors, or frame-limit
  hangs.
- Whether `--software` still passes when Vulkan fails.

If `vulkaninfo` is not installed, install the distribution's Vulkan tools
package before validating. If installing packages is not allowed on the host,
record the run as blocked rather than passing it.

## Windows D3D12

Run this section only on Windows with a D3D12-capable GPU and display session.
Do not mark this complete from macOS.

In PowerShell:

```powershell
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsHardwareAbstractionLayer
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
zig build test
zig build check
zig build run-tools -- describe
zig build run-client -- --headless --frames 3
zig build run-client -- --software --frames 120
zig build run-client -- --frames 120
zig build run-editor -- --software --frames 5
zig build run-editor -- --frames 30
```

Expected pass criteria:

- Common command criteria pass.
- Windows GPU information reports a D3D12-capable adapter.
- `zig build run-client -- --frames 120` opens a GPU window and prints
  `friendly-engine client: D3D12 GPU renderer enabled (SDL3 GPU API)`.
- `zig build run-editor -- --frames 30` opens the editor and prints
  `friendly-engine editor: D3D12 GPU viewport enabled (SDL3 GPU API)`.
- The client/editor windows close after the requested frame count without a
  crash, hang, or Direct3D runtime error.

Capture failure notes for:

- Windows edition/version, GPU model, and driver version.
- Missing Windows SDK, compiler, runtime DLL, or SDL3 build errors.
- SDL3 window or GPU device creation failures.
- D3D12 device creation failures, blank frames, resize/swapchain errors, or
  frame-limit hangs.
- Whether `--software` still passes when D3D12 fails.

## Completion Criteria

Stage 1 platform validation is complete only when each platform has a dated
`PROGRESS.md` entry with:

- Host and GPU/driver details.
- Pass/fail/block status for every command in that platform section.
- Renderer banner captured for the GPU client and editor commands.
- Failure notes for any command that did not meet the expected pass criteria.

Linux Vulkan and Windows D3D12 remain unverified until those commands run on
Linux and Windows hosts.
