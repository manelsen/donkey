import { app } from 'electron';
import { execSync, spawnSync } from 'child_process';
import { existsSync, mkdirSync, writeFileSync, chmodSync, statSync, readdirSync } from 'fs';
import { delimiter, dirname, join } from 'path';
import { buildEnvForConfig, getCurrentApiConfig, resolveCurrentApiConfig } from './claudeSettings';
import type { OpenAICompatProxyTarget } from './coworkOpenAICompatProxy';
import { getInternalApiBaseURL } from './coworkOpenAICompatProxy';
import { coworkLog } from './coworkLogger';
import { appendPythonRuntimeToEnv } from './pythonRuntime';
import { isSystemProxyEnabled, resolveSystemProxyUrl } from './systemProxy';

function appendEnvPath(current: string | undefined, additions: string[]): string | undefined {
}

function hasCommandInEnv(command: string, env: Record<string, string | undefined>): boolean {
}

let cachedElectronNodeRuntimePath: string | null;

function resolveElectronNodeRuntimePath(): string {
}

export function getElectronNodeRuntimePath(): string {
  if (!cachedElectronNodeRuntimePath) {
  }

/**
 * Cached user shell PATH. Resolved once and reused across calls.
 */

/**
 * Resolve the user's login shell PATH on macOS/Linux.
 * Packaged Electron apps on macOS don't inherit the user's shell profile,
 * so node/npm and other tools won't be in PATH unless we resolve it.
 */
function resolveUserShellPath(): string | null {
}

/**
 * Cached Windows registry PATH. Resolved once and reused.
 */

function readWindowsRegistryPathValue(registryKey: string): string {
}

/**
 * Resolve the latest PATH from the Windows registry (Machine + User).
 *
 * When a packaged Electron app is launched from the Start Menu, desktop shortcut,
 * or Explorer, its `process.env.PATH` is inherited from the Explorer shell process.
 * If the user installed tools (Python, Node.js, npm, etc.) after Explorer started
 * — or without restarting Explorer — those new PATH entries won't be in
 * `process.env.PATH`. This causes commands like `python`, `npm`, `pip` to be
 * missing from the cowork session even though they work fine in a freshly opened
 * terminal (which reads the latest registry values).
 *
 * This function reads the current Machine and User PATH directly from the registry
 * to get the most up-to-date values, similar to how `resolveUserShellPath()` works
 * for macOS/Linux.
 */
function resolveWindowsRegistryPath(): string | null {
}

/**
 * Merge the current process PATH with registry-resolved PATH on Windows.
 *
 * This ensures that any PATH entries the user has added (e.g. Python, Node.js,
 * npm, pip) are available even if the Electron app inherited a stale PATH from
 * Explorer. The registry PATH entries are appended after the current entries
 * so that any overrides already in the env (like Git toolchain, shims) take priority.
 */
function ensureWindowsRegistryPathEntries(env: Record<string, string | undefined>): void {
}

/**
 * Cached git-bash path on Windows. Resolved once and reused.
 */

function normalizeWindowsPath(input: string | undefined): string | null {
}

function listWindowsCommandPaths(command: string): string[] {
}

function listGitInstallPathsFromRegistry(): string[] {
}

function getBundledGitBashCandidates(): string[] {
}

function checkWindowsGitBashHealth(bashPath: string): { ok: boolean; reason?: string } {
}

function truncateDiagnostic(message: string, maxLength = 500): string {
}

function getWindowsGitToolDirs(bashPath: string): string[] {
}

function ensureElectronNodeShim(electronPath: string, npmBinDir?: string): string | null {
}

/**
 * Resolve git-bash path on Windows.
 * Claude Code CLI requires git-bash for shell tool execution.
 * Priority: env var override > bundled PortableGit > installed Git > PATH lookup.
 * Every candidate must pass a health check (`cygpath -u`) before use.
 */
function resolveWindowsGitBashPath(): string | null {
}

/**
 * Windows system directories that must be in PATH for built-in commands
 * (ipconfig, systeminfo, netstat, ping, nslookup, etc.) to work.
 */

/**
 * Critical Windows environment variables that some system commands and DLLs depend on.
 * Without these, commands like ipconfig may fail even if System32 is in PATH.
 */
const WINDOWS_CRITICAL_ENV_VARS: Record<string, ();

/**
 * Ensure critical Windows system environment variables are present in the env object.
 *
 * Packaged Electron apps or certain launch contexts may strip environment variables
 * like SystemRoot, windir, COMSPEC, and SYSTEMDRIVE. Many Windows system commands
 * and DLLs depend on these variables to locate system resources.
 *
 * Additionally, the Claude Agent SDK's shell snapshot mechanism runs `echo $PATH`
 * via `shell: true`, which on Windows uses cmd.exe. The captured PATH is then
 * baked into the snapshot file. If these critical variables are missing, the shell
 * environment may be broken and commands fail silently.
 */
function ensureWindowsSystemEnvVars(env: Record<string, string | undefined>): void {
}

/**
 * Ensure Windows system directories (System32, etc.) are present in PATH.
 *
 * When the Electron app launches, process.env.PATH normally includes System32.
 * However, the Claude Agent SDK creates a "shell snapshot" by running git-bash
 * with `-c -l` (login shell). The git-bash `/etc/profile` rebuilds PATH based on
 * MSYS2_PATH_TYPE (default: "inherit"), which preserves ORIGINAL_PATH from the
 * inherited environment. If System32 entries are somehow missing from the inherited
 * PATH, they won't appear in the snapshot either.
 *
 * This function ensures that essential Windows system directories are always
 * present in PATH before the environment is handed to the SDK.
 */
function ensureWindowsSystemPathEntries(env: Record<string, string | undefined>): void {
}

/**
 * Ensure non-login git-bash invocations can resolve core MSYS commands.
 *
 * Claude Agent SDK invokes `cygpath` during Windows path normalization via
 * `execSync(..., { shell: bash.exe })`, which does NOT always run a login shell.
 * In that code path, bash may inherit Windows-format PATH directly, and command
 * lookup for `cygpath` can fail because PATH is semicolon-delimited.
 *
 * Prefixing PATH with `/usr/bin:/bin` keeps Windows PATH semantics (semicolon
 * delimiter) while giving bash a valid colon-delimited segment at the beginning.
 * This prevents errors like: `/bin/bash: line 1: cygpath: command not found`.
 */
function ensureWindowsBashBootstrapPath(env: Record<string, string | undefined>): void {
}

/**
 * Convert a single Windows path to MSYS2/POSIX format.
 *
 * When the Windows path contains non-ASCII characters (e.g. Chinese usernames
 * like C:\Users\中文用户\...), MSYS2's automatic Windows→POSIX conversion may
 * corrupt the path if it runs before LANG=C.UTF-8 takes effect. Pre-converting
 * to POSIX format (/c/Users/中文用户/...) bypasses this problematic conversion
 * because MSYS2 recognises the value as already POSIX and passes it through
 * directly to its internal wide-char file APIs.
 */
function singleWindowsPathToPosix(windowsPath: string): string {
}

/**
 * Convert a Windows-format PATH string to MSYS2/POSIX format for git-bash.
 *
 * Windows PATH uses semicolons (;) as delimiters and backslash paths (C:\...),
 * while MSYS2 bash expects colons (:) and forward-slash POSIX paths (/c/...).
 *
 * When Node.js passes env vars to a forked process, PATH stays in Windows format.
 * If the CLI later spawns git-bash, the /etc/profile uses ORIGINAL_PATH="${PATH}"
 * and appends it to the new PATH with a colon. But since the Windows PATH still
 * has semicolons inside, it becomes one giant invalid path entry.
 *
 * This function converts each semicolon-separated Windows path entry to its
 * POSIX equivalent so that git-bash can correctly parse all entries.
 */
function convertWindowsPathToMsys(windowsPath: string): string {
}

/**
 * Set ORIGINAL_PATH with POSIX-converted PATH for git-bash to inherit.
 *
 * Git-bash's /etc/profile (with MSYS2_PATH_TYPE=inherit) reads ORIGINAL_PATH
 * and appends it to the MSYS2 PATH. However, if ORIGINAL_PATH contains
 * Windows-format paths (semicolons, backslashes), bash treats them as a single
 * invalid entry because it uses colons as the PATH delimiter.
 *
 * By pre-setting ORIGINAL_PATH to the POSIX-converted version of our PATH,
 * we ensure that /etc/profile appends properly formatted, colon-separated
 * paths that bash can actually use.
 */
function ensureWindowsOriginalPath(env: Record<string, string | undefined>): void {
}

/**
 * Create a bash init script that sets the Windows console code page to UTF-8 (65001).
 *
 * On Chinese Windows, the default console code page is GBK (936). When git-bash
 * executes Windows native commands (dir, ipconfig, systeminfo, net, type, etc.),
 * they output text encoded in the active console code page. If the code page is GBK,
 * the output contains GBK-encoded bytes, but the Claude Agent SDK reads them as UTF-8,
 * producing garbled characters (mojibake).
 *
 * By setting BASH_ENV to this script, every non-interactive bash session spawned by
 * the Claude Agent SDK will automatically switch the console code page to UTF-8
 * before executing any commands.
 */
function ensureWindowsBashUtf8InitScript(): string | null {
}

function applyPackagedEnvOverrides(env: Record<string, string | undefined>): void {
}

/**
 * Verify that node/npx/npm can be resolved from the constructed environment PATH.
 * Logs diagnostic info for debugging MCP server startup issues on macOS.
 */
function verifyNodeEnvironment(env: Record<string, string | undefined>): void {
}

/**
 * Get SKILLs directory path (handles both development and production)
 */
export function getSkillsRoot(): string {
  if (app.isPackaged) {
  }

  // In development, __dirname can vary with bundling output (e.g. dist-electron/ or dist-electron/libs/).
  // Resolve from several stable anchors and pick the first existing SKILLs directory.

  for (const candidate of candidates) {
  }

  // Final fallback for first-run dev environments where SKILLs may not exist yet.

/**
 * Get enhanced environment variables (including proxy configuration)
 * Async function to fetch system proxy and inject into environment variables
 */
export async function getEnhancedEnv(target: OpenAICompatProxyTarget = 'local'): Promise<Record<string, string | undefined>> {


  // Inject SKILLs directory path for skill scripts.
  // On Windows, normalise backslashes to forward slashes so the value is usable
  // in both Node.js (which accepts forward slashes) and bash (which treats
  // backslashes as escape characters).
  if (process.platform === 'win32' || env.LOBSTERAI_NODE_SHIM_ACTIVE === '1') {
  }

  // Inject internal API base URL for skill scripts (e.g. scheduled-task creation)
  if (internalApiBaseURL) {
  }

  // Skip system proxy resolution if proxy env vars already exist
  if (env.http_proxy || env.HTTP_PROXY || env.https_proxy || env.HTTPS_PROXY) {
  }

  // User can disable system proxy from settings.

  // Resolve proxy from system settings
  if (proxyUrl) {
  }


/**
 * Ensure the cowork temp directory exists in the given working directory
 * @param cwd Working directory path
 * @returns Path to the temp directory
 */
export function ensureCoworkTempDir(cwd: string): string {
      // Fall back to cwd if we can't create the temp dir

/**
 * Get enhanced environment variables with TMPDIR set to the cowork temp directory
 * This ensures Claude Agent SDK creates temporary files in the user's working directory
 * @param cwd Working directory path
 */
export async function getEnhancedEnvWithTmpdir(

  // Set temp directory environment variables for all platforms



function buildAnthropicMessagesUrl(baseUrl: string): string {
}

function extractApiErrorSnippet(rawText: string): string {
}

function extractTextFromAnthropicResponse(payload: unknown): string {
}

function normalizeTitleToPlainText(value: string, fallback: string): string {
}

function buildFallbackSessionTitle(userIntent: string | null): string {
}

export async function probeCoworkModelReadiness(
  if (!config) {
  }



    if (!response.ok) {
    }

    if (error instanceof Error && error.name === 'AbortError') {
    }

export async function generateSessionTitle(userIntent: string | null): Promise<string> {
  if (!normalizedInput) {
  }

  if (!config) {
  }




    if (!response.ok) {
    }

