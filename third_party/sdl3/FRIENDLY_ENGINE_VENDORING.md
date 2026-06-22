# SDL3 Vendoring

Source: https://github.com/castholm/SDL.git
Branch: release-3.4.x
Revision: 018241066ffdae90d8b11f8bdc6242202f0f5451
Zig package hash: sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj
Vendored from: zig-pkg/sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj

friendly-engine vendors the SDL3 Zig package used by `build.zig`,
because the build links the package's `SDL3` artifact directly.
The package's lazy Linux dependency is also vendored at
`third_party/sdl_linux_deps`.

To refresh this tree, use the `vendor-sdl3` contributor skill in
`.agents/skills/vendor-sdl3`.
