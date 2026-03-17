/**
 * QuickAction 类型定义
 * 用于首页快捷操作功能
 */

/**
 * 预制提示词（原始结构，从JSON加载）
 */
export interface Prompt {
  /** 唯一标识 */

/**
 * 本地化后的预制提示词（包含翻译后的文本）
 */
export interface LocalizedPrompt {
  /** 唯一标识 */
  /** 显示标题 */
  /** 简短描述 */
  /** 完整提示词内容 */

/**
 * 快捷操作主项（原始结构，从JSON加载）
 */
export interface QuickAction {
  /** 唯一标识 */
  /** 图标名称（Heroicons） */
  /** 主题色（hex） */
  /** 映射到 Skill ID */
  /** 预制提示词列表 */

/**
 * 本地化后的快捷操作主项（包含翻译后的文本）
 */
export interface LocalizedQuickAction {
  /** 唯一标识 */
  /** 显示标题 */
  /** 图标名称（Heroicons） */
  /** 主题色（hex） */
  /** 映射到 Skill ID */
  /** 预制提示词列表（已本地化） */

/**
 * 快捷操作配置（原始结构）
 */
export interface QuickActionsConfig {
  /** 配置版本 */
  /** 快捷操作列表 */

/**
 * 国际化配置结构
 */
export interface QuickActionsI18n {

export interface QuickActionsI18nData {
