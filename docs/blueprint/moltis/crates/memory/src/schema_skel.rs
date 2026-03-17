//! Row types for the memory database and migration runner.

/// A tracked file row.
#[derive(Debug, Clone)]
pub struct FileRow {
    ...
}

/// A chunk row.
#[derive(Debug, Clone)]
pub struct ChunkRow {
    ...
}

/// Run database migrations for the memory system.
///
/// This creates the `files`, `chunks`, `embedding_cache` tables and the
/// `chunks_fts` full-text search virtual table. Memory uses its own database
/// (`memory.db`) separate from the main `moltis.db`.
pub async fn run_migrations(pool: &sqlx::SqlitePool) -> anyhow::Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
}
