use {clap::Subcommand, std::path::PathBuf};

#[derive(Subcommand)]
pub enum DbAction {
    ...
}

/// Returns the paths to the database files.
fn db_paths() -> (PathBuf, PathBuf) {
    ...
}

pub async fn handle_db(action: DbAction) -> anyhow::Result<()> {
    ...
}

/// Delete all database files completely.
async fn reset_databases() -> anyhow::Result<()> {
    ...
}

/// Clear all data from tables but keep the schema intact.
async fn clear_databases() -> anyhow::Result<()> {
    ...
}

/// Run all pending database migrations.
async fn run_migrations() -> anyhow::Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
