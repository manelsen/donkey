Vendored SQLite amalgamation used for self-contained `-d:withSqlite` builds.

Current source snapshot:

- SQLite `3.51.0`

Files expected by the build:

- `sqlite3.c`
- `sqlite3.h`
- `sqlite3ext.h`

The project root contains a thin wrapper file `sqlite3.c` that includes this
vendored amalgamation so `db_connector` can compile SQLite statically into the
Donkey binary when `staticSqlite` is enabled.
