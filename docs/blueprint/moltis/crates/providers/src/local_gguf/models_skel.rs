//! Model registry for local LLM models (GGUF and MLX).
//!
//! Defines available models with HuggingFace URLs, memory requirements,
//! and chat template hints.

use std::path::{Component, Path, PathBuf};

use {
    anyhow::{Context, bail},
    futures::StreamExt,
    tracing::{debug, info},
};

use super::{chat_templates::ChatTemplateHint, system_info::MemoryTier};

/// Progress info for model downloads.
#[derive(Debug, Clone)]
pub struct DownloadProgress {
    ...
}

/// Backend type for local models.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelBackend {
    ...
}

impl std::fmt::Display for ModelBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Definition of a local LLM model in the registry.
#[derive(Debug, Clone)]
pub struct GgufModelDef {
    ...
}

impl GgufModelDef {
    /// HuggingFace download URL for this model.
    #[must_use]
    pub fn hf_url(&self) -> String {
}

/// Model registry — all known local LLM models organized by backend and memory tier.
///
/// Models are listed in recommended order within each tier.
pub static MODEL_REGISTRY: &[GgufModelDef] = &[
    // ════════════════════════════════════════════════════════════════════════
    // GGUF Models (llama.cpp)
    // ════════════════════════════════════════════════════════════════════════
    // ── 4GB tier (Tiny) ────────────────────────────────────────────────────
    GgufModelDef {
        id: "qwen2.5-coder-1.5b-q4_k_m",
        display_name: "Qwen 2.5 Coder 1.5B (Q4_K_M)",
        hf_repo: "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF",
        hf_filename: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
        min_ram_gb: 4,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "llama-3.2-1b-q4_k_m",
        display_name: "Llama 3.2 1B (Q4_K_M)",
        hf_repo: "bartowski/Llama-3.2-1B-Instruct-GGUF",
        hf_filename: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        min_ram_gb: 4,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Gguf,
    },
    // ── 8GB tier (Small) ───────────────────────────────────────────────────
    GgufModelDef {
        id: "qwen2.5-coder-7b-q4_k_m",
        display_name: "Qwen 2.5 Coder 7B (Q4_K_M)",
        hf_repo: "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF",
        hf_filename: "qwen2.5-coder-7b-instruct-q4_k_m.gguf",
        min_ram_gb: 8,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "llama-3.2-3b-q4_k_m",
        display_name: "Llama 3.2 3B (Q4_K_M)",
        hf_repo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
        hf_filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        min_ram_gb: 8,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "deepseek-coder-6.7b-q4_k_m",
        display_name: "DeepSeek Coder 6.7B (Q4_K_M)",
        hf_repo: "TheBloke/deepseek-coder-6.7B-instruct-GGUF",
        hf_filename: "deepseek-coder-6.7b-instruct.Q4_K_M.gguf",
        min_ram_gb: 8,
        context_window: 16_384,
        chat_template: ChatTemplateHint::DeepSeek,
        backend: ModelBackend::Gguf,
    },
    // ── 16GB tier (Medium) ─────────────────────────────────────────────────
    GgufModelDef {
        id: "qwen2.5-coder-14b-q4_k_m",
        display_name: "Qwen 2.5 Coder 14B (Q4_K_M)",
        hf_repo: "Qwen/Qwen2.5-Coder-14B-Instruct-GGUF",
        hf_filename: "qwen2.5-coder-14b-instruct-q4_k_m.gguf",
        min_ram_gb: 16,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "codestral-22b-q4_k_m",
        display_name: "Codestral 22B (Q4_K_M)",
        hf_repo: "bartowski/Codestral-22B-v0.1-GGUF",
        hf_filename: "Codestral-22B-v0.1-Q4_K_M.gguf",
        min_ram_gb: 16,
        context_window: 32_768,
        chat_template: ChatTemplateHint::Mistral,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "mistral-7b-q5_k_m",
        display_name: "Mistral 7B Instruct (Q5_K_M)",
        hf_repo: "TheBloke/Mistral-7B-Instruct-v0.2-GGUF",
        hf_filename: "mistral-7b-instruct-v0.2.Q5_K_M.gguf",
        min_ram_gb: 12,
        context_window: 32_768,
        chat_template: ChatTemplateHint::Mistral,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "llama-3.1-8b-q4_k_m",
        display_name: "Llama 3.1 8B (Q4_K_M)",
        hf_repo: "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF",
        hf_filename: "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
        min_ram_gb: 12,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Gguf,
    },
    // ── 32GB tier (Large) ──────────────────────────────────────────────────
    GgufModelDef {
        id: "qwen2.5-coder-32b-q4_k_m",
        display_name: "Qwen 2.5 Coder 32B (Q4_K_M)",
        hf_repo: "Qwen/Qwen2.5-Coder-32B-Instruct-GGUF",
        hf_filename: "qwen2.5-coder-32b-instruct-q4_k_m.gguf",
        min_ram_gb: 32,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "deepseek-coder-33b-q4_k_m",
        display_name: "DeepSeek Coder 33B (Q4_K_M)",
        hf_repo: "TheBloke/deepseek-coder-33B-instruct-GGUF",
        hf_filename: "deepseek-coder-33b-instruct.Q4_K_M.gguf",
        min_ram_gb: 32,
        context_window: 16_384,
        chat_template: ChatTemplateHint::DeepSeek,
        backend: ModelBackend::Gguf,
    },
    GgufModelDef {
        id: "llama-3.1-70b-q2_k",
        display_name: "Llama 3.1 70B (Q2_K)",
        hf_repo: "bartowski/Meta-Llama-3.1-70B-Instruct-GGUF",
        hf_filename: "Meta-Llama-3.1-70B-Instruct-Q2_K.gguf",
        min_ram_gb: 48,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Gguf,
    },
    // ════════════════════════════════════════════════════════════════════════
    // MLX Models (Apple Silicon native)
    // ════════════════════════════════════════════════════════════════════════
    // ── 4GB tier (Tiny) ────────────────────────────────────────────────────
    GgufModelDef {
        id: "mlx-qwen2.5-coder-1.5b-4bit",
        display_name: "Qwen 2.5 Coder 1.5B (4-bit MLX)",
        hf_repo: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 4,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Mlx,
    },
    GgufModelDef {
        id: "mlx-llama-3.2-1b-4bit",
        display_name: "Llama 3.2 1B (4-bit MLX)",
        hf_repo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 4,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Mlx,
    },
    // ── 8GB tier (Small) ───────────────────────────────────────────────────
    GgufModelDef {
        id: "mlx-qwen2.5-coder-7b-4bit",
        display_name: "Qwen 2.5 Coder 7B (4-bit MLX)",
        hf_repo: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 8,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Mlx,
    },
    GgufModelDef {
        id: "mlx-llama-3.2-3b-4bit",
        display_name: "Llama 3.2 3B (4-bit MLX)",
        hf_repo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 8,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Mlx,
    },
    // ── 16GB tier (Medium) ─────────────────────────────────────────────────
    GgufModelDef {
        id: "mlx-qwen2.5-coder-14b-4bit",
        display_name: "Qwen 2.5 Coder 14B (4-bit MLX)",
        hf_repo: "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 16,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Mlx,
    },
    GgufModelDef {
        id: "mlx-mistral-7b-4bit",
        display_name: "Mistral 7B Instruct (4-bit MLX)",
        hf_repo: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
        hf_filename: "",
        min_ram_gb: 8,
        context_window: 32_768,
        chat_template: ChatTemplateHint::Mistral,
        backend: ModelBackend::Mlx,
    },
    GgufModelDef {
        id: "mlx-llama-3.1-8b-4bit",
        display_name: "Llama 3.1 8B (4-bit MLX)",
        hf_repo: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 8,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Mlx,
    },
    // ── 32GB tier (Large) ──────────────────────────────────────────────────
    GgufModelDef {
        id: "mlx-qwen2.5-coder-32b-4bit",
        display_name: "Qwen 2.5 Coder 32B (4-bit MLX)",
        hf_repo: "mlx-community/Qwen2.5-Coder-32B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 32,
        context_window: 32_768,
        chat_template: ChatTemplateHint::ChatML,
        backend: ModelBackend::Mlx,
    },
    GgufModelDef {
        id: "mlx-llama-3.1-70b-4bit",
        display_name: "Llama 3.1 70B (4-bit MLX)",
        hf_repo: "mlx-community/Meta-Llama-3.1-70B-Instruct-4bit",
        hf_filename: "",
        min_ram_gb: 48,
        context_window: 128_000,
        chat_template: ChatTemplateHint::Llama3,
        backend: ModelBackend::Mlx,
    },
];

/// Find a model definition by ID.
#[must_use]
pub fn find_model(id: &str) -> Option<&'static GgufModelDef> {
    ...
}

/// Get models suitable for a given memory tier (all backends).
#[must_use]
pub fn models_for_tier(tier: MemoryTier) -> Vec<&'static GgufModelDef> {
    ...
}

/// Get models suitable for a given memory tier and backend.
#[must_use]
pub fn models_for_tier_and_backend(
    tier: MemoryTier,
    backend: ModelBackend,
) -> Vec<&'static GgufModelDef> {
    ...
}

/// Suggest the best model for a memory tier (all backends).
#[must_use]
pub fn suggest_model(tier: MemoryTier) -> Option<&'static GgufModelDef> {
    ...
}

/// Suggest the best model for a memory tier and backend.
#[must_use]
pub fn suggest_model_for_backend(
    tier: MemoryTier,
    backend: ModelBackend,
) -> Option<&'static GgufModelDef> {
    ...
}

/// Default cache directory for downloaded models.
///
/// Returns `~/.moltis/models` (same base as config/data directories).
#[must_use]
pub fn default_models_dir() -> PathBuf {
    ...
}

/// Check if a GGUF model file is cached locally.
#[must_use]
pub fn is_gguf_model_cached(model: &GgufModelDef, cache_dir: &Path) -> bool {
    ...
}

fn validate_hf_filename_path(hf_filename: &str) -> anyhow::Result<&Path> {
    ...
}

fn validate_hf_repo_path(hf_repo: &str) -> anyhow::Result<Vec<&str>> {
    ...
}

fn custom_model_download_url(hf_repo: &str, hf_filename: &str) -> anyhow::Result<String> {
    ...
}

/// Compute the cache path for a custom GGUF model from Hugging Face.
pub fn custom_model_path(
    hf_repo: &str,
    hf_filename: &str,
    cache_dir: &Path,
) -> anyhow::Result<PathBuf> {
    ...
}

/// Check if a custom GGUF model file is cached locally.
#[must_use]
pub fn is_custom_model_cached(hf_repo: &str, hf_filename: &str, cache_dir: &Path) -> bool {
    ...
}

/// Check if an MLX model directory is cached locally.
#[must_use]
pub fn is_mlx_model_cached(model: &GgufModelDef, cache_dir: &Path) -> bool {
    ...
}

/// Check if a model is cached (based on its backend type).
#[must_use]
pub fn is_model_cached(model: &GgufModelDef, cache_dir: &Path) -> bool {
    ...
}

/// Ensure a model is downloaded, returning the path to the GGUF file.
///
/// Downloads from HuggingFace if not present in the cache.
pub async fn ensure_model(model: &GgufModelDef, cache_dir: &Path) -> anyhow::Result<PathBuf> {
    ...
}

/// Ensure a model is downloaded with progress reporting.
///
/// The progress callback is called periodically during download with the current progress.
pub async fn ensure_model_with_progress<F>(
    model: &GgufModelDef,
    cache_dir: &Path,
    mut on_progress: F,
) -> anyhow::Result<PathBuf>
where
    F: FnMut(DownloadProgress),
{
    let model_path = cache_dir.join(model.hf_filename);
    if model_path.exists() {
        info!(path = %model_path.display(), model = model.id, "model found in cache");
        return Ok(model_path);
    }

    let url = model.hf_url();
    download_gguf_file_with_progress(&url, &model_path, model.id, &mut on_progress).await
}

/// Ensure a custom GGUF model is downloaded, returning the path to the file.
pub async fn ensure_custom_model(
    hf_repo: &str,
    hf_filename: &str,
    cache_dir: &Path,
) -> anyhow::Result<PathBuf> {
    ...
}

/// Ensure a custom GGUF model is downloaded with progress reporting.
pub async fn ensure_custom_model_with_progress<F>(
    hf_repo: &str,
    hf_filename: &str,
    cache_dir: &Path,
    mut on_progress: F,
) -> anyhow::Result<PathBuf>
where
    F: FnMut(DownloadProgress),
{
    let model_path = custom_model_path(hf_repo, hf_filename, cache_dir)?;
    if model_path.exists() {
        info!(
            path = %model_path.display(),
            hf_repo,
            hf_filename,
            "custom GGUF model found in cache"
        );
        return Ok(model_path);
    }

    let url = custom_model_download_url(hf_repo, hf_filename)?;
    let label = format!("{hf_repo}/{hf_filename}");
    download_gguf_file_with_progress(&url, &model_path, &label, &mut on_progress).await
}

// ── MLX Model Download ───────────────────────────────────────────────────────

/// Ensure an MLX model is downloaded, returning the path to the model directory.
///
/// MLX models are directories containing multiple files (config.json, model.safetensors, etc.).
pub async fn ensure_mlx_model(model: &GgufModelDef, cache_dir: &Path) -> anyhow::Result<PathBuf> {
    ...
}

/// Ensure an MLX model is downloaded with progress reporting.
pub async fn ensure_mlx_model_with_progress<F>(
    model: &GgufModelDef,
    cache_dir: &Path,
    mut on_progress: F,
) -> anyhow::Result<PathBuf>
where
    F: FnMut(DownloadProgress),
{
    if model.backend != ModelBackend::Mlx {
        anyhow::bail!(
            "model '{}' is not an MLX model (backend: {:?})",
            model.id,
            model.backend
        );
    }

    // Create model directory using sanitized repo name
    let model_dir_name = model.hf_repo.replace('/', "__");
    let model_dir = cache_dir.join("mlx").join(&model_dir_name);

    // Check if model is already fully downloaded
    let config_path = model_dir.join("config.json");
    let model_path = model_dir.join("model.safetensors");
    let index_path = model_dir.join("model.safetensors.index.json");

    // A model is considered cached if it has config.json and either model.safetensors or an index file
    if config_path.exists() && (model_path.exists() || index_path.exists()) {
        info!(
            path = %model_dir.display(),
            model = model.id,
            "MLX model found in cache"
        );
        return Ok(model_dir);
    }

    // Create the model directory
    tokio::fs::create_dir_all(&model_dir)
        .await
        .context("creating MLX model cache dir")?;

    info!(
        hf_repo = model.hf_repo,
        model = model.id,
        "downloading MLX model from HuggingFace"
    );

    // First, get the list of files in the repository
    let files = list_hf_repo_files(model.hf_repo).await?;
    debug!(file_count = files.len(), "found files in HuggingFace repo");

    // Filter to only the files we need
    let files_to_download: Vec<String> = files
        .into_iter()
        .filter(|f| {
            // Include essential config/tokenizer files
            matches!(
                f.as_str(),
                "config.json"
                    | "model.safetensors"
                    | "model.safetensors.index.json"
                    | "tokenizer.json"
                    | "tokenizer_config.json"
                    | "special_tokens_map.json"
                    | "generation_config.json"
            )
            // Include sharded weight files
            || (f.starts_with("model-") && f.ends_with(".safetensors"))
            || (f.starts_with("weights.") && f.ends_with(".safetensors"))
            // Include any .safetensors file
            || f.ends_with(".safetensors")
        })
        .collect();

    if files_to_download.is_empty() {
        anyhow::bail!(
            "no model files found in HuggingFace repo '{}'",
            model.hf_repo
        );
    }

    info!(
        file_count = files_to_download.len(),
        "downloading files for MLX model"
    );
    debug!(files = ?files_to_download, "files to download");

    // Download each file
    let mut total_downloaded: u64 = 0;
    for filename in &files_to_download {
        let file_path = model_dir.join(filename);

        // Skip if already downloaded
        if file_path.exists() {
            debug!(file = filename, "file already cached, skipping");
            continue;
        }

        // Create parent directories if needed (for sharded files)
        if let Some(parent) = file_path.parent() {
            tokio::fs::create_dir_all(parent).await.ok();
        }

        let url = format!(
            "https://huggingface.co/{}/resolve/main/{}",
            model.hf_repo, filename
        );
        debug!(url = %url, file = filename, "downloading file");

        let downloaded = download_mlx_file(&url, &file_path, |progress| {
            on_progress(DownloadProgress {
                downloaded: total_downloaded + progress.downloaded,
                total: None,
            });
        })
        .await
        .with_context(|| format!("downloading {}", filename))?;

        total_downloaded += downloaded;
        debug!(
            file = filename,
            size_mb = downloaded / (1024 * 1024),
            "file downloaded"
        );
    }

    // Final progress report
    on_progress(DownloadProgress {
        downloaded: total_downloaded,
        total: Some(total_downloaded),
    });

    info!(
        path = %model_dir.display(),
        total_size_mb = total_downloaded / (1024 * 1024),
        model = model.id,
        "MLX model downloaded successfully"
    );

    Ok(model_dir)
}

/// List files in a HuggingFace repository.
async fn list_hf_repo_files(repo: &str) -> anyhow::Result<Vec<String>> {
    ...
}

/// Download a single file with progress reporting.
async fn download_mlx_file<F>(url: &str, path: &PathBuf, mut on_progress: F) -> anyhow::Result<u64>
where
    F: FnMut(DownloadProgress),
{
    let client = reqwest::Client::new();
    let response = client
        .get(url)
        .header("User-Agent", "moltis/1.0")
        .send()
        .await
        .context("starting download")?
        .error_for_status()
        .context("download failed")?;

    let total = response.content_length();
    let mut downloaded: u64 = 0;

    on_progress(DownloadProgress { downloaded, total });

    let tmp_path = path.with_extension("tmp");
    let mut file = tokio::fs::File::create(&tmp_path)
        .await
        .context("creating temp file")?;

    let mut stream = response.bytes_stream();
    let mut last_report = std::time::Instant::now();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("reading chunk")?;
        downloaded += chunk.len() as u64;

        tokio::io::AsyncWriteExt::write_all(&mut file, &chunk)
            .await
            .context("writing chunk")?;

        if last_report.elapsed() >= std::time::Duration::from_millis(100) {
            on_progress(DownloadProgress { downloaded, total });
            last_report = std::time::Instant::now();
        }
    }

    on_progress(DownloadProgress { downloaded, total });

    tokio::io::AsyncWriteExt::flush(&mut file)
        .await
        .context("flushing file")?;
    drop(file);

    tokio::fs::rename(&tmp_path, path)
        .await
        .context("renaming file")?;

    Ok(downloaded)
}

async fn download_gguf_file_with_progress<F>(
    url: &str,
    model_path: &Path,
    model_label: &str,
    mut on_progress: F,
) -> anyhow::Result<PathBuf>
where
    F: FnMut(DownloadProgress),
{
    let cache_dir = model_path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("invalid model cache path"))?;
    debug!(cache_dir = %cache_dir.display(), "ensuring cache directory exists");
    tokio::fs::create_dir_all(cache_dir)
        .await
        .context("creating models cache dir")?;

    info!(url = %url, model = model_label, "downloading model from HuggingFace");

    let download_start = std::time::Instant::now();

    let response = reqwest::get(url)
        .await
        .context("downloading GGUF model")?
        .error_for_status()
        .context("GGUF model download failed")?;

    let total = response.content_length();
    let mut downloaded: u64 = 0;

    if let Some(size) = total {
        debug!(total_size_mb = size / (1024 * 1024), "download size known");
    }

    on_progress(DownloadProgress { downloaded, total });

    let tmp_path = model_path.with_extension("tmp");
    debug!(tmp_path = %tmp_path.display(), "creating temp file for download");
    let mut file = tokio::fs::File::create(&tmp_path)
        .await
        .context("creating temp file")?;

    let mut stream = response.bytes_stream();
    let mut last_report = std::time::Instant::now();
    let mut last_log = std::time::Instant::now();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("reading chunk")?;
        downloaded += chunk.len() as u64;

        tokio::io::AsyncWriteExt::write_all(&mut file, &chunk)
            .await
            .context("writing chunk")?;

        if last_report.elapsed() >= std::time::Duration::from_millis(100) {
            on_progress(DownloadProgress { downloaded, total });
            last_report = std::time::Instant::now();
        }

        if last_log.elapsed() >= std::time::Duration::from_secs(5) {
            let percent = total
                .map(|t| (downloaded as f64 / t as f64 * 100.0) as u32)
                .unwrap_or(0);
            debug!(
                downloaded_mb = downloaded / (1024 * 1024),
                percent, "download progress"
            );
            last_log = std::time::Instant::now();
        }
    }

    on_progress(DownloadProgress { downloaded, total });

    tokio::io::AsyncWriteExt::flush(&mut file)
        .await
        .context("flushing file")?;
    drop(file);

    debug!(
        from = %tmp_path.display(),
        to = %model_path.display(),
        "renaming temp file to final location"
    );
    tokio::fs::rename(&tmp_path, model_path)
        .await
        .context("renaming model file")?;

    let download_duration = download_start.elapsed();
    let download_speed_mbps = if download_duration.as_secs_f64() > 0.0 {
        (downloaded as f64 / (1024.0 * 1024.0)) / download_duration.as_secs_f64()
    } else {
        0.0
    };

    info!(
        path = %model_path.display(),
        size_mb = downloaded / (1024 * 1024),
        duration_secs = download_duration.as_secs_f64(),
        speed_mbps = format!("{:.1}", download_speed_mbps),
        model = model_label,
        "model downloaded successfully"
    );

    Ok(model_path.to_path_buf())
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_find_model() {
    ...
}

    #[test]
    fn test_hf_url() {
    ...
}

    #[test]
    fn test_models_for_tier() {
    ...
}

    #[test]
    fn test_suggest_model() {
    ...
}

    #[test]
    fn test_default_models_dir() {
    ...
}

    #[test]
    fn test_model_registry_unique_ids() {
    ...
}

    #[test]
    fn test_model_registry_valid_urls() {
    ...
}

    #[test]
    fn test_model_registry_context_windows() {
    ...
}

    #[test]
    fn test_models_for_tier_and_backend() {
    ...
}

    #[test]
    fn test_suggest_model_for_backend() {
    ...
}

    #[test]
    fn test_model_backend_display() {
    ...
}

    #[test]
    fn test_is_gguf_model_cached_returns_false_when_not_exists() {
    ...
}

    #[test]
    fn test_is_gguf_model_cached_returns_true_when_exists() {
    ...
}

    #[test]
    fn test_custom_model_path_scopes_repo_and_filename() {
    ...
}

    #[test]
    fn test_custom_model_path_rejects_parent_segments() {
    ...
}

    #[test]
    fn test_custom_model_path_rejects_invalid_repo_segments() {
    ...
}

    #[test]
    fn test_custom_model_path_rejects_backslash_repo_separators() {
    ...
}

    #[test]
    fn test_custom_model_path_rejects_windows_drive_prefix_repo_components() {
    ...
}

    #[test]
    fn test_custom_model_path_distinguishes_repo_collisions() {
    ...
}

    #[test]
    fn test_is_custom_model_cached_returns_true_when_exists() {
    ...
}

    #[test]
    fn test_custom_model_download_url_encodes_repo_and_filename_segments() {
    ...
}

    #[test]
    fn test_custom_model_download_url_rejects_backslash_repo_separators() {
    ...
}

    #[test]
    fn test_custom_model_download_url_rejects_windows_drive_prefix_repo_components() {
    ...
}

    #[test]
    fn test_is_gguf_model_cached_returns_false_for_mlx_model() {
    ...
}

    #[test]
    fn test_is_mlx_model_cached_returns_false_when_not_exists() {
    ...
}

    #[test]
    fn test_is_mlx_model_cached_returns_true_when_exists() {
    ...
}

    #[test]
    fn test_is_mlx_model_cached_with_sharded_model() {
    ...
}

    #[test]
    fn test_is_mlx_model_cached_returns_false_for_gguf_model() {
    ...
}

    #[test]
    fn test_is_mlx_model_cached_returns_false_when_incomplete() {
    ...
}

    #[test]
    fn test_is_model_cached_routes_to_correct_function() {
    ...
}

    #[test]
    fn test_find_mlx_model_in_legacy_registry() {
    ...
}

    #[tokio::test]
    async fn test_download_gguf_file_with_progress_downloads_to_target_path() {
    ...
}
}
