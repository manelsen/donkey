/**
 * Logger module using electron-log
 * Intercepts console.* methods and writes to file + console simultaneously.
 *
 * Log file locations:
 *   macOS:   ~/Library/Logs/LobsterAI/main.log
 *   Windows: %USERPROFILE%\AppData\Roaming\LobsterAI\logs\main.log
 *   Linux:   ~/.config/LobsterAI/logs/main.log
 */

import log from 'electron-log/main';

/**
 * Initialize logging system.
 * Must be called early in main process, before any console output.
 */
export function initLogger(): void {
  // File transport config

  // Console transport config

  // Intercept console.* methods so all existing console.log/error/warn
  // across 25+ files are automatically captured without any code changes.
  // electron-log correctly serializes Error objects (with stack traces),
  // unlike JSON.stringify which outputs '{}' for Error instances.


  // Disable electron-log's own console transport to avoid double printing
  // (we already call originalLog above, so electron-log only needs to write to file)

  // Log startup marker

/**
 * Get the current log file path
 */
export function getLogFilePath(): string {

/**
 * Log instance for direct usage if needed
 */
export { log };
