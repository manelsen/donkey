//! Next-run computation for all schedule kinds.

use {
    chrono::{DateTime, TimeZone, Utc},
    cron::Schedule,
};

use crate::{Error, Result, types::CronSchedule};

/// Compute the next run time (epoch millis) for a given schedule.
///
/// Returns `None` if the schedule has no future runs (e.g. a past one-shot).
pub fn compute_next_run(schedule: &CronSchedule, now_ms: u64) -> Result<Option<u64>> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_at_past() {
    ...
}

    #[test]
    fn test_every_no_anchor() {
    ...
}

    #[test]
    fn test_every_with_anchor_past() {
    ...
}

    #[test]
    fn test_every_with_anchor_future() {
    ...
}

    #[test]
    fn test_every_zero_interval() {
    ...
}

    #[test]
    fn test_cron_five_field() {
    ...
}

    #[test]
    fn test_cron_with_timezone() {
    ...
}

    #[test]
    fn test_cron_invalid_expr() {
    ...
}

    #[test]
    fn test_cron_invalid_tz() {
    ...
}
}
