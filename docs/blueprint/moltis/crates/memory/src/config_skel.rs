use std::{convert::Infallible, fmt, path::PathBuf, str::FromStr};

/// Citation mode for memory search results.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum CitationMode {
    ...
}

impl FromStr for CitationMode {
    type Err = Infallible;

    /// Parse from string (case-insensitive). Never fails - defaults to Auto.
    fn from_str(s: &str) -> Result<Self, Self::Err> {
}

/// Strategy for merging vector and keyword search results.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum MergeStrategy {
    ...
}

impl FromStr for MergeStrategy {
    type Err = Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
}

impl fmt::Display for MergeStrategy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
}

/// Configuration for the memory subsystem.
#[derive(Debug, Clone)]
pub struct MemoryConfig {
    ...
}

impl Default for MemoryConfig {
    fn default() -> Self {
}
