# The SQLite store suite only exists with the SQLite backend: without these
# defines the runner compiled an empty suite and the store went untested.
switch("define", "withSqlite")
switch("define", "staticSqlite")
