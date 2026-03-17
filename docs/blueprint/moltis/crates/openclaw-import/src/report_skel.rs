//! Import report types — aggregated results of an import operation.

use serde::{Deserialize, Serialize};

use crate::{agents::ImportedAgents, channels::ImportedChannels, identity::ImportedIdentity};

/// A single import category.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportCategory {
    ...
}

impl std::fmt::Display for ImportCategory {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Outcome status of a single category import.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportStatus {
    ...
}

/// Report for a single import category.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CategoryReport {
    ...
}

impl CategoryReport {
    /// Create a successful report with no warnings.
    pub fn success(category: ImportCategory, items_imported: usize) -> Self {

    /// Create a skipped report (nothing to import for this category).
    pub fn skipped(category: ImportCategory) -> Self {
    ...
}

    /// Create a failed report.
    pub fn failed(category: ImportCategory, error: String) -> Self {
    ...
}
}

/// A deferred/unsupported feature noted during import.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TodoItem {
    ...
}

/// Full import report with all categories and deferred items.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportReport {
    ...
}

impl ImportReport {
    /// Create an empty report.
    pub fn new() -> Self {

    /// Add a category report.
    pub fn add_category(&mut self, report: CategoryReport) {
    ...
}

    /// Add a TODO item for an unsupported feature.
    pub fn add_todo(&mut self, feature: impl Into<String>, description: impl Into<String>) {
    ...
}

    /// Total items successfully imported across all categories.
    pub fn total_imported(&self) -> usize {
    ...
}

    /// Whether any category failed.
    pub fn has_failures(&self) -> bool {
    ...
}
}

impl Default for ImportReport {
    fn default() -> Self {
}
