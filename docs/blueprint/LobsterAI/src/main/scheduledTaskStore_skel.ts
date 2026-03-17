import { Database } from 'sql.js';
import { v4 as uuidv4 } from 'uuid';
import { CronExpressionParser } from 'cron-parser';

// Types for scheduled tasks (main process side)
export type TaskLastStatus = 'success' | 'error' | 'running' | null;

export interface TaskState {

export interface Schedule {

export type NotifyPlatform = 'dingtalk' | 'feishu' | 'qq' | 'telegram' | 'discord' | 'nim' | 'xiaomifeng' | 'wecom';

export interface ScheduledTask {

export interface ScheduledTaskRun {

export interface ScheduledTaskInput {

// Raw DB row types
interface TaskRow {

interface RunRow {

export class ScheduledTaskStore {


  // Helper method to get a single row from query result
const row: Record<string, unknown>;

  // Helper method to get all rows from query result
const row: Record<string, unknown>;

  // --- Startup ---

  private resetStuckRunningTasks(): void {
  }

  // --- Task CRUD ---

  listTasks(): ScheduledTask[] {
  }

  getTask(id: string): ScheduledTask | null {
  }

  createTask(input: ScheduledTaskInput): ScheduledTask {
  }

  updateTask(id: string, input: Partial<ScheduledTaskInput>): ScheduledTask | null {
  }

  deleteTask(id: string): boolean {
  }

  toggleTask(id: string, enabled: boolean): { task: ScheduledTask | null; warning: string | null } {
  }

  /**
   * Check if a task can meaningfully run after being enabled.
   * Returns a warning string if the task will never fire, null otherwise.
   */
  validateTaskActivation(task: ScheduledTask): string | null {
  }

  // --- Task State Updates (called by Scheduler) ---

  markTaskRunning(id: string, runningAtMs: number): void {
  }

    const nextRunAtMs = task?.enabled ? this.calculateNextRunTime(schedule, now) : null;



  // --- Run History ---

  createRun(taskId: string, trigger: 'scheduled' | 'manual'): ScheduledTaskRun {
  }


  getRun(id: string): ScheduledTaskRun | null {
  }

  listRuns(taskId: string, limit: number = 50, offset: number = 0): ScheduledTaskRun[] {
  }

  listAllRuns(limit: number = 50, offset: number = 0): (ScheduledTaskRun & { taskName: string })[] {
  }

  countRuns(taskId: string): number {
  }

  pruneRuns(taskId: string, keepCount: number = 100): void {
  }

  // --- Scheduler Queries ---

  getDueTasks(nowMs: number): ScheduledTask[] {
  }

  getNextDueTimeMs(): number | null {
  }

  // --- Helpers ---

  calculateNextRunTime(schedule: Schedule, lastRunAtMs: number | null): number | null {
  }

  private getNextCronTime(expression: string, afterMs: number): number | null {
  }

  private rowToTask(row: TaskRow): ScheduledTask {
  }

  private rowToRun(row: RunRow): ScheduledTaskRun {
  }
