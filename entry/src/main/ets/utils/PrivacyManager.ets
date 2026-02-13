/**
 * 隐私政策管理器
 * 用于管理用户隐私政策同意状态
 */
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

export class PrivacyManager {
  private static instance: PrivacyManager;
  private dataPreferences: preferences.Preferences | null = null;
  private readonly PRIVACY_AGREED_KEY = 'privacy_agreed';
  private readonly PREFERENCES_NAME = 'privacy_preferences';

  private constructor() {}

  static getInstance(): PrivacyManager {
    if (!PrivacyManager.instance) {
      PrivacyManager.instance = new PrivacyManager();
    }
    return PrivacyManager.instance;
  }

  /**
   * 初始化隐私管理器
   * @param context UIAbilityContext
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.dataPreferences = await preferences.getPreferences(context, this.PREFERENCES_NAME);
      hilog.info(0xFF00, '[PrivacyManager]', 'Privacy manager initialized successfully');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, '[PrivacyManager]', `Failed to initialize privacy manager: ${error.message}`);
      throw new Error(`Failed to initialize privacy manager: ${error.message}`);
    }
  }

  /**
   * 检查用户是否已同意隐私政策
   * @returns Promise<boolean> 是否已同意
   */
  async hasAgreedToPrivacy(): Promise<boolean> {
    try {
      if (!this.dataPreferences) {
        hilog.warn(0xFF00, '[PrivacyManager]', 'Privacy manager not initialized');
        return false;
      }
      
      const agreed = await this.dataPreferences.get(this.PRIVACY_AGREED_KEY, false);
      hilog.info(0xFF00, '[PrivacyManager]', `Privacy agreement status: ${agreed}`);
      return agreed as boolean;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, '[PrivacyManager]', `Failed to check privacy agreement: ${error.message}`);
      return false;
    }
  }

  /**
   * 设置用户同意隐私政策
   */
  async setPrivacyAgreed(): Promise<void> {
    try {
      if (!this.dataPreferences) {
        hilog.error(0xFF00, '[PrivacyManager]', 'Privacy manager not initialized');
        return;
      }

      hilog.info(0xFF00, '[PrivacyManager]', 'Setting privacy agreement to true');
      await this.dataPreferences.put(this.PRIVACY_AGREED_KEY, true);
      await this.dataPreferences.flush();
      hilog.info(0xFF00, '[PrivacyManager]', 'Privacy agreement status saved successfully');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, '[PrivacyManager]', `Failed to save privacy agreement: ${error.message}`);
      throw new Error(`Failed to save privacy agreement: ${error.message}`);
    }
  }

  /**
   * 重置隐私政策状态（用于测试）
   */
  async resetPrivacyAgreement(): Promise<void> {
    try {
      if (!this.dataPreferences) {
        hilog.error(0xFF00, '[PrivacyManager]', 'Privacy manager not initialized');
        return;
      }

      await this.dataPreferences.delete(this.PRIVACY_AGREED_KEY);
      await this.dataPreferences.flush();
      hilog.info(0xFF00, '[PrivacyManager]', 'Privacy agreement status reset');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, '[PrivacyManager]', `Failed to reset privacy agreement: ${error.message}`);
      throw new Error(`Failed to reset privacy agreement: ${error.message}`);
    }
  }
}
