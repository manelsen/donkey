//! Metrics recorder initialization and configuration.

use {crate::Result, tracing::info};

/// Handle to the metrics system, providing access to exported metrics.
#[derive(Clone)]
pub struct MetricsHandle {
    ...
}

impl MetricsHandle {
    /// Render metrics in Prometheus text format.
    ///
    /// Returns the metrics as a string suitable for the `/metrics` endpoint.
    #[must_use]
    pub fn render(&self) -> String {
        #[cfg(feature = "prometheus")]
        #[cfg(not(feature = "prometheus"))]
}

/// Configuration for the metrics system.
#[derive(Debug, Clone, Default)]
pub struct MetricsRecorderConfig {
    ...
}

/// Initialize the metrics system.
///
/// This should be called once at application startup. When the `prometheus` feature
/// is enabled, this sets up the Prometheus exporter. Otherwise, it uses a no-op
/// recorder that discards all metrics.
///
/// # Returns
///
/// A `MetricsHandle` that can be used to render metrics for the `/metrics` endpoint.
///
/// # Errors
///
/// Returns an error if the metrics system fails to initialize.
pub fn init_metrics(config: MetricsRecorderConfig) -> Result<MetricsHandle> {
    ...
}

#[cfg(feature = "prometheus")]
fn init_prometheus(
    config: MetricsRecorderConfig,
) -> Result<metrics_exporter_prometheus::PrometheusHandle> {
    ...
}

#[cfg(feature = "prometheus")]
fn init_prometheus_disabled() -> Result<metrics_exporter_prometheus::PrometheusHandle> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
}
