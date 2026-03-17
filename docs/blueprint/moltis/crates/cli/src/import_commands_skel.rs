//! CLI subcommand for importing data from an OpenClaw installation.

use clap::Subcommand;

#[derive(Subcommand)]
pub enum ImportAction {
    ...
}

pub async fn handle_import(action: ImportAction) -> anyhow::Result<()> {
    ...
}

fn handle_detect(json_output: bool) -> anyhow::Result<()> {
    ...
}

fn handle_import_all(dry_run: bool, json_output: bool) -> anyhow::Result<()> {
    ...
}

fn handle_import_select(
    categories: &[String],
    dry_run: bool,
    json_output: bool,
) -> anyhow::Result<()> {
    ...
}

struct ParsedSelection {
    ...
}

fn parse_selection(categories: &[String], warn_unknown: bool) -> ParsedSelection {
    ...
}

fn print_json(value: serde_json::Value) -> anyhow::Result<()> {
    ...
}

fn print_scan_item(name: &str, available: bool, detail: Option<String>) {
    ...
}

fn print_scan_summary(scan: &moltis_openclaw_import::ImportScan) {
    ...
}

fn print_selection(sel: &moltis_openclaw_import::ImportSelection) {
    ...
}

fn format_channel_scan_detail(scan: &moltis_openclaw_import::ImportScan) -> Option<String> {
    ...
}

fn print_report(report: &moltis_openclaw_import::report::ImportReport) {
    ...
}
