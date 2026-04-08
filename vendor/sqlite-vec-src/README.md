Vendored `sqlite-vec` source used for self-contained `-d:withSqlite` builds.

Current source snapshot:

- `sqlite-vec` `v0.1.9`

Files expected by the build:

- `sqlite-vec.c`
- `sqlite-vec.h`

The project root contains a thin wrapper file `sqlite-vec.c` that compiles this
source with `SQLITE_CORE` and `SQLITE_VEC_STATIC`, so the extension is embedded
and registered in-process instead of being loaded from a `.so`/`.dylib`/`.dll`
at runtime.
