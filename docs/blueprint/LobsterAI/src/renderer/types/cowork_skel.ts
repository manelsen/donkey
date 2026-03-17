// Cowork image attachment for vision-capable models
export interface CoworkImageAttachment {

// Cowork session status
export type CoworkSessionStatus = 'idle' | 'running' | 'completed' | 'error';

// Cowork message types
export type CoworkMessageType = 'user' | 'assistant' | 'tool_use' | 'tool_result' | 'system';

// Cowork execution mode
export type CoworkExecutionMode = 'auto' | 'local' | 'sandbox';

// Cowork message metadata
export interface CoworkMessageMetadata {

// Cowork message
export interface CoworkMessage {

// Cowork session
export interface CoworkSession {

// Cowork configuration
export interface CoworkConfig {

export type CoworkConfigUpdate = Partial<Pick<

export interface CoworkApiConfig {

export type CoworkSandboxStatus = {

export type CoworkSandboxProgress = {

export type CoworkUserMemoryStatus = 'created' | 'stale' | 'deleted';

export interface CoworkUserMemoryEntry {

export interface CoworkMemoryStats {

// Cowork pending permission request
export interface CoworkPermissionRequest {

export type CoworkPermissionResult =

// Cowork permission response
export interface CoworkPermissionResponse {

// Session summary for list display (without full messages)
export interface CoworkSessionSummary {

// Start session options
export interface CoworkStartOptions {

// Continue session options
export interface CoworkContinueOptions {

// IPC result types
export interface CoworkSessionResult {

export interface CoworkSessionListResult {

export interface CoworkConfigResult {

// Stream event types for IPC communication
export type CoworkStreamEventType =

export interface CoworkStreamEvent {
