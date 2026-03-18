# Makes `src/` visible to all nim compilations in this project,
# including testament test files in tests/.
switch("path", "src")

# Required for httpclient HTTPS (Telegram API, Zhipu API).
switch("define", "ssl")

# PostgreSQL + pgvector + Apache AGE backend (opt-in).
# Build with: nimble build -d:withPostgres
# Requires libpq installed: apt install libpq-dev  (Debian/Ubuntu)
#                            apk add postgresql-dev  (Alpine)
when defined(withPostgres):
  switch("passL", "-lpq")
