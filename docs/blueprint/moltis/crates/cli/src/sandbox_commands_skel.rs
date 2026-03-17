use {anyhow::Result, clap::Subcommand};

use moltis_tools::sandbox;

fn sanitize_instance_slug(name: &str) -> String {
    ...
}

fn instance_sandbox_prefix(config: &moltis_config::MoltisConfig) -> String {
    ...
}

#[derive(Subcommand)]
pub enum SandboxAction {
    ...
}

pub async fn handle_sandbox(action: SandboxAction) -> Result<()> {
    ...
}

fn image_build_not_supported_notice(backend: &str) -> Option<(&'static str, &'static str)> {
    ...
}

async fn list() -> Result<()> {
    ...
}

async fn build() -> Result<()> {
    ...
}

async fn remove(tag: &str) -> Result<()> {
    ...
}

async fn clean() -> Result<()> {
    ...
}

#[cfg(test)]
mod tests {
