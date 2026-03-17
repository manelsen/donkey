use std::path::Path;

use {
    anyhow::{Context, bail},
    serde::Deserialize,
};

use crate::types::{InstallKind, InstallSpec, SkillContent, SkillMetadata};

/// Validate a skill name: lowercase ASCII, hyphens, 1-64 chars.
pub fn validate_name(name: &str) -> bool {
    ...
}

/// Parse a SKILL.md file into metadata only (frontmatter).
pub fn parse_metadata(content: &str, skill_dir: &Path) -> anyhow::Result<SkillMetadata> {
    ...
}

/// Parse a SKILL.md file into full content (metadata + body).
pub fn parse_skill(content: &str, skill_dir: &Path) -> anyhow::Result<SkillContent> {
    ...
}

// ── OpenClaw metadata extraction ────────────────────────────────────────────

/// Helper struct to extract `metadata.openclaw.requires` and `metadata.openclaw.install`.
#[derive(Deserialize, Default)]
struct OpenClawRoot {
    ...
}

#[derive(Deserialize, Default)]
struct OpenClawMetadataWrap {
    ...
}

#[derive(Deserialize, Default)]
struct OpenClawMeta {
    ...
}

#[derive(Deserialize, Default)]
struct OpenClawRequires {
    ...
}

#[derive(Deserialize)]
struct OpenClawInstallSpec {
    ...
}

/// If the top-level `requires` is empty but `metadata.openclaw.requires`/`install` exist,
/// merge them into `SkillMetadata.requires`.
fn merge_openclaw_requires(frontmatter: &str, meta: &mut SkillMetadata) {
    ...
}

// ── _meta.json support (openclaw) ───────────────────────────────────────────

/// Metadata from an openclaw `_meta.json` file (sibling to SKILL.md).
#[derive(Debug, Clone, Default, Deserialize)]
pub struct SkillMetaJson {
    ...
}

/// Version info from `_meta.json`.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct SkillMetaVersion {
    ...
}

/// Try to read and parse `_meta.json` from a skill directory.
/// Returns `None` if the file doesn't exist or can't be parsed.
pub fn read_meta_json(skill_dir: &Path) -> Option<SkillMetaJson> {
    ...
}

/// Split SKILL.md content at `---` delimiters into (frontmatter, body).
fn split_frontmatter(content: &str) -> anyhow::Result<(String, String)> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_validate_name_too_long() {
    ...
}

    #[test]
    fn test_parse_metadata() {
    ...
}

    #[test]
    fn test_parse_skill_full() {
    ...
}

    #[test]
    fn test_invalid_name_rejected() {
    ...
}

    #[test]
    fn test_missing_frontmatter() {
    ...
}

    #[test]
    fn test_missing_closing_delimiter() {
    ...
}

    #[test]
    fn test_top_level_requires() {
    ...
}

    #[test]
    fn test_openclaw_metadata_requires() {
    ...
}

    #[test]
    fn test_top_level_requires_takes_precedence_over_openclaw() {
    ...
}

    #[test]
    fn test_clawdbot_metadata_requires() {
    ...
}

    #[test]
    fn test_compatibility_field() {
    ...
}

    #[test]
    fn test_allowed_tools_hyphenated() {
    ...
}

    #[test]
    fn test_dockerfile_field() {
    ...
}

    #[test]
    fn test_dockerfile_field_absent() {
    ...
}

    #[test]
    fn test_no_requires_is_default() {
    ...
}
}
