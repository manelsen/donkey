/**
 * IM Gateway Types for Renderer Process
 * Mirrors src/main/im/types.ts for use in React components
 */

// ==================== DingTalk Types ====================

export interface DingTalkConfig {

export interface DingTalkGatewayStatus {

// ==================== Feishu Types ====================

export interface FeishuConfig {

export interface FeishuGatewayStatus {

// ==================== Telegram Types ====================

export interface TelegramConfig {

export interface TelegramGatewayStatus {

// ==================== Discord Types ====================

export interface DiscordConfig {

export interface DiscordGatewayStatus {

// ==================== NIM (NetEase IM) Types ====================

export type NimTeamPolicy = 'open' | 'allowlist' | 'disabled';

export interface NimConfig {
  // 群组消息配置
  // QChat 圈组配置

export interface NimGatewayStatus {

// ==================== Xiaomifeng Types ====================

export interface XiaomifengConfig {

export interface XiaomifengGatewayStatus {

// ==================== QQ Types ====================

export interface QQConfig {

export interface QQGatewayStatus {

// ==================== WeCom (企业微信) Types ====================

export interface WecomConfig {

export interface WecomGatewayStatus {

// ==================== Common IM Types ====================

export type IMPlatform = 'dingtalk' | 'feishu' | 'qq' | 'telegram' | 'discord' | 'nim' | 'xiaomifeng' | 'wecom';

export interface IMGatewayConfig {

export interface IMSettings {

export interface IMGatewayStatus {

// ==================== Media Attachment Types ====================

export type IMMediaType = 'image' | 'video' | 'audio' | 'voice' | 'document' | 'sticker';

export interface IMMediaAttachment {

export interface IMMessage {

// ==================== IPC Result Types ====================

export interface IMConfigResult {

export interface IMStatusResult {

export interface IMGatewayResult {

// ==================== Connectivity Test Types ====================

export type IMConnectivityVerdict = 'pass' | 'warn' | 'fail';

export type IMConnectivityCheckLevel = 'pass' | 'info' | 'warn' | 'fail';

export type IMConnectivityCheckCode =

export interface IMConnectivityCheck {

export interface IMConnectivityTestResult {

export interface IMConnectivityTestResponse {

// ==================== Default Configurations ====================

export const DEFAULT_DINGTALK_CONFIG: DingTalkConfig = {

export const DEFAULT_FEISHU_CONFIG: FeishuConfig = {

export const DEFAULT_TELEGRAM_CONFIG: TelegramConfig = {

export const DEFAULT_DISCORD_CONFIG: DiscordConfig = {

export const DEFAULT_NIM_CONFIG: NimConfig = {

export const DEFAULT_XIAOMIFENG_CONFIG: XiaomifengConfig = {

export const DEFAULT_QQ_CONFIG: QQConfig = {

export const DEFAULT_WECOM_CONFIG: WecomConfig = {

export const DEFAULT_IM_SETTINGS: IMSettings = {

export const DEFAULT_IM_CONFIG: IMGatewayConfig = {

export const DEFAULT_IM_STATUS: IMGatewayStatus = {
