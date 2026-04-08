`sqlite-vec` vendor directory.

Expected layout:

- `vendor/sqlite-vec/linux-x86_64/vec0.so`
- `vendor/sqlite-vec/linux-aarch64/vec0.so`
- `vendor/sqlite-vec/macos-x86_64/vec0.dylib`
- `vendor/sqlite-vec/macos-aarch64/vec0.dylib`
- `vendor/sqlite-vec/windows-x86_64/vec0.dll`

Populate it with:

```bash
./scripts/vendor_sqlite_vec.sh
```

Runtime resolution order:

1. `DONKEY_SQLITE_VEC_PATH`
2. legacy `DONKEY_SQLITE_VECTOR_PATH`
3. autodiscovery under `vendor/sqlite-vec/<platform>/`

Upstream:

- <https://github.com/asg017/sqlite-vec>
