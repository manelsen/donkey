/**
 * IM Media Instruction Builder
 * 
 * 构建 IM 媒体发送能力的系统提示词指令。
 * 当 AI 通过 IM 渠道（钉钉、飞书、Telegram、Discord、云信）与用户交互时，
 * 需要告知 AI 可以通过特定的文本标记格式来触发图片/音视频/文件的发送。
 * 
 * 该指令会被追加到系统提示词的末尾，确保 AI 始终了解自己的媒体发送能力。
 */

import type { IMSettings } from './types';

/**
 * Build the IM media sending instruction for system prompt.
 * Returns the instruction text, or empty string if not applicable.
 */
export function buildIMMediaInstruction(_imSettings: IMSettings): string {
  // Always include the media instruction for IM sessions.
  // The actual sending is handled by each gateway's replyFn (parseMediaMarkers → sendMedia).
  // This instruction tells the AI how to format its response to trigger media sending.










