---
name: vendor-audio
description: Vendor or refresh miniaudio, stb_vorbis, and friendly-engine's audio decode bridge. Use when a user asks to update third_party/audio, refresh audio third-party files, verify miniaudio or stb_vorbis provenance, or repeat the audio vendoring workflow for contributors.
---

# Vendor Audio

## Workflow

friendly-engine vendors `miniaudio.h`, `stb_vorbis.c`, and a local
`fe_audio_decode.*` bridge. Preserve the bridge files; they are local
integration code.

1. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-audio/scripts/vendor_audio.zig -- --replace
```

2. Confirm `third_party/audio/FRIENDLY_ENGINE_VENDORING.md` records the source.
3. Run:

```sh
zig build test
```

## Script Options

Use `--source <path>` when refreshed `miniaudio.h` and `stb_vorbis.c` are
available locally. Use `--bridge-source <path>` if preserving bridge files from
somewhere other than `third_party/audio`.

## Guardrails

- Keep `miniaudio.h`, `stb_vorbis.c`, `fe_audio_decode.c`, and
  `fe_audio_decode.h`.
- Do not commit local build outputs.
- Do not overwrite or drop the bridge files while refreshing upstream source.
