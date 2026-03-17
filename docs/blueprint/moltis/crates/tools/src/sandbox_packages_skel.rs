//! `sandbox_packages` tool — lists packages pre-installed in the sandbox
//! container, grouped by category.
//!
//! The LLM calls this tool before running commands that need specific tools
//! (image processing, audio/video, document conversion, GIS, etc.) to check
//! what's available, instead of bloating every system prompt with the full
//! package list.
//!
//! **Hybrid mode**: the tool always returns the configured package list
//! (categorized).  When a sandbox container is already running for the
//! current session it also queries `dpkg-query` inside the container and
//! reports any extra packages that were installed at runtime.

use std::{collections::HashSet, sync::Arc};

use {
    async_trait::async_trait,
    serde_json::{Value, json},
    tracing::debug,
};

#[cfg(feature = "metrics")]
use moltis_metrics::{counter, histogram};

use moltis_agents::tool_registry::AgentTool;

use crate::{exec::ExecOpts, sandbox::SandboxRouter};

// ── Category mapping ────────────────────────────────────────────────────────

/// Static mapping of package names to categories.
///
/// Order matters: first match wins. Packages not matching any entry end up
/// in "Other". Library/dev/font packages are filtered out before
/// categorization (see [`is_infrastructure_package`]).
const CATEGORY_MAP: &[(&str, &[&str])] = &[
    ("Networking", &[
        "curl",
        "wget",
        "ca-certificates",
        "dnsutils",
        "netcat-openbsd",
        "openssh-client",
        "iproute2",
        "net-tools",
    ]),
    ("Languages", &[
        "python3",
        "python3-pip",
        "python3-venv",
        "python-is-python3",
        "nodejs",
        "npm",
        "ruby",
        "golang-go",
    ]),
    ("Build tools", &[
        "build-essential",
        "clang",
        "pkg-config",
        "autoconf",
        "automake",
        "libtool",
        "bison",
        "flex",
        "dpkg-dev",
        "fakeroot",
    ]),
    ("Compression", &[
        "zip",
        "unzip",
        "bzip2",
        "xz-utils",
        "p7zip-full",
        "tar",
        "zstd",
        "lz4",
        "pigz",
    ]),
    ("CLI utilities", &[
        "git",
        "gnupg2",
        "jq",
        "rsync",
        "file",
        "tree",
        "sqlite3",
        "sudo",
        "locales",
        "tzdata",
        "shellcheck",
        "patchelf",
        "tmux",
    ]),
    ("Text processing", &["ripgrep", "fd-find", "yq"]),
    ("Browser automation", &["chromium"]),
    ("Image processing", &[
        "imagemagick",
        "graphicsmagick",
        "libvips-tools",
        "pngquant",
        "optipng",
        "jpegoptim",
        "webp",
        "libimage-exiftool-perl",
    ]),
    ("Audio/video", &[
        "ffmpeg",
        "sox",
        "lame",
        "flac",
        "vorbis-tools",
        "opus-tools",
        "mediainfo",
    ]),
    ("Documents", &[
        "pandoc",
        "poppler-utils",
        "ghostscript",
        "texlive-latex-base",
        "texlive-latex-extra",
        "texlive-fonts-recommended",
        "antiword",
        "catdoc",
        "unrtf",
        "libreoffice-core",
        "libreoffice-writer",
    ]),
    ("Data processing", &[
        "csvtool",
        "xmlstarlet",
        "html2text",
        "dos2unix",
        "miller",
        "datamash",
    ]),
    ("GIS/maps", &[
        "gdal-bin",
        "mapnik-utils",
        "osm2pgsql",
        "osmium-tool",
        "osmctools",
        "python3-mapnik",
    ]),
    ("CalDAV/CardDAV", &["vdirsyncer", "khal", "python3-caldav"]),
    ("Email", &[
        "isync",
        "offlineimap3",
        "notmuch",
        "notmuch-mutt",
        "aerc",
        "mutt",
        "neomutt",
    ]),
    ("Newsgroups (NNTP)", &["tin", "slrn"]),
    ("Messaging APIs", &["python3-discord"]),
];

/// Returns `true` for packages that are infrastructure/library deps and should
/// be hidden from the LLM (they're not directly useful as CLI tools).
fn is_infrastructure_package(pkg: &str) -> bool {
    ...
}

/// Well-known base OS packages that are always present and not useful to list.
const BASE_OS_PACKAGES: &[&str] = &[
    "adduser",
    "apt",
    "base-files",
    "base-passwd",
    "bash",
    "coreutils",
    "dash",
    "debconf",
    "debianutils",
    "diffutils",
    "dpkg",
    "e2fsprogs",
    "findutils",
    "grep",
    "gzip",
    "hostname",
    "init-system-helpers",
    "login",
    "mawk",
    "mount",
    "ncurses-base",
    "ncurses-bin",
    "passwd",
    "perl-base",
    "procps",
    "sed",
    "sensible-utils",
    "sysvinit-utils",
    "tar",
    "ubuntu-keyring",
    "util-linux",
];

/// Categorize a list of packages, filtering out infrastructure deps.
///
/// Returns a sorted list of `(category, packages)` pairs. Packages not
/// matching any known category are grouped under "Other".
fn categorize_packages(packages: &[String]) -> Vec<(&'static str, Vec<&str>)> {
    ...
}

/// Query the sandbox container for installed packages via `dpkg-query`.
///
/// Returns `None` if the container is not reachable (not running, etc.).
async fn query_sandbox_packages(router: &SandboxRouter, session_key: &str) -> Option<Vec<String>> {
    ...
}

/// Filter packages from the sandbox query that are not already in the config
/// list and are not base OS / infrastructure packages.
fn extra_packages(sandbox_pkgs: &[String], config_pkgs: &[String]) -> Vec<String> {
    ...
}

// ── Tool ────────────────────────────────────────────────────────────────────

/// LLM-callable tool that lists sandbox packages grouped by category.
pub struct SandboxPackagesTool {
    ...
}

impl SandboxPackagesTool {
    pub fn new() -> Self {

    /// Attach a sandbox router to read the configured packages.
    pub fn with_sandbox_router(mut self, router: Arc<SandboxRouter>) -> Self {
    ...
}
}

impl Default for SandboxPackagesTool {
    fn default() -> Self {
}

#[async_trait]
impl AgentTool for SandboxPackagesTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> anyhow::Result<Value> {
    ...
}
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    fn make_tool(packages: Vec<String>) -> SandboxPackagesTool {
    ...
}

    #[tokio::test]
    async fn test_list_returns_categorized_packages() {
    ...
}

    #[tokio::test]
    async fn test_filters_library_deps() {
    ...
}

    #[tokio::test]
    async fn test_custom_packages_in_other() {
    ...
}

    #[tokio::test]
    async fn test_no_sandbox_returns_error() {
    ...
}

    #[tokio::test]
    async fn test_empty_packages() {
    ...
}

    #[test]
    fn test_tool_metadata() {
    ...
}

    #[test]
    fn test_categorize_preserves_order_within_category() {
    ...
}

    #[test]
    fn test_is_infrastructure_package() {
    ...
}

    #[test]
    fn test_new_categories_exist() {
    ...
}

    #[test]
    fn test_extra_packages_filters_config_and_base() {
    ...
}

    #[test]
    fn test_extra_packages_empty_when_same() {
    ...
}
}
