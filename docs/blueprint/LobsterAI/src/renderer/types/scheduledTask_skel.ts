// 调度类型
export interface ScheduleAt {

export interface ScheduleInterval {

export interface ScheduleCron {

export type Schedule = ScheduleAt | ScheduleInterval | ScheduleCron;

// 任务状态
export type TaskLastStatus = 'success' | 'error' | 'running' | null;

export interface TaskState {

// IM 通知平台类型
export type NotifyPlatform = 'dingtalk' | 'feishu' | 'qq' | 'telegram' | 'discord' | 'nim' | 'xiaomifeng' | 'wecom';

// 定时任务
export interface ScheduledTask {

// 运行记录
export interface ScheduledTaskRun {

// 带任务名称的运行记录（用于全局历史列表）
export interface ScheduledTaskRunWithName extends ScheduledTaskRun {

// 表单输入
export interface ScheduledTaskInput {

// IPC 事件
export interface ScheduledTaskStatusEvent {

export interface ScheduledTaskRunEvent {

// UI 视图模式
export type ScheduledTaskViewMode = 'list' | 'create' | 'edit' | 'detail';
