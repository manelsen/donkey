//! Browser detection and install guidance.

use std::{
    collections::HashSet,
    path::{Path, PathBuf},
    time::Duration,
};

use crate::types::{BrowserKind, BrowserPreference};

/// Executable names mapped to known Chromium-family browser kinds.
#[derive(Debug, Clone, Copy)]
struct BrowserExecutable {
    ...
}

/// Known Chromium-based browser executable names to search for.
/// All of these support CDP (Chrome DevTools Protocol).
const CHROMIUM_EXECUTABLES: &[BrowserExecutable] = &[
    // Chrome
    BrowserExecutable {
        kind: BrowserKind::Chrome,
        name: "chrome",
    },
    BrowserExecutable {
        kind: BrowserKind::Chrome,
        name: "chrome-browser",
    },
    BrowserExecutable {
        kind: BrowserKind::Chrome,
        name: "google-chrome",
    },
    BrowserExecutable {
        kind: BrowserKind::Chrome,
        name: "google-chrome-stable",
    },
    // Chromium
    BrowserExecutable {
        kind: BrowserKind::Chromium,
        name: "chromium",
    },
    BrowserExecutable {
        kind: BrowserKind::Chromium,
        name: "chromium-browser",
    },
    // Microsoft Edge
    BrowserExecutable {
        kind: BrowserKind::Edge,
        name: "msedge",
    },
    BrowserExecutable {
        kind: BrowserKind::Edge,
        name: "microsoft-edge",
    },
    BrowserExecutable {
        kind: BrowserKind::Edge,
        name: "microsoft-edge-stable",
    },
    // Brave
    BrowserExecutable {
        kind: BrowserKind::Brave,
        name: "brave",
    },
    BrowserExecutable {
        kind: BrowserKind::Brave,
        name: "brave-browser",
    },
    // Opera
    BrowserExecutable {
        kind: BrowserKind::Opera,
        name: "opera",
    },
    // Vivaldi
    BrowserExecutable {
        kind: BrowserKind::Vivaldi,
        name: "vivaldi",
    },
    BrowserExecutable {
        kind: BrowserKind::Vivaldi,
        name: "vivaldi-stable",
    },
];

#[cfg(any(target_os = "macos", target_os = "windows"))]
#[derive(Debug, Clone, Copy)]
struct BrowserPath {
    ...
}

/// macOS app bundle paths for Chromium-based browsers.
#[cfg(target_os = "macos")]
const MACOS_APP_PATHS: &[BrowserPath] = &[
    BrowserPath {
        kind: BrowserKind::Chrome,
        path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    },
    BrowserPath {
        kind: BrowserKind::Chromium,
        path: "/Applications/Chromium.app/Contents/MacOS/Chromium",
    },
    BrowserPath {
        kind: BrowserKind::Edge,
        path: "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    },
    BrowserPath {
        kind: BrowserKind::Brave,
        path: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    },
    BrowserPath {
        kind: BrowserKind::Opera,
        path: "/Applications/Opera.app/Contents/MacOS/Opera",
    },
    BrowserPath {
        kind: BrowserKind::Vivaldi,
        path: "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi",
    },
    BrowserPath {
        kind: BrowserKind::Arc,
        path: "/Applications/Arc.app/Contents/MacOS/Arc",
    },
];

/// Windows installation paths for Chromium-based browsers.
#[cfg(target_os = "windows")]
const WINDOWS_PATHS: &[BrowserPath] = &[
    BrowserPath {
        kind: BrowserKind::Chrome,
        path: r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    },
    BrowserPath {
        kind: BrowserKind::Chrome,
        path: r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    },
    BrowserPath {
        kind: BrowserKind::Edge,
        path: r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    },
    BrowserPath {
        kind: BrowserKind::Brave,
        path: r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
    },
];

/// Where a detected browser path came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DetectionSource {
    ...
}

/// One detected browser candidate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetectedBrowser {
    ...
}

/// Result of browser detection.
#[derive(Debug, Clone)]
pub struct DetectionResult {
    ...
}

impl DetectionResult {
    #[must_use]
    pub fn found(&self) -> bool {
}

fn infer_kind_from_path(path: &Path) -> BrowserKind {
    ...
}

fn push_browser(
    browsers: &mut Vec<DetectedBrowser>,
    seen_paths: &mut HashSet<PathBuf>,
    kind: BrowserKind,
    path: PathBuf,
    source: DetectionSource,
) {
    ...
}

/// Detect all Chromium-based browsers available on the system.
///
/// Checks (in order):
/// 1. Custom path from config (if provided)
/// 2. CHROME environment variable
/// 3. Platform-specific installation paths (macOS app bundles, Windows paths)
/// 4. Known executable names in PATH (fallback)
#[must_use]
pub fn detect_browsers(custom_path: Option<&str>) -> Vec<DetectedBrowser> {
    ...
}

/// Detect available browsers and include install guidance when empty.
#[must_use]
pub fn detect_browser(custom_path: Option<&str>) -> DetectionResult {
    ...
}

/// Select a browser from detected candidates based on request preference.
#[must_use]
pub fn pick_browser(
    browsers: &[DetectedBrowser],
    preference: Option<BrowserPreference>,
) -> Option<DetectedBrowser> {
    ...
}

/// Convert detected browser kinds into a readable list.
#[must_use]
pub fn installed_browser_labels(browsers: &[DetectedBrowser]) -> Vec<String> {
    ...
}

/// Result of a best-effort browser auto-install attempt.
#[derive(Debug, Clone)]
pub struct AutoInstallResult {
    ...
}

#[derive(Debug, Clone)]
struct InstallCommand {
    ...
}

impl InstallCommand {
    fn new(program: &'static str, args: &[&'static str]) -> Self {

    fn display(&self) -> String {
    ...
}
}

fn install_targets_for_preference(preference: BrowserPreference) -> Vec<BrowserKind> {
    ...
}

#[cfg(target_os = "macos")]
fn macos_install_commands(target: BrowserKind) -> Vec<InstallCommand> {
    ...
}

#[cfg(target_os = "linux")]
fn linux_package_candidates(target: BrowserKind) -> Vec<&'static str> {
    ...
}

#[cfg(target_os = "windows")]
fn windows_package_ids(target: BrowserKind) -> Vec<&'static str> {
    ...
}

#[derive(Debug, thiserror::Error)]
#[error("{message}")]
struct InstallError {
    ...
}

impl InstallError {
    #[must_use]
    fn message(message: impl std::fmt::Display) -> Self {
}

type InstallResult<T> = Result<T, InstallError>;

async fn run_command(command: &InstallCommand) -> InstallResult<()> {
    ...
}

#[cfg(target_os = "linux")]
async fn run_with_optional_sudo(command: InstallCommand) -> InstallResult<()> {
    ...
}

#[cfg(target_os = "macos")]
async fn auto_install_for_targets(targets: &[BrowserKind]) -> AutoInstallResult {
    ...
}

#[cfg(target_os = "linux")]
struct LinuxPkgManager {
    ...
}

#[cfg(target_os = "linux")]
const LINUX_PKG_MANAGERS: &[LinuxPkgManager] = &[
    LinuxPkgManager {
        bin: "apt-get",
        install_args: &["install", "-y", "-qq"],
        pre_install: Some(&["update", "-qq"]),
    },
    LinuxPkgManager {
        bin: "dnf",
        install_args: &["install", "-y"],
        pre_install: None,
    },
    LinuxPkgManager {
        bin: "pacman",
        install_args: &["-S", "--noconfirm"],
        pre_install: None,
    },
];

#[cfg(target_os = "linux")]
async fn auto_install_for_targets(targets: &[BrowserKind]) -> AutoInstallResult {
    ...
}

#[cfg(target_os = "windows")]
async fn auto_install_for_targets(targets: &[BrowserKind]) -> AutoInstallResult {
    ...
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
async fn auto_install_for_targets(_targets: &[BrowserKind]) -> AutoInstallResult {
    ...
}

/// Attempt to auto-install a browser when none are detected.
///
/// This is best-effort only. On failure, callers should still return explicit
/// install instructions.
pub async fn auto_install_browser(preference: BrowserPreference) -> AutoInstallResult {
    ...
}

/// Get platform-specific install instructions.
#[must_use]
pub fn install_instructions() -> String {
    ...
}

/// Check browser availability and warn if not found.
///
/// Call this at startup when browser is enabled. Prints a visible warning
/// to stderr and logs via tracing for log file capture.
pub fn check_and_warn(custom_path: Option<&str>) -> bool {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_install_instructions_platform_specific() {
    ...
}

    #[test]
    fn test_detect_with_invalid_custom_path() {
    ...
}

    #[test]
    fn test_detect_custom_path_takes_precedence() {
    ...
}

    #[test]
    fn test_chromium_executables_list_not_empty() {
    ...
}

    #[test]
    fn test_pick_browser_auto_uses_first() {
    ...
}

    #[test]
    fn test_pick_browser_specific() {
    ...
}

    #[test]
    fn test_pick_browser_missing_specific_returns_none() {
    ...
}

    #[test]
    fn test_installed_browser_labels_dedupes_kinds() {
    ...
}

    // --- infer_kind_from_path tests ---

    #[test]
    fn test_infer_chrome_from_path() {
    ...
}

    #[test]
    fn test_infer_chromium_from_path() {
    ...
}

    #[test]
    fn test_infer_brave_from_path() {
    ...
}

    #[test]
    fn test_infer_edge_from_path() {
    ...
}

    #[test]
    fn test_infer_opera_from_path() {
    ...
}

    #[test]
    fn test_infer_vivaldi_from_path() {
    ...
}

    #[test]
    fn test_infer_arc_from_path() {
    ...
}

    #[test]
    fn test_infer_custom_from_unknown_path() {
    ...
}

    #[test]
    fn test_infer_brave_not_confused_with_chrome() {
    ...
}

    #[test]
    fn test_infer_chromium_before_chrome() {
    ...
}

    // --- install_targets_for_preference tests ---

    #[test]
    fn test_install_targets_auto_returns_multiple() {
    ...
}

    #[test]
    fn test_install_targets_specific_returns_single() {
    ...
}

    // --- platform install command mapping tests ---

    #[cfg(target_os = "macos")]
    #[test]
    fn test_macos_install_commands_chrome() {
    ...
}

    #[cfg(target_os = "macos")]
    #[test]
    fn test_macos_install_commands_custom_is_empty() {
    ...
}

    #[cfg(target_os = "linux")]
    #[test]
    fn test_linux_package_candidates_chrome() {
    ...
}

    #[cfg(target_os = "linux")]
    #[test]
    fn test_linux_package_candidates_custom_is_empty() {
    ...
}

    #[cfg(target_os = "windows")]
    #[test]
    fn test_windows_package_ids_chrome() {
    ...
}

    #[cfg(target_os = "windows")]
    #[test]
    fn test_windows_package_ids_custom_is_empty() {
    ...
}
}
