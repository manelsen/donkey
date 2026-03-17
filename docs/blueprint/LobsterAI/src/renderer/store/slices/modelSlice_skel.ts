import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import { defaultConfig } from '../../config';

export interface Model {

export function getModelIdentityKey(model: Pick<Model, 'id' | 'providerKey'>): string {

export function isSameModelIdentity(
  if (modelA.id !== modelB.id) {
  }
  if (modelA.providerKey && modelB.providerKey) {
  }
  // 兼容旧配置：缺失 providerKey 时回退到 id 匹配

// 从 providers 配置中构建初始可用模型列表
function buildInitialModels(): Model[] {
}

// 初始可用模型列表（会在运行时更新）
export let availableModels: Model[] = buildInitialModels();

interface ModelState {

const initialState: ModelState;
  // 使用 config 中的默认模型

      // 更新导出的 availableModels
      // 同步选中模型信息，确保名称与最新配置一致
      if (action.payload.length > 0) {
      }

export const { setSelectedModel, setAvailableModels } = modelSlice.actions;
export default modelSlice.reducer; 
