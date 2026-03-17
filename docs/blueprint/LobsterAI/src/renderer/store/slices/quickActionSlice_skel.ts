import { createSlice, PayloadAction } from '@reduxjs/toolkit';
import type { LocalizedQuickAction } from '../../types/quickAction';

interface QuickActionState {
  /** 快捷操作列表（已本地化） */
  /** 当前选中的 action ID */
  /** 当前选中的 prompt ID */
  /** 是否正在加载 */

const initialState: QuickActionState;

    /** 设置快捷操作列表 */
    /** 选择快捷操作 */
      // 切换 action 时清空 prompt 选择
    /** 选择提示词 */
    /** 设置加载状态 */
    /** 清空选择 */

export const {

export default quickActionSlice.reducer;
