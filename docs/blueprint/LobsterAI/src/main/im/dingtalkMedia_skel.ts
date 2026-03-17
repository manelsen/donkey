/**
 * DingTalk Media Upload Utilities
 * 钉钉媒体上传工具函数
 */
import axios from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import FormData from 'form-data';
import { sanitizeLogArgs, sanitizeSensitiveString } from './logSanitizer';


// 旧版 oapi access_token 缓存
let oapiAccessToken: string | null;

export type DingTalkMediaType = 'image' | 'voice' | 'video' | 'file';

export interface MediaUploadResult {

// 文件扩展名分类

/**
 * 获取旧版 oapi access_token
 * 旧版 oapi 接口需要使用不同的 token 获取方式
 */
export async function getOapiAccessToken(appKey: string, appSecret: string): Promise<string> {
  if (oapiAccessToken && oapiTokenExpiry > now + 60000) {
  }


  const response = await axios.get<{ access_token: string; expires_in: number; errcode?: number; errmsg?: string }>(

  if (response.data.errcode && response.data.errcode !== 0) {
  }


/**
 * 上传媒体文件到钉钉
 */
export async function uploadMediaToDingTalk(

    // 处理路径（支持 file:// 协议）


    // 验证文件


    if (stats.size > MAX_FILE_SIZE) {
    }

    // 创建 FormData
    // 使用自定义文件名或从路径提取


    // 上传到钉钉



    if (response.data.errcode && response.data.errcode !== 0) {
    }


/**
 * 根据文件扩展名确定媒体类型
 */
export function detectMediaType(filePath: string): DingTalkMediaType {

/**
 * 获取文件 MIME 类型
 */
export function getMimeType(filePath: string): string {
const mimeMap: Record<string, string>;

/**
 * 判断文件路径是否为图片
 */
export function isImagePath(filePath: string): boolean {
