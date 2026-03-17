import type { QuickActionsConfig, QuickAction, Prompt, LocalizedQuickAction, QuickActionsI18n } from '../types/quickAction';
import { i18nService } from './i18n';


class QuickActionService {

  /**
   * 加载快捷操作配置
   */
  async loadConfig(): Promise<QuickActionsConfig> {
  }

  /**
   * 加载国际化数据
   */
  async loadI18n(): Promise<QuickActionsI18n> {
  }

  /**
   * 获取所有快捷操作（已本地化）
   */
  async getLocalizedActions(): Promise<LocalizedQuickAction[]> {
  }

  /**
   * 获取所有快捷操作（原始数据）
   */
  async getActions(): Promise<QuickAction[]> {
  }

  /**
   * 根据 ID 获取快捷操作（已本地化）
   */
  async getLocalizedActionById(id: string): Promise<LocalizedQuickAction | undefined> {
  }

  /**
   * 根据 ID 获取快捷操作（原始数据）
   */
  async getActionById(id: string): Promise<QuickAction | undefined> {
  }

  /**
   * 根据 actionId 和 promptId 获取提示词（原始数据）
   */
  async getPrompt(actionId: string, promptId: string): Promise<Prompt | undefined> {
  }

  /**
   * 根据 skillMapping 获取对应的快捷操作（已本地化）
   */
  async getLocalizedActionBySkillMapping(skillMapping: string): Promise<LocalizedQuickAction | undefined> {
  }

  /**
   * 根据 skillMapping 获取对应的快捷操作（原始数据）
   */
  async getActionBySkillMapping(skillMapping: string): Promise<QuickAction | undefined> {
  }

  /**
   * 订阅语言变化事件
   */
    return () => {
    };

  /**
   * 通知所有订阅者
   */
  private notifyListeners(): void {
  }

  /**
   * 清除缓存（用于重新加载）
   */
  clearCache(): void {
  }

  /**
   * 初始化服务（订阅语言变化）
   */
  initialize(): void {
  }

export const quickActionService = new QuickActionService();
