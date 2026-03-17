import { app, BrowserWindow, session } from 'electron';
import { execSync, spawn, spawnSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import extractZip from 'extract-zip';
import { SqliteStore } from './sqliteStore';
import { cpRecursiveSync } from './fsCompat';
import { getElectronNodeRuntimePath } from './libs/coworkUtil';
import { appendPythonRuntimeToEnv } from './libs/pythonRuntime';

/**
 * Resolve the user's login shell PATH on macOS/Linux.
 * Packaged Electron apps on macOS don't inherit the user's shell profile,
 * so node/npm won't be in PATH unless we resolve it explicitly.
 */
function resolveUserShellPath(): string | null {
}

/**
 * Check if a command exists in the given environment.
 */
function hasCommand(command: string, env: NodeJS.ProcessEnv): boolean {
}

/**
 * Normalize the PATH key in an env object on Windows.
 * Windows env vars are case-insensitive, but JS objects are case-sensitive.
 * After spreading process.env, the key might be "Path" or "PATH".
 * We normalize to "PATH" to avoid issues with duplicate keys.
 */
function normalizePathKey(env: Record<string, string | undefined>): void {
}

/**
 * Resolve the latest Windows system PATH from the registry.
 * When an Electron app is launched from Start Menu or Explorer,
 * process.env.PATH may be stale (missing tools installed after Explorer started).
 */
function resolveWindowsRegistryPath(): string | null {
}

/**
 * Build an environment for spawning skill scripts.
 * Merges the user's shell PATH with the current process environment.
 */
function buildSkillEnv(): Record<string, string | undefined> {
}

export type SkillRecord = {

type SkillStateMap = Record<string, { enabled: boolean }>;

type EmailConnectivityCheckCode = 'imap_connection' | 'smtp_connection';
type EmailConnectivityCheckLevel = 'pass' | 'fail';
type EmailConnectivityVerdict = 'pass' | 'fail';

type EmailConnectivityCheck = {

type EmailConnectivityTestResult = {

type SkillDefaultConfig = {

type SkillsConfig = {



const parseFrontmatter = (raw: string): { frontmatter: Record<string, unknown>; content: string } => {
  if (!match) {
  }

let frontmatter: Record<string, unknown>;


const isTruthy = (value?: unknown): boolean => {

const extractDescription = (content: string): string => {
  for (const line of lines) {
  }

const normalizeFolderName = (name: string): string => {

const isZipFile = (filePath: string): boolean => path.extname(filePath).toLowerCase() === '.zip';

/**
 * Compare two semver-like version strings (e.g. "1.0.0" vs "1.0.1").
 * Returns 1 if a > b, -1 if a < b, 0 if equal.
 * Non-numeric segments are treated as 0.
 */
const compareVersions = (a: string, b: string): number => {

const resolveWithin = (root: string, target: string): string => {

const appendEnvPath = (current: string | undefined, entries: string[]): string => {

const listWindowsCommandPaths = (command: string): string[] => {


const resolveWindowsGitExecutable = (): string | null => {



  for (const candidate of installedCandidates) {
  }

  for (const candidate of whereCandidates) {
  }


  for (const root of bundledRoots) {
  }


const resolveGitCommand = (): { command: string; env?: NodeJS.ProcessEnv } => {
  if (process.platform !== 'win32') {
  }

  if (!gitExe) {
  }

const env: NodeJS.ProcessEnv;


    if (code === 0) {
    }

type SkillScriptRunResult = {


let forceKillTimer: NodeJS.Timeout | null;

  const settle = (result: SkillScriptRunResult) => {





const cleanupPathSafely = (targetPath: string | null): void => {

const listSkillDirs = (root: string): string[] => {


const collectSkillDirsFromSource = (source: string): string[] => {

    if (nestedSkills.length > 0) {
    }

  if (directSkills.length > 0) {
  }


const collectSkillDirsRecursively = (root: string): string[] => {

const matchedDirs: string[];
const queue: string[];

  while (queue.length > 0) {
  }


const deriveRepoName = (source: string): string => {

type NormalizedGitSource = {

type GithubRepoSource = {

const extractErrorMessage = (error: unknown): string => {
  if (error instanceof Error) {
  }

const parseGithubRepoSource = (repoUrl: string): GithubRepoSource | null => {

  if (sshMatch) {
  }


    if (segments.length < 2) {
    }


const archiveUrlCandidates: Array<{ url: string; headers: Record<string, string> }>;

  if (encodedRef) {
  }


let buffer: Buffer | null;
let lastError: string | null;

  for (const candidate of archiveUrlCandidates) {
  }

  if (!buffer) {
  }



  if (extractedDirs.length === 1) {
  }


const isRemoteZipUrl = (source: string): boolean => {

const downloadZipUrl = async (zipUrl: string, tempRoot: string): Promise<string> => {

  if (!response.ok) {
  }



  if (extractedDirs.length === 1) {
  }


const normalizeGithubSubpath = (value: string): string | null => {

const parseGithubTreeOrBlobUrl = (source: string): NormalizedGitSource | null => {

    if (segments.length < 5) {
    }


    if (!repo || !sourceSubpath) {
    }


const isWebSearchSkillBroken = (skillRoot: string): boolean => {




export class SkillManager {


  getSkillsRoot(): string {
  }

  ensureSkillsRoot(): string {
  }

  syncBundledSkillsToUserData(): void {
  }

  /**
   * Check if a skill's runtime is healthy by comparing with bundled version.
   * Returns false if bundled has dependencies but target doesn't.
   */
  private isSkillRuntimeHealthy(targetDir: string, bundledDir: string): boolean {
  }

  private getSkillVersion(skillDir: string): string {
  }

  private mergeSkillsConfig(bundledPath: string, targetPath: string): void {
  }

  listSkills(): SkillRecord[] {
  }

  buildAutoRoutingPrompt(): string | null {
  }

  setSkillEnabled(id: string, enabled: boolean): SkillRecord[] {
  }

  deleteSkill(id: string): SkillRecord[] {
  }

  async downloadSkill(source: string): Promise<{ success: boolean; skills?: SkillRecord[]; error?: string }> {
  }

  startWatching(): void {
  }

  stopWatching(): void {
  }

  handleWorkingDirectoryChange(): void {
  }

  private scheduleNotify(): void {
  }

  private notifySkillsChanged(): void {
  }


  private listBuiltInSkillIds(): Set<string> {
  }

  private isBuiltInSkillId(id: string): boolean {
  }

  private loadSkillStateMap(): SkillStateMap {
  }

  private saveSkillStateMap(map: SkillStateMap): void {
  }

  private loadSkillsDefaults(roots: string[]): Record<string, SkillDefaultConfig> {
  }

  private getSkillRoots(primaryRoot?: string): string[] {
  }

  private getClaudeSkillsRoot(): string | null {
  }

  private getBundledSkillsRoot(): string {
  }

  getSkillConfig(skillId: string): { success: boolean; config?: Record<string, string>; error?: string } {
  }

  setSkillConfig(skillId: string, config: Record<string, string>): { success: boolean; error?: string } {
  }

  private repairSkillFromBundled(skillId: string, skillPath: string): boolean {
  }

  private ensureSkillDependencies(skillDir: string): { success: boolean; error?: string } {
  }


      // Ensure dependencies are installed before running scripts
      if (!depsResult.success) {
      }


      // Mask password for logging




const checks: EmailConnectivityCheck[];
const verdict: EmailConnectivityVerdict;



  private resolveSkillDir(skillId: string): string {
  }

  private getScriptRuntimeCandidates(env: NodeJS.ProcessEnv): Array<{ command: string; extraEnv?: NodeJS.ProcessEnv }> {
  }

let lastResult: SkillScriptRunResult | null;

    // Build base environment with user's shell PATH

const env: NodeJS.ProcessEnv;

      if (result.spawnErrorCode === 'ENOENT') {
      }


  private parseScriptMessage(stdout: string): string | null {
  }

  private getLastOutputLine(text: string): string {
  }


    if (result.success) {
    }



  private normalizeGitSource(source: string): NormalizedGitSource | null {
  }

export const __skillManagerTestUtils = {
