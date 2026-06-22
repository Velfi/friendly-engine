# xatlas

Vendored from `jpcy/xatlas`.

- Upstream: https://github.com/jpcy/xatlas
- Commit: `f700c7790aaa030e794b52ba7791a05c085faf0c`
- Commit date: 2022-07-25T23:06:01Z
- License: MIT, see `LICENSE`.

Only the library source required for engine integration is vendored:

- `source/xatlas/xatlas.h`
- `source/xatlas/xatlas.cpp`
- `fe_xatlas_bridge.h`
- `fe_xatlas_bridge.cpp`

The bridge exposes a small C ABI so Zig code does not depend directly on C++
namespace types.
