#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

#[cfg(any(target_os = "macos", test))]
use super::apple::*;
use {
    super::{containers::*, docker::*, host::*, paths::*, platform::*, router::*, types::*, *},
    crate::{
        error::{Error, Result},
        exec::{ExecOpts, ExecResult},
    },
};

fn clear_host_data_dir_test_state() {
    ...
}

fn set_test_container_mount_override(cli: &str, reference: &str, mounts: Vec<ContainerMount>) {
    ...
}

#[test]
fn test_normalize_cgroup_container_ref() {
    ...
}

#[test]
fn test_parse_container_mounts_from_inspect() {
    ...
}

#[test]
fn test_resolve_host_path_from_mounts_prefers_longest_prefix() {
    ...
}

#[test]
fn test_detect_host_data_dir_with_references_uses_mount_overrides() {
    ...
}

#[test]
fn test_detect_host_data_dir_does_not_cache_missing_result() {
    ...
}

#[test]
fn test_ensure_sandbox_home_persistence_host_dir_propagates_guest_visible_create_error() {
    ...
}

#[test]
fn test_ensure_sandbox_home_persistence_host_dir_allows_translated_create_error() {
    ...
}

struct TestSandbox {
    ...
}

impl TestSandbox {
    fn new(name: &'static str, ensure_ready_error: Option<&str>, exec_error: Option<&str>) -> Self {

    fn ensure_ready_calls(&self) -> usize {
    ...
}

    fn exec_calls(&self) -> usize {
    ...
}
}

#[test]
fn truncate_output_for_display_handles_multibyte_boundary() {
    ...
}

#[async_trait::async_trait]
impl Sandbox for TestSandbox {
    fn backend_name(&self) -> &'static str {

    async fn ensure_ready(&self, _id: &SandboxId, _image_override: Option<&str>) -> Result<()> {
    ...
}

    async fn exec(&self, _id: &SandboxId, _command: &str, _opts: &ExecOpts) -> Result<ExecResult> {
    ...
}

    async fn cleanup(&self, _id: &SandboxId) -> Result<()> {
    ...
}
}

#[test]
fn test_sandbox_mode_display() {
    ...
}

#[test]
fn test_sandbox_scope_display() {
    ...
}

#[test]
fn test_docker_hardening_args_prebuilt() {
    ...
}

#[test]
fn test_docker_hardening_args_not_prebuilt() {
    ...
}

#[test]
fn test_workspace_mount_display() {
    ...
}

#[test]
fn test_home_persistence_display() {
    ...
}

#[test]
fn test_resource_limits_default() {
    ...
}

#[test]
fn test_resource_limits_serde() {
    ...
}

#[test]
fn test_sandbox_config_serde() {
    ...
}

#[test]
fn test_docker_resource_args() {
    ...
}

#[test]
fn test_docker_workspace_args_ro() {
    ...
}

#[test]
fn test_docker_workspace_args_uses_host_data_dir_override() {
    ...
}

#[test]
fn test_docker_workspace_args_none() {
    ...
}

#[test]
fn test_docker_home_persistence_args_off() {
    ...
}

#[test]
fn test_docker_home_persistence_args_default_shared() {
    ...
}

#[test]
fn test_docker_home_persistence_args_default_shared_uses_host_data_dir_override() {
    ...
}

#[test]
fn test_docker_home_persistence_args_custom_shared_absolute_path() {
    ...
}

#[test]
fn test_docker_home_persistence_args_custom_shared_relative_path() {
    ...
}

#[test]
fn test_docker_home_persistence_args_custom_shared_guest_absolute_path_uses_host_override() {
    ...
}

#[test]
fn test_docker_home_persistence_args_session() {
    ...
}

#[test]
fn test_docker_home_persistence_args_session_uses_host_data_dir_override() {
    ...
}

#[test]
fn test_create_sandbox_off_uses_no_sandbox() {
    ...
}

#[tokio::test]
async fn test_no_sandbox_exec() {
    ...
}

#[test]
fn test_docker_container_name() {
    ...
}

/// Helper: build a `SandboxRouter` with a deterministic backend so tests
/// don't depend on the host having Docker / Apple Container installed.
fn router_with_real_backend(config: SandboxConfig) -> SandboxRouter {
    ...
}

#[tokio::test]
async fn test_sandbox_router_default_all() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_mode_off() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_mode_all() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_mode_non_main() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_override() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_override_overrides_mode() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_no_runtime_returns_false() {
    ...
}

#[test]
fn test_backend_name_docker() {
    ...
}

#[test]
fn test_backend_name_podman() {
    ...
}

#[test]
fn test_backend_name_none() {
    ...
}

#[test]
fn test_sandbox_router_backend_name() {
    ...
}

#[test]
fn test_sandbox_router_explicit_docker_backend() {
    ...
}

#[test]
fn test_sandbox_router_config_accessor() {
    ...
}

#[test]
fn test_sandbox_router_sandbox_id_for() {
    ...
}

#[tokio::test]
async fn test_resolve_image_default() {
    ...
}

#[tokio::test]
async fn test_resolve_image_skill_override() {
    ...
}

#[tokio::test]
async fn test_resolve_image_session_override() {
    ...
}

#[tokio::test]
async fn test_resolve_image_skill_beats_session() {
    ...
}

#[tokio::test]
async fn test_resolve_image_config_override() {
    ...
}

#[tokio::test]
async fn test_remove_image_override() {
    ...
}

#[test]
fn test_docker_image_tag_deterministic() {
    ...
}

#[test]
fn test_docker_image_tag_order_independent() {
    ...
}

#[test]
fn test_docker_image_tag_normalizes_whitespace_and_duplicates() {
    ...
}

#[test]
fn test_sandbox_image_dockerfile_creates_home_in_install_layer() {
    ...
}

#[test]
fn test_sandbox_image_dockerfile_installs_gogcli() {
    ...
}

#[test]
fn test_docker_image_tag_changes_with_base() {
    ...
}

#[test]
fn test_docker_image_tag_changes_with_packages() {
    ...
}

#[test]
fn test_rebuildable_sandbox_image_tag_requires_packages() {
    ...
}

#[test]
fn test_rebuildable_sandbox_image_tag_requires_local_repo_prefix() {
    ...
}

#[test]
fn test_rebuildable_sandbox_image_tag_returns_deterministic_tag() {
    ...
}

#[tokio::test]
async fn test_no_sandbox_build_image_is_noop() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_events() {
    ...
}

#[tokio::test]
async fn test_sandbox_router_global_image_override() {
    ...
}

#[cfg(target_os = "macos")]
#[test]
fn test_backend_name_apple_container() {
    ...
}

#[cfg(target_os = "macos")]
#[test]
fn test_sandbox_router_explicit_apple_container_backend() {
    ...
}

#[cfg(target_os = "macos")]
#[tokio::test]
async fn test_apple_container_name_generation_rotation() {
    ...
}

/// When both Docker and Apple Container are available, test that we can
/// explicitly select each one.
#[test]
fn test_select_backend_explicit_choices() {
    ...
}

#[test]
fn test_is_apple_container_service_error() {
    ...
}

#[test]
fn test_is_apple_container_exists_error() {
    ...
}

#[test]
fn test_is_apple_container_unavailable_error() {
    ...
}

#[test]
fn test_should_restart_after_readiness_error() {
    ...
}

#[test]
fn test_apple_container_bootstrap_command_uses_portable_sleep() {
    ...
}

#[test]
fn test_apple_container_run_args_pin_workdir_and_bootstrap_home() {
    ...
}

#[test]
fn test_apple_container_run_args_with_home_volume() {
    ...
}

#[test]
fn test_apple_container_exec_args_pin_workdir_and_bootstrap_home() {
    ...
}

#[test]
fn test_container_exec_shell_args_apple_container_uses_safe_wrapper() {
    ...
}

#[test]
fn test_container_exec_shell_args_docker_keeps_standard_exec_shape() {
    ...
}

#[test]
fn test_apple_container_status_from_inspect() {
    ...
}

#[test]
fn test_is_apple_container_daemon_stale_error() {
    ...
}

#[test]
fn test_is_apple_container_boot_failure() {
    ...
}

#[test]
fn test_is_apple_container_corruption_error() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_switches_from_apple_to_docker() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_switches_on_boot_failure() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_does_not_switch_on_unrelated_error() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_switches_exec_path() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_switches_on_daemon_stale_error() {
    ...
}

#[tokio::test]
async fn test_failover_sandbox_docker_to_wasm() {
    ...
}

#[tokio::test]
async fn test_failover_docker_does_not_switch_on_unrelated_error() {
    ...
}

#[test]
fn test_is_docker_failover_error() {
    ...
}

#[test]
fn test_is_podman_failover_error() {
    ...
}

#[test]
fn test_select_backend_podman() {
    ...
}

#[test]
fn test_select_backend_wasm() {
    ...
}

#[test]
fn test_select_backend_restricted_host() {
    ...
}

#[test]
fn test_is_debian_host() {
    ...
}

#[test]
fn test_host_package_name_candidates_t64_to_base() {
    ...
}

#[test]
fn test_host_package_name_candidates_base_to_t64_for_soname() {
    ...
}

#[test]
fn test_host_package_name_candidates_non_library_stays_single() {
    ...
}

#[tokio::test]
async fn test_provision_host_packages_empty() {
    ...
}

#[tokio::test]
async fn test_provision_host_packages_non_debian() {
    ...
}

#[test]
fn test_is_running_as_root() {
    ...
}

#[test]
fn test_should_use_docker_backend() {
    ...
}

#[test]
fn container_run_state_serializes_lowercase() {
    ...
}

#[test]
fn container_backend_serializes_kebab_case() {
    ...
}

#[test]
fn running_container_serializes_to_json() {
    ...
}

#[test]
fn test_zombie_set_lifecycle() {
    ...
}

// ── NetworkPolicy / proxy wiring tests ────────────────────────────────

#[test]
fn test_from_config_network_trusted_overrides_no_network() {
    ...
}

#[test]
fn test_from_config_network_bypass_overrides_no_network() {
    ...
}

#[test]
fn test_from_config_empty_network_defaults_to_trusted() {
    ...
}

#[test]
fn test_from_config_no_network_true_empty_network_is_blocked() {
    ...
}

#[test]
fn test_docker_network_run_args_blocked() {
    ...
}

#[test]
fn test_docker_network_run_args_trusted() {
    ...
}

#[test]
fn test_docker_network_run_args_bypass() {
    ...
}

#[test]
fn test_docker_proxy_exec_env_args_trusted() {
    ...
}

#[test]
fn test_docker_proxy_exec_env_args_blocked() {
    ...
}

#[test]
fn test_docker_proxy_exec_env_args_bypass() {
    ...
}

#[test]
fn test_docker_resolve_host_gateway_always_returns_host_gateway() {
    ...
}

#[test]
fn test_podman_network_run_args_trusted_contains_add_host() {
    ...
}

#[cfg(target_os = "macos")]
#[test]
fn test_apple_container_proxy_prefix_trusted() {
    ...
}

mod restricted_host_tests {

    #[test]
    fn test_restricted_host_sandbox_is_real() {
    ...
}

    #[tokio::test]
    async fn test_restricted_host_sandbox_ensure_ready_noop() {
    ...
}

    #[tokio::test]
    async fn test_restricted_host_sandbox_exec_simple_echo() {
    ...
}

    #[tokio::test]
    async fn test_restricted_host_sandbox_restricted_env() {
    ...
}

    #[tokio::test]
    async fn test_restricted_host_sandbox_build_image_returns_none() {
    ...
}

    #[tokio::test]
    async fn test_restricted_host_sandbox_cleanup_noop() {
    ...
}

    #[test]
    fn test_parse_memory_limit() {
    ...
}

    #[test]
    fn test_wasm_sandbox_available() {
    ...
}
}

#[cfg(feature = "wasm")]
mod wasm_sandbox_tests {

    #[test]
    fn test_wasm_sandbox_backend_name() {
    ...
}

    #[test]
    fn test_wasm_sandbox_is_real() {
    ...
}

    #[test]
    fn test_wasm_sandbox_fuel_limit_default() {
    ...
}

    #[test]
    fn test_wasm_sandbox_fuel_limit_custom() {
    ...
}

    #[test]
    fn test_wasm_sandbox_epoch_interval_default() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_ensure_ready_creates_dirs() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_cleanup_removes_dirs() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_echo() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_echo_no_newline() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_pwd() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_true_false() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_mkdir_ls() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_touch_cat() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_rm() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_unknown_command_127() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_path_escape_blocked() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_and_connector() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_or_connector() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_test_file() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_basename_dirname() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_builtin_which() {
    ...
}

    #[tokio::test]
    async fn test_wasm_sandbox_build_image_returns_none() {
    ...
}
}

#[cfg(target_os = "linux")]
mod linux_tests {

    #[test]
    fn test_cgroup_property_args() {
    ...
}
}
