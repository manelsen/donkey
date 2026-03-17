//! Import skills from OpenClaw to Moltis.
//!
//! OpenClaw skills use the SKILL.md format that Moltis already parses.
//! This module copies skill directories, skipping duplicates.

use std::path::{Path, PathBuf};

use tracing::{debug, warn};

use crate::{
    detect::OpenClawDetection,
    report::{CategoryReport, ImportCategory, ImportStatus},
};

/// Discovered skill ready for import.
#[derive(Debug, Clone)]
pub struct DiscoveredSkill {
    ...
}

/// Scan OpenClaw for importable skills.
pub fn discover_skills(detection: &OpenClawDetection) -> Vec<DiscoveredSkill> {
    ...
}

fn scan_skill_dir(dir: &Path, is_workspace: bool, skills: &mut Vec<DiscoveredSkill>) {
    ...
}

/// Import discovered skills into the Moltis skills directory.
///
/// `dest_skills_dir` is typically `~/.moltis/skills/`.
pub fn import_skills(detection: &OpenClawDetection, dest_skills_dir: &Path) -> CategoryReport {
    ...
}

/// Recursively copy a directory.
fn copy_dir_recursive(src: &Path, dest: &Path) -> crate::error::Result<()> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    fn make_detection(home: &Path) -> OpenClawDetection {
    ...
}

    #[test]
    fn discover_finds_valid_skills() {
    ...
}

    #[test]
    fn import_copies_skill_directories() {
    ...
}

    #[test]
    fn import_skips_existing() {
    ...
}

    #[test]
    fn import_no_skills_returns_skipped() {
    ...
}
}
