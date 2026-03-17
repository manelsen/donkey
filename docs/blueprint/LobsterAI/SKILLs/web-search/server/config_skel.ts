/**
 * Web Search Skill Configuration
 */

export interface BrowserConfig {
  /** Chrome executable path (auto-detected if not provided) */
  /** CDP debugging port */
  /** User data directory for browser isolation */
  /** Whether to run browser headless */
  /** Additional Chrome flags */

export interface ServerConfig {
  /** Bridge server port */
  /** Bridge server host */

export interface SearchConfig {
  /** Default search engine */
  /** Engine fallback order when defaultEngine is auto */
  /** Default max results per search */
  /** Search timeout in milliseconds */
  /** Navigation timeout in milliseconds */

export interface Config {

/**
 * Default configuration
 */
export const defaultConfig: Config = {

/**
 * Merge user config with defaults
 */
export function mergeConfig(userConfig?: Partial<Config>): Config {
  if (!userConfig) {
  }

