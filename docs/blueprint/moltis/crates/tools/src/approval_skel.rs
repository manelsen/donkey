use std::{collections::HashSet, sync::Arc, time::Duration};

use {
    crate::error::Error,
    regex::RegexSet,
    serde::{Deserialize, Serialize},
    tokio::sync::{RwLock, oneshot},
    tracing::{debug, warn},
};

use crate::Result;

/// Outcome of an approval request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ApprovalDecision {
    ...
}

/// Approval mode.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
#[derive(Default)]
pub enum ApprovalMode {
    ...
}

impl ApprovalMode {
    /// Parse approval mode from config value.
    ///
    /// Accepts canonical values plus legacy aliases:
    /// - `on-miss` / `smart` -> `OnMiss`
    /// - `off` / `never` -> `Off`
    pub fn parse(value: &str) -> Option<Self> {
}

/// Security level for exec commands.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum SecurityLevel {
    ...
}

impl SecurityLevel {
    /// Parse security level from config value.
    ///
    /// Accepts canonical values plus schema aliases:
    /// - `allowlist` -> `Allowlist`
    /// - `permissive` / `full` -> `Full`
    /// - `strict` / `deny` -> `Deny`
    pub fn parse(value: &str) -> Option<Self> {
}

/// Well-known safe binaries that don't need approval.
pub const SAFE_BINS: &[&str] = &[
    "cat",
    "echo",
    "printf",
    "head",
    "tail",
    "wc",
    "sort",
    "uniq",
    "cut",
    "tr",
    "grep",
    "egrep",
    "fgrep",
    "awk",
    "sed",
    "jq",
    "yq",
    "date",
    "cal",
    "ls",
    "pwd",
    "whoami",
    "hostname",
    "uname",
    "env",
    "printenv",
    "basename",
    "dirname",
    "realpath",
    "readlink",
    "diff",
    "comm",
    "paste",
    "tee",
    "xargs",
    "true",
    "false",
    "test",
    "[",
    "seq",
    "yes",
    "rev",
    "fold",
    "expand",
    "unexpand",
    "md5sum",
    "sha256sum",
    "sha1sum",
    "b2sum",
    "file",
    "stat",
    "du",
    "df",
    "free",
    "which",
    "type",
    "command",
];

/// Dangerous command patterns that force approval even when `approval_mode` is
/// off or `security_level` is full.  Each entry: `(regex_pattern, description)`.
static DANGEROUS_PATTERN_DEFS: &[(&str, &str)] = &[
    // Filesystem destruction
    (
        r"rm\s+(-\S*[rR]\S*\s+)*/(\s|$|\*)",
        "rm -r on filesystem root",
    ),
    (
        r"rm\s+(-\S*[rR]\S*\s+)+(~|\$HOME)",
        "rm -r on home directory",
    ),
    (r"\bmkfs\b", "make filesystem"),
    (
        r"\bdd\b.*\bif=/dev/(zero|urandom)\b",
        "disk overwrite with dd",
    ),
    (r":\(\)\s*\{.*\|.*&\s*\}\s*;", "fork bomb"),
    // Git destructive operations
    (r"git\s+reset\s+--hard", "git reset --hard"),
    (
        r"git\s+push\s+.*(-\S*f\S*|--force\b|--force-with-lease\b)",
        "git force push",
    ),
    (r"git\s+clean\s+(-\S*f)", "git clean with force"),
    (r"git\s+stash\s+(drop|clear)\b", "git stash drop/clear"),
    // Database destruction
    (
        r"(?i)\bDROP\s+(TABLE|DATABASE|SCHEMA)\b",
        "DROP TABLE/DATABASE",
    ),
    (r"(?i)\bTRUNCATE\b", "TRUNCATE"),
    // Container / infrastructure destruction
    (r"docker\s+system\s+prune", "docker system prune"),
    (r"kubectl\s+delete\s+namespace", "kubectl delete namespace"),
    (r"terraform\s+destroy", "terraform destroy"),
    // System-level danger
    (
        r"chmod\s+(-\S*R\S*\s+)*777\s+/",
        "recursive chmod 777 on root",
    ),
];

static DANGEROUS_SET: std::sync::LazyLock<RegexSet> = std::sync::LazyLock::new(|| {
    RegexSet::new(DANGEROUS_PATTERN_DEFS.iter().map(|(p, _)| *p))
        .unwrap_or_else(|e| panic!("built-in dangerous patterns must be valid regex: {e}"))
});

/// Check if a command matches any dangerous pattern.
/// Returns the description of the first matching pattern.
pub fn check_dangerous(command: &str) -> Option<&'static str> {
    ...
}

/// Extract the first command/binary from a shell command string.
fn extract_first_bin(command: &str) -> Option<&str> {
    ...
}

/// Check if a command is on the safe bins list.
pub fn is_safe_command(command: &str) -> bool {
    ...
}

/// Check if a command matches any pattern in an allowlist.
pub fn matches_allowlist(command: &str, allowlist: &[String]) -> bool {
    ...
}

/// Pending approval request waiting for gateway resolution.
struct PendingApproval {
    ...
}

/// The approval manager handles approval flow for exec commands.
pub struct ApprovalManager {
    ...
}

impl Default for ApprovalManager {
    fn default() -> Self {
}

impl ApprovalManager {
    /// Decide whether a command needs approval.
    /// Returns Ok(()) if the command can proceed, Err if denied.
    pub async fn check_command(&self, command: &str) -> Result<ApprovalAction> {

    /// Register a pending approval request. Returns an ID and a receiver for the decision.
    pub async fn create_request(
        &self,
        command: &str,
    ) -> (String, oneshot::Receiver<ApprovalDecision>) {
    ...
}

    /// Resolve a pending approval request.
    pub async fn resolve(&self, id: &str, decision: ApprovalDecision, command: Option<&str>) {
    ...
}

    /// Return the IDs of all pending approval requests.
    pub async fn pending_ids(&self) -> Vec<String> {
    ...
}

    /// Wait for an approval decision with timeout.
    pub async fn wait_for_decision(
        &self,
        rx: oneshot::Receiver<ApprovalDecision>,
    ) -> ApprovalDecision {
    ...
}
}

/// Action to take after checking approval.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApprovalAction {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_is_safe_command() {
    ...
}

    #[test]
    fn test_allowlist_matching() {
    ...
}

    #[test]
    fn test_parse_approval_mode_aliases() {
    ...
}

    #[test]
    fn test_parse_security_level_aliases() {
    ...
}

    #[tokio::test]
    async fn test_approval_off_mode() {
    ...
}

    #[tokio::test]
    async fn test_approval_always_mode() {
    ...
}

    #[tokio::test]
    async fn test_approval_on_miss_safe() {
    ...
}

    #[tokio::test]
    async fn test_approval_on_miss_unsafe() {
    ...
}

    #[tokio::test]
    async fn test_deny_security_level() {
    ...
}

    // --- Dangerous pattern detection ---

    #[test]
    fn test_dangerous_rm_rf_root() {
    ...
}

    #[test]
    fn test_dangerous_rm_rf_home() {
    ...
}

    #[test]
    fn test_dangerous_git_reset_hard() {
    ...
}

    #[test]
    fn test_dangerous_git_force_push() {
    ...
}

    #[test]
    fn test_dangerous_drop_table() {
    ...
}

    #[test]
    fn test_dangerous_mkfs() {
    ...
}

    #[test]
    fn test_dangerous_docker_prune() {
    ...
}

    #[test]
    fn test_dangerous_truncate() {
    ...
}

    #[test]
    fn test_dangerous_terraform_destroy() {
    ...
}

    #[test]
    fn test_dangerous_git_clean_force() {
    ...
}

    #[test]
    fn test_dangerous_git_stash_drop() {
    ...
}

    #[test]
    fn test_safe_commands_not_flagged() {
    ...
}

    #[tokio::test]
    async fn test_dangerous_overridden_by_allowlist() {
    ...
}

    #[tokio::test]
    async fn test_dangerous_forces_approval_when_mode_off() {
    ...
}

    #[tokio::test]
    async fn test_dangerous_forces_approval_when_full() {
    ...
}
}
