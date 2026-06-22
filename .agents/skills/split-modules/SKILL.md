---
name: split-modules
description: Run the friendly-engine module-size checker and break oversized source files into smaller, cohesive modules. Use when the user asks to find oversized files, split modules, reduce file size, or enforce the "small files" principle.
---

# Split Oversized Modules

Enforces the AGENTS.md principle "Small files, happy developers" by finding
oversized source files and refactoring them into smaller, focused modules.

## Workflow

Copy this checklist and track progress:

```
- [ ] Step 1: Run the checker
- [ ] Step 2: Pick the worst offender
- [ ] Step 3: Plan the split
- [ ] Step 4: Extract into new files
- [ ] Step 5: Verify build + tests
- [ ] Step 6: Re-run the checker
```

### Step 1: Run the checker

```sh
zig build modcheck
```

Exits non-zero and lists files over the threshold (default 700 lines), sorted
largest first. Flags: `--max <lines>`, `--dir <path>`, `--ext <.zig>`.

### Step 2: Pick the worst offender

Start with the largest file reported. Work one file at a time so each change
stays reviewable. Read the whole file before editing.

### Step 3: Plan the split

Identify cohesive groups inside the file (a type and its methods, a subsystem,
a set of related helpers). Each new file should have a single clear
responsibility and a name that describes it. Follow existing layout: shared
runtime code lives in `src/runtime/shared/`, editor code in
`src/runtime/editor/`, etc.

Prefer extracting:
- Standalone structs/types and their methods.
- Pure helper/free functions grouped by topic.
- Self-contained subsystems (rendering, input, serialization, UI panels).

### Step 4: Extract into new files

- Create the new `.zig` file(s) with the moved declarations.
- Make declarations that cross file boundaries `pub`.
- In the original file, replace moved code with `const x = @import("new_file.zig");`
  and update references.
- Keep the public API of the original file unchanged where possible so callers
  and `build.zig` module roots do not break.
- Do not leave narration comments; let names carry intent.

### Step 5: Verify build + tests

```sh
zig build test
zig build run-editor -- --frames 5
```

Run the relevant verification commands from `PROGRESS.md`. Fix any compile or
test failures before moving on.

### Step 6: Re-run the checker

```sh
zig build modcheck
```

Confirm the file you split is now under the threshold. Repeat from Step 2 for
the next offender, or stop if the user only asked for one.

## Notes

- The tool lives in `src/tools/module_size.zig` (logic) and
  `src/tools/modcheck_main.zig` (entry); build wiring is in `build.zig`.
- Splitting must preserve behavior. This is mechanical refactoring, not a
  rewrite — do not change logic while moving code.
- If a single function is itself oversized, split it into smaller helpers in
  the same or a new file rather than just relocating it.
```
