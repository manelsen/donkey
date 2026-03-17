//! Path resolution, mount detection, and home persistence directories.

use std::{
    collections::{HashMap, HashSet},
    path::{Path as FsPath, PathBuf},
    sync::{Mutex, OnceLock},
};

use tracing::{debug, warn};

use {
    super::{
        containers::{is_cli_available, is_docker_daemon_available, should_use_docker_backend},
        types::{HomePersistence, SandboxConfig, SandboxId, sanitize_path_component},
    },
    crate::error::Result,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ContainerMount {
    ...
}

pub(crate) static HOST_DATA_DIR_CACHE: OnceLock<Mutex<HashMap<String, PathBuf>>> = OnceLock::new();
#[cfg(test)]
pub(crate) static TEST_CONTAINER_MOUNT_OVERRIDES: OnceLock<
    Mutex<HashMap<String, Vec<ContainerMount>>>,
> = OnceLock::new();

pub(crate) fn configured_host_data_dir(config: &SandboxConfig) -> Option<PathBuf> {
    ...
}

pub(crate) fn read_trimmed_file(path: &str) -> Option<String> {
    ...
}

pub(crate) fn normalize_cgroup_container_ref(segment: &str) -> Option<String> {
    ...
}

pub(crate) fn current_container_references() -> Vec<String> {
    ...
}

pub(crate) fn parse_container_mounts_from_inspect(stdout: &str) -> Vec<ContainerMount> {
    ...
}

pub(crate) fn resolve_host_path_from_mounts(
    guest_path: &FsPath,
    mounts: &[ContainerMount],
) -> Option<PathBuf> {
    ...
}

#[cfg(test)]
pub(crate) fn test_container_mount_override_key(cli: &str, reference: &str) -> String {
    ...
}

pub(crate) fn inspect_current_container_mounts(cli: &str, reference: &str) -> Vec<ContainerMount> {
    ...
}

pub(crate) fn detect_host_data_dir_with_references(
    cli: &str,
    guest_data_dir: &FsPath,
    references: &[String],
) -> Option<PathBuf> {
    ...
}

pub(crate) fn host_data_dir_cache() -> &'static Mutex<HashMap<String, PathBuf>> {
    ...
}

pub(crate) fn detect_host_data_dir(cli: &str, guest_data_dir: &FsPath) -> Option<PathBuf> {
    ...
}

pub(crate) fn detected_container_cli(config: &SandboxConfig) -> Option<&'static str> {
    ...
}

pub(crate) fn host_visible_data_dir(config: &SandboxConfig, cli: Option<&str>) -> PathBuf {
    ...
}

pub(crate) fn host_visible_path(
    config: &SandboxConfig,
    cli: Option<&str>,
    path: &FsPath,
) -> PathBuf {
    ...
}

pub(crate) fn sandbox_home_persistence_base_dir(
    config: &SandboxConfig,
    cli: Option<&str>,
) -> PathBuf {
    ...
}

pub(crate) fn default_shared_home_dir(config: &SandboxConfig, cli: Option<&str>) -> PathBuf {
    ...
}

pub(crate) fn resolve_shared_home_dir(config: &SandboxConfig, cli: Option<&str>) -> PathBuf {
    ...
}

/// Effective host path used when shared home persistence is enabled.
pub fn shared_home_dir_path(config: &SandboxConfig) -> PathBuf {
    ...
}

pub(crate) fn sandbox_home_persistence_host_dir(
    config: &SandboxConfig,
    cli: Option<&str>,
    id: &SandboxId,
) -> Option<PathBuf> {
    ...
}

pub(crate) fn guest_visible_sandbox_home_persistence_host_dir(
    config: &SandboxConfig,
    id: &SandboxId,
) -> Option<PathBuf> {
    ...
}

pub(crate) fn ensure_sandbox_home_persistence_host_dir(
    config: &SandboxConfig,
    cli: Option<&str>,
    id: &SandboxId,
) -> Result<Option<PathBuf>> {
    ...
}
