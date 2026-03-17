import { diagnosticLogger as diag, logLaneDequeue, logLaneEnqueue } from "../logging/diagnostic.js";
import { resolveGlobalSingleton } from "../shared/global-singleton.js";
import { CommandLane } from "./lanes.js";
/**
 * Dedicated error type thrown when a queued command is rejected because
 * its lane was cleared.  Callers that fire-and-forget enqueued tasks can
 * catch (or ignore) this specific type to avoid unhandled-rejection noise.
 */
export class CommandLaneClearedError extends Error {
/**
 * Dedicated error type thrown when a new command is rejected because the
 * gateway is currently draining for restart.
 */
export class GatewayDrainingError extends Error {
type QueueEntry = {
type LaneState = {
/**
 * Keep queue runtime state on globalThis so every bundled entry/chunk shares
 * the same lanes, counters, and draining flag in production builds.
 */
function getLaneState(lane: string): LaneState;
function completeTask(state: LaneState, taskId: number, taskGeneration: number): boolean;
function drainLane(lane: string);
/**
 * Mark gateway as draining for restart so new enqueues fail fast with
 * `GatewayDrainingError` instead of being silently killed on shutdown.
 */
export function markGatewayDraining(): void;
export function setCommandLaneConcurrency(lane: string, maxConcurrent: number);
export function enqueueCommandInLane<T>(;
export function enqueueCommand<T>(;
export function getQueueSize(lane: string = CommandLane.Main);
export function getTotalQueueSize();
export function clearCommandLane(lane: string = CommandLane.Main);
/**
 * Reset all lane runtime state to idle. Used after SIGUSR1 in-process
 * restarts where interrupted tasks' finally blocks may not run, leaving
 * stale active task IDs that permanently block new work from draining.
 *
 * Bumps lane generation and clears execution counters so stale completions
 * from old in-flight tasks are ignored. Queued entries are intentionally
 * preserved — they represent pending user work that should still execute
 * after restart.
 *
 * After resetting, drains any lanes that still have queued entries so
 * preserved work is pumped immediately rather than waiting for a future
 * `enqueueCommandInLane()` call (which may never come).
 */
export function resetAllLanes(): void;
/**
 * Returns the total number of actively executing tasks across all lanes
 * (excludes queued-but-not-started entries).
 */
export function getActiveTaskCount(): number;
/**
 * Wait for all currently active tasks across all lanes to finish.
 * Polls at a short interval; resolves when no tasks are active or
 * when `timeoutMs` elapses (whichever comes first).
 *
 * New tasks enqueued after this call are ignored — only tasks that are
 * already executing are waited on.
 */
export function waitForActiveTasks(timeoutMs: number): Promise<;
