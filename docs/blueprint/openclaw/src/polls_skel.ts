export type PollInput = {
  /**
   * Poll duration in seconds.
   * Channel-specific limits apply (e.g. Telegram open_period is 5-600s).
   */
  /**
   * Poll duration in hours.
   * Used by channels that model duration in hours (e.g. Discord).
   */
export type NormalizedPollInput = {
type NormalizePollOptions = {
export function resolvePollMaxSelections(;
export function normalizePollInput(;
export function normalizePollDurationHours(;
