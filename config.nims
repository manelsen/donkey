# Makes `src/` visible to all nim compilations in this project,
# including testament test files in tests/.
switch("path", "src")

# Required for httpclient HTTPS (Telegram API, Zhipu API).
switch("define", "ssl")
