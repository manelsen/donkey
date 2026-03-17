use clap::Subcommand;

#[derive(Subcommand)]
pub enum MemoryAction {
    ...
}

pub async fn handle_memory(action: MemoryAction) -> anyhow::Result<()> {
    ...
}

/// Resolve the memory.db path using the data directory.
fn memory_db_path() -> std::path::PathBuf {
    ...
}

/// Open a read-only SQLite connection pool to memory.db.
async fn open_memory_pool() -> anyhow::Result<sqlx::SqlitePool> {
    ...
}

async fn search_memory(query: &str, limit: usize, json: bool) -> anyhow::Result<()> {
    ...
}

fn print_json(results: &[moltis_memory::search::SearchResult]) -> anyhow::Result<()> {
    ...
}

fn print_human(results: &[moltis_memory::search::SearchResult]) {
    ...
}

async fn show_status() -> anyhow::Result<()> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn test_search_missing_db() {
    ...
}

    #[tokio::test]
    async fn test_search_with_results() {
    ...
}

    #[tokio::test]
    async fn test_search_no_results() {
    ...
}

    #[tokio::test]
    async fn test_status_missing_db() {
    ...
}

    #[tokio::test]
    async fn test_status_with_db() {
    ...
}

    #[test]
    fn test_print_json_output() {
    ...
}

    #[test]
    fn test_print_human_output() {
    ...
}
}
