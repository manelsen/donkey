import { app, BrowserWindow, ipcMain, session, nativeTheme, dialog, shell, nativeImage, systemPreferences, Menu } from 'electron';
import type { WebContents } from 'electron';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { SqliteStore } from './sqliteStore';
import { CoworkStore } from './coworkStore';
import { CoworkRunner } from './libs/coworkRunner';
import { SkillManager } from './skillManager';
import type { PermissionResult } from '@anthropic-ai/claude-agent-sdk';
import { getCurrentApiConfig, resolveCurrentApiConfig, setStoreGetter } from './libs/claudeSettings';
import { saveCoworkApiConfig } from './libs/coworkConfigStore';
import { generateSessionTitle, probeCoworkModelReadiness } from './libs/coworkUtil';
import { ensureSandboxReady, getSandboxStatus, onSandboxProgress } from './libs/coworkSandboxRuntime';
import { startCoworkOpenAICompatProxy, stopCoworkOpenAICompatProxy, setScheduledTaskDeps } from './libs/coworkOpenAICompatProxy';
import { IMGatewayManager, IMPlatform, IMGatewayConfig } from './im';
import { APP_NAME } from './appConstants';
import { getSkillServiceManager } from './skillServices';
import { createTray, destroyTray, updateTrayMenu } from './trayManager';
import { isAutoLaunched, getAutoLaunchEnabled, setAutoLaunchEnabled } from './autoLaunchManager';
import { McpStore } from './mcpStore';
import { ScheduledTaskStore } from './scheduledTaskStore';
import { Scheduler } from './libs/scheduler';
import { downloadUpdate, installUpdate, cancelActiveDownload } from './libs/appUpdateInstaller';
import { initLogger, getLogFilePath } from './logger';
import { getCoworkLogPath } from './libs/coworkLogger';
import { exportLogsZip } from './libs/logExport';
import { ensurePythonRuntimeReady } from './libs/pythonRuntime';
import {

// 设置应用程序名称

const MIME_EXTENSION_MAP: Record<string, string>;

const sanitizeExportFileName = (value: string): string => {

const sanitizeAttachmentFileName = (value?: string): string => {

const inferAttachmentExtension = (fileName: string, mimeType?: string): string => {
  if (fromName) {
  }
  if (typeof mimeType === 'string') {
  }

const resolveInlineAttachmentDir = (cwd?: string): string => {
  if (trimmed) {
  }

const ensurePngFileName = (value: string): string => {

const ensureZipFileName = (value: string): string => {

const padTwoDigits = (value: number): string => value.toString().padStart(2, '0');

const buildLogExportFileName = (): string => {

const truncateIpcString = (value: string, maxChars: number): string => {

const sanitizeIpcPayload = (value: unknown, depth = 0, seen?: WeakSet<object>): unknown => {
  if (typeof value === 'string') {
  }
  if (typeof value === 'bigint') {
  }
  if (typeof value === 'function') {
  }
  if (depth >= IPC_MAX_DEPTH) {
  }
    if (value.length > IPC_MAX_ITEMS) {
    }
  if (typeof value === 'object') {
  }

const sanitizeCoworkMessageForIpc = (message: any): any => {
  if (!message || typeof message !== 'object') {
  }

  // Preserve imageAttachments in metadata as-is (base64 data can be very large
  // and must not be truncated by the generic sanitizer).
  if (message.metadata && typeof message.metadata === 'object') {
  }


const sanitizePermissionRequestForIpc = (request: any): any => {
  if (!request || typeof request !== 'object') {
  }

type CaptureRect = { x: number; y: number; width: number; height: number };

const normalizeCaptureRect = (rect?: Partial<CaptureRect> | null): CaptureRect | null => {

const resolveTaskWorkingDirectory = (workspaceRoot: string): string => {

const resolveExistingTaskWorkingDirectory = (workspaceRoot: string): string => {
  if (!trimmed) {
  }

const getDefaultExportImageName = (defaultFileName?: string): string => {


  if (saveResult.canceled || !saveResult.filePath) {
  }


const configureUserDataPath = (): void => {

  if (currentUserDataPath !== preferredUserDataPath) {
  }


const DEV_SERVER_URL = process.env.ELECTRON_START_URL || 'http://localhost:5175';
  // Align light title bar with app light surface-muted tone to reduce visual contrast.

const safeDecodeURIComponent = (value: string): string => {

const normalizeWindowsShellPath = (inputPath: string): string => {




  if (unixDriveMatch) {
  }



// ==================== macOS Permissions ====================

/**
 * Check calendar permission on macOS by attempting to access Calendar app
 * Returns: 'authorized' | 'denied' | 'restricted' | 'not-determined'
 * On Windows, checks if Outlook is available
 * On Linux, returns 'not-supported'
 */
const checkCalendarPermission = async (): Promise<string> => {
  if (process.platform === 'darwin') {
  }

  if (process.platform === 'win32') {
  }


/**
 * Request calendar permission on macOS
 * On Windows, attempts to initialize Outlook COM object
 */
const requestCalendarPermission = async (): Promise<boolean> => {
  if (process.platform === 'darwin') {
  }

  if (process.platform === 'win32') {
  }




// 配置应用
if (isLinux) {
}
if (disableGpu) {
}
if (enableVerboseLogging) {
}

// 配置网络服务
  // 配置网络服务重启策略

// 添加错误处理
  if (shouldReload) {
  }


// 处理未捕获的异常



let store: SqliteStore | null;
let coworkStore: CoworkStore | null;
let coworkRunner: CoworkRunner | null;
let skillManager: SkillManager | null;
let mcpStore: McpStore | null;
let imGatewayManager: IMGatewayManager | null;
let scheduledTaskStore: ScheduledTaskStore | null;
let scheduler: Scheduler | null;
let storeInitPromise: Promise<SqliteStore> | null;

const initStore = async (): Promise<SqliteStore> => {
  if (!storeInitPromise) {
  }

const getStore = (): SqliteStore => {
  if (!store) {
  }

  if (!coworkStore) {
  }

  if (!coworkRunner) {
  }

  if (!skillManager) {
  }

  if (!mcpStore) {
  }

  if (!imGatewayManager) {
  }

  if (!scheduledTaskStore) {
  }

  if (!scheduler) {
  }

// 获取正确的预加载脚本路径

// 获取应用图标路径（Windows 使用 .ico，其他平台使用 .png）
const getAppIconPath = (): string | undefined => {

// 保存对主窗口的引用
let mainWindow: BrowserWindow | null;

onSandboxProgress((progress) => {
});

// 存储活跃的流式请求控制器
type AppConfigSettings = {

const getUseSystemProxyFromConfig = (config?: { useSystemProxy?: boolean }): boolean => {

const resolveThemeFromConfig = (config?: AppConfigSettings): 'light' | 'dark' => {
  if (config?.theme === 'dark') {
  }
  if (config?.theme === 'light') {
  }



  if (!isMac && !isWindows) {
  }
  // Also update the window background color to match the theme

const applyProxyPreference = async (useSystemProxy: boolean): Promise<void> => {


  if (!useSystemProxy) {
  }


  if (proxyUrl) {
  }


const showSystemMenu = (position?: { x?: number; y?: number }) => {



const scheduleReload = (reason: string, webContents?: WebContents) => {
  if (now - lastReloadAt < MIN_RELOAD_INTERVAL_MS) {
  }


// 确保应用程序只有一个实例

if (!gotTheLock) {
} 
