/**
 * DingTalk Media Marker Parser
 * 解析文本中的媒体标记
 */
import type { MediaMarker } from './types';

// 文件扩展名分类
// 文档/文件扩展名（非媒体类型，但需要作为文件发送）

// 正则表达式模式
// Markdown 图片: ![alt](path) - 匹配本地路径
// 支持: file:/// 协议, 常见系统路径, 以及 ~/.lobsterai 等用户目录路径
const MARKDOWN_IMAGE_RE = /!\[([^\]]*)\]\(((?:file:\/\/\/|\/(?:tmp|var|private|Users|home|root)|~\/|[A-Za-z]:)[^)]+)\)/g;

// Markdown 链接: [text](path) - 匹配本地媒体文件路径
// 用于识别普通链接中的音视频文件
const MARKDOWN_LINK_RE = /\[([^\]]*)\]\(((?:file:\/\/\/|\/(?:tmp|var|private|Users|home|root)|~\/|[A-Za-z]:)[^)]+)\)/g;

// 裸路径图片: /path/to/image.png
const BARE_IMAGE_PATH_RE = /(?:^|\s)((?:\/(?:tmp|var|private|Users|home|root)\/[^\s`'",)]+|~\/[^\s`'",)]+|[A-Za-z]:[\\/][^\s`'",)]+)\.(?:png|jpg|jpeg|gif|bmp|webp))(?:\s|$|[,.])/gi;

// 裸路径音视频: /path/to/audio.mp3 或 /path/to/video.mp4
const BARE_MEDIA_PATH_RE = /(?:^|\s)((?:\/(?:tmp|var|private|Users|home|root)\/[^\s`'",)]+|~\/[^\s`'",)]+|[A-Za-z]:[\\/][^\s`'",)]+)\.(?:mp3|wav|ogg|amr|m4a|aac|mp4|mov))(?:\s|$|[,.])/gi;

// 裸路径文件: /path/to/file.txt, /path/to/file.pdf 等
const BARE_FILE_PATH_RE = /(?:^|\s)((?:\/(?:tmp|var|private|Users|home|root)\/[^\s`'",)]+|~\/[^\s`'",)]+|[A-Za-z]:[\\/][^\s`'",)]+)\.(?:txt|pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|tar|gz|json|xml|csv|md|html|htm|js|ts|py|java|c|cpp|h|cs|go|rs|rb|php|sh))(?:\s|$|[,.])/gi;

// 视频标记: [DINGTALK_VIDEO]{"path":"..."}[/DINGTALK_VIDEO]

// 音频标记: [DINGTALK_AUDIO]{"path":"..."}[/DINGTALK_AUDIO]

// 文件标记: [DINGTALK_FILE]{"path":"...","name":"..."}[/DINGTALK_FILE]

/**
 * 根据文件扩展名判断媒体类型
 */
function getMediaTypeByExtension(filePath: string): 'image' | 'audio' | 'video' | 'file' | null {
}

/**
 * 清理路径（移除 file:// 协议，处理转义空格）
 */
function cleanPath(rawPath: string): string {
}

/**
 * 解析文本中的所有媒体标记
 */
export function parseMediaMarkers(text: string): MediaMarker[] {
const markers: MediaMarker[];


  // 1. 解析 Markdown 图片 ![alt](path)
    // 使用 alt 文本作为文件名（如果有的话），否则从路径提取

  // 2. 解析普通 Markdown 链接 [text](path) 中的媒体文件
    // 使用链接文本作为文件名（如果有的话）

  // 3. 解析裸图片路径

  // 4. 解析裸音视频路径

  // 5. 解析裸文件路径 (txt, pdf, doc, etc.)

  // 6. 解析视频标记 [DINGTALK_VIDEO]

  // 7. 解析音频标记 [DINGTALK_AUDIO]

  // 8. 解析文件标记 [DINGTALK_FILE]



/**
 * 从文本中移除已处理的媒体标记
 */
export function stripMediaMarkers(text: string, markers: MediaMarker[]): string {
  for (const marker of markers) {
  }
  // 清理多余空行
