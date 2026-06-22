---
name: vendor-fonts
description: Vendor or refresh friendly-engine's UI font files. Use when a user asks to update third_party/fonts, refresh Atkinson Hyperlegible, verify font provenance, repair vendored font files, or repeat the font vendoring workflow for contributors.
---

# Vendor Fonts

## Workflow

friendly-engine vendors Atkinson Hyperlegible for editor and runtime UI text.

1. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-fonts/scripts/vendor_fonts.zig -- --replace
```

2. Confirm `third_party/fonts/FRIENDLY_ENGINE_VENDORING.md` records the source.
3. Run:

```sh
zig build test
```

## Script Options

Use `--source <path>` when refreshed font files are available locally.

## Guardrails

- Keep `AtkinsonHyperlegible-Regular.ttf` and `AtkinsonHyperlegible-OFL.txt`.
- Keep the SIL Open Font License text with the font.
- Do not silently skip missing font files. The script should fail loudly.
