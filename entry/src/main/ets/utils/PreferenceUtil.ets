import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { formBindingData, formProvider, formInfo } from '@kit.FormKit';

const TAG = 'PreferenceUtil';
const DOMAIN = 0x0000;
const PREFERENCES_NAME = 'user_session';

// 会员信息接口
export interface MembershipData {
  level: string;
  expiry: number;
  isVip: boolean;
}

export type MembershipInfo = MembershipData;

export class WatermarkOffset {
  x: number = 0;
  y: number = 0;
}

export class PreferenceUtil {
  private static readonly KEY_THEME = 'app_theme';
  private static readonly KEY_AI_KEY = 'ai_api_key';
  private static readonly KEY_AI_CONFIG_REMINDED = 'ai_config_reminded';
  private static readonly KEY_ANIMATION_ENABLED = 'animation_enabled';
  private static readonly KEY_POINT_LIGHT_ENABLED = 'point_light_enabled';
  private static readonly KEY_SPLIT_VIEW_ENABLED = 'split_view_enabled';
  private static readonly KEY_AI_ENABLED = 'ai_enabled';
  private static readonly KEY_SHOW_VIP_THEME = 'show_vip_theme';
  private static readonly KEY_SMART_GESTURE_ENABLED = 'smart_gesture_enabled';
  private static readonly KEY_THEME_ID = 'app_theme_id';
  private static readonly KEY_SORT_ORDER = 'subscription_sort_order';
  private static readonly KEY_LAST_KNOWN_VERSION = 'last_known_version';
  private static readonly KEY_LAST_AGREEMENT_VERSION = 'last_agreement_version';
  private static readonly KEY_TEXT_WATERMARK_ENABLED = 'text_watermark_enabled';
  private static readonly KEY_WATERMARK_TEXT = 'watermark_text_content';
  private static readonly KEY_APP_LOCK_PASSWORD = 'app_lock_password';
  private static readonly KEY_APP_LOCK_FACE = 'app_lock_face';
  private static readonly KEY_APP_LOCK_FINGERPRINT = 'app_lock_fingerprint';
  private static readonly KEY_APP_LOCK_PASSWORD_LENGTH = 'app_lock_password_length';
  private static readonly KEY_ANIMATION_DURATION = 'animation_duration';
  private static readonly KEY_ANIMATION_DAMPING = 'animation_damping';
  private static readonly KEY_ANIMATION_RESPONSE = 'animation_response';
  private static readonly KEY_ANIMATION_PRESET_MODE = 'animation_preset_mode';
  private static readonly KEY_NEW_YEAR_REMINDER_DISABLED = 'new_year_reminder_disabled';
  private static instance: PreferenceUtil;
  private pref: preferences.Preferences | null = null;
  private context: common.Context | null = null;
  private initPromise: Promise<void> | null = null;

  private constructor() {}

  public static getInstance(): PreferenceUtil {
    if (!PreferenceUtil.instance) {
      PreferenceUtil.instance = new PreferenceUtil();
    }
    return PreferenceUtil.instance;
  }

  public getContext(): common.Context | null {
    return this.context;
  }

  public async loadPreference(context: common.Context): Promise<void> {
    if (this.initPromise) {
      return this.initPromise;
    }
    
    this.initPromise = new Promise(async (resolve) => {
      try {
        this.context = context;
        this.pref = await preferences.getPreferences(context, PREFERENCES_NAME);
        hilog.info(DOMAIN, TAG, 'Preferences initialized');
        resolve();
      } catch (err) {
        const error = err as BusinessError;
        hilog.error(DOMAIN, TAG, `Failed to get preferences. Code:${error.code},message:${error.message}`);
        this.initPromise = null; // Reset to allow retry
        resolve();
      }
    });
    
    return this.initPromise;
  }

  private async ensureInitialized() {
      if (!this.pref && this.initPromise) {
          await this.initPromise;
      }
  }

  public async get(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType> {
    await this.ensureInitialized();
    if (!this.pref) return defaultValue;
    try {
      return await this.pref.get(key, defaultValue);
    } catch (err) {
      return defaultValue;
    }
  }

  public async put(key: string, value: preferences.ValueType): Promise<void> {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(key, value);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to put preference ${key}: ${err}`);
    }
  }

  public async saveSession(isLoggedIn: boolean, unionId: string, userName: string, avatar: string) {
    await this.ensureInitialized();
    if (!this.pref) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized');
      return;
    }
    try {
      await this.pref.put('isLoggedIn', isLoggedIn);
      await this.pref.put('unionId', unionId);
      await this.pref.put('userName', userName);
      await this.pref.put('userAvatar', avatar);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save session. Code:${(err as BusinessError).code},message:${(err as BusinessError).message}`);
    }
  }

  public async saveAppLockPassword(password: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      if (password === '') {
        await this.pref.delete(PreferenceUtil.KEY_APP_LOCK_PASSWORD);
        AppStorage.setOrCreate('hasAppLock', false);
      } else {
        await this.pref.put(PreferenceUtil.KEY_APP_LOCK_PASSWORD, password);
        AppStorage.setOrCreate('hasAppLock', true);
      }
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, `App lock password saved/cleared. hasAppLock=${!!password}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save app lock password: ${err}`);
    }
  }

  public async getAppLockPassword(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return '';
    try {
      const password = await this.pref.get(PreferenceUtil.KEY_APP_LOCK_PASSWORD, '') as string;
      // Sync with AppStorage when reading
      AppStorage.setOrCreate('hasAppLock', !!password);
      
      // 同时同步加载生物识别配置，防止异步竞争导致的逻辑错误
      const face = await this.getAppLockFace();
      const fingerprint = await this.getAppLockFingerprint();
      const length = await this.getAppLockPasswordLength();
      AppStorage.setOrCreate('appLockFace', face);
      AppStorage.setOrCreate('appLockFingerprint', fingerprint);
      AppStorage.setOrCreate('appLockPasswordLength', length);
      
      return password;
    } catch (err) {
      return '';
    }
  }

  public async saveAppLockPasswordLength(length: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_APP_LOCK_PASSWORD_LENGTH, length);
      await this.pref.flush();
      AppStorage.setOrCreate('appLockPasswordLength', length);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save app lock password length: ${err}`);
    }
  }

  public async getAppLockPasswordLength(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 4;
    try {
      const length = await this.pref.get(PreferenceUtil.KEY_APP_LOCK_PASSWORD_LENGTH, 4) as number;
      AppStorage.setOrCreate('appLockPasswordLength', length);
      return length;
    } catch (err) {
      return 4;
    }
  }


  public async saveAppLockFace(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_APP_LOCK_FACE, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('appLockFace', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save app lock face: ${err}`);
    }
  }

  public async getAppLockFace(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return false;
    try {
      return await this.pref.get(PreferenceUtil.KEY_APP_LOCK_FACE, false) as boolean;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get app lock face: ${err}`);
      return false;
    }
  }

  public async saveAppLockFingerprint(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_APP_LOCK_FINGERPRINT, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('appLockFingerprint', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save app lock fingerprint: ${err}`);
    }
  }

  public async getAppLockFingerprint(): Promise<boolean> {
     await this.ensureInitialized();
    if (!this.pref) return false;
    try {
      return await this.pref.get(PreferenceUtil.KEY_APP_LOCK_FINGERPRINT, false) as boolean;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to get app lock fingerprint: ${err}`);
      return false;
    }
  }

  public async loadSession(): Promise<Record<string, Object>> {
    await this.ensureInitialized();
    if (!this.pref) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized');
      return {};
    }
    try {
      const isLoggedIn = await this.pref.get('isLoggedIn', false);
      const unionId = await this.pref.get('unionId', '');
      const userName = await this.pref.get('userName', '');
      const avatar = await this.pref.get('userAvatar', '');
      
      hilog.info(DOMAIN, TAG, `Session loaded: LoggedIn=${isLoggedIn}, User=${userName}`);
      
      return {
        'isLoggedIn': isLoggedIn,
        'unionId': unionId,
        'userName': userName,
        'userAvatar': avatar
      };
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to load session. Code:${error.code},message:${error.message}`);
      return {};
    }
  }

  public async clearSession() {
    await this.ensureInitialized();
    if (!this.pref) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized');
      return;
    }
    try {
      await this.pref.put('isLoggedIn', false);
      await this.pref.put('unionId', '');
      await this.pref.put('userName', '立即登录');
      await this.pref.put('userAvatar', '');
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, 'Session cleared');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to clear session. Code:${error.code},message:${error.message}`);
    }
  }
  public async saveTheme(mode: number) {
    await this.ensureInitialized();
    if (!this.pref) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized');
      return;
    }
    try {
      await this.pref.put('theme_mode', mode);
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, `Theme saved: ${mode}`);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to save theme. Code:${error.code},message:${error.message}`);
    }
  }

  public async loadTheme(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) {
      hilog.error(DOMAIN, TAG, 'Preferences not initialized');
      return 0; // Default to System
    }
    try {
      const mode = await this.pref.get('theme_mode', 0);
      hilog.info(DOMAIN, TAG, `Theme loaded: ${mode}`);
      return mode as number;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, `Failed to load theme. Code:${error.code},message:${error.message}`);
      return 0;
    }
  }

  public async getFormIds(): Promise<string[]> {
    await this.ensureInitialized();
    if (!this.pref) return [];
    try {
      const ids = await this.pref.get('form_ids', []);
      return ids as string[];
    } catch (err) {
      return [];
    }
  }

  public async saveFormId(formId: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      const ids = await this.getFormIds();
      if (!ids.includes(formId)) {
        ids.push(formId);
        await this.pref.put('form_ids', ids);
        await this.pref.flush();
      }
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save formId: ${err}`);
    }
  }

  public async removeFormId(formId: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      let ids = await this.getFormIds();
      if (ids.includes(formId)) {
        ids = ids.filter(id => id !== formId);
        await this.pref.put('form_ids', ids);
        await this.pref.flush();
      }
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to remove formId: ${err}`);
    }
  }

  public async getAIKey(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return '';
    try {
      const key = await this.pref.get('ai_api_key', '');
      return key as string;
    } catch (err) {
      return '';
    }
  }

  public async saveAIKey(key: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put('ai_api_key', key);
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, 'AI API Key saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save AI API Key: ${err}`);
    }
  }

  public async getAIConfigReminded(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return false;
    try {
      const val = await this.pref.get('ai_config_reminded', false);
      return val as boolean;
    } catch (err) {
      return false;
    }
  }

  public async saveAIConfigReminded(reminded: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put('ai_config_reminded', reminded);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save AI config reminded: ${err}`);
    }
  }

  async saveAnimationEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_ANIMATION_ENABLED, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('isAnimationEnabled', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save animation enabled: ${err}`);
    }
  }

  async loadAnimationEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return true; // Default to true if preferences not initialized
    try {
      const enabled = await this.pref.get(PreferenceUtil.KEY_ANIMATION_ENABLED, true);
      AppStorage.setOrCreate('isAnimationEnabled', enabled);
      return enabled as boolean;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load animation enabled: ${err}`);
      return true; // Default to true on error
    }
  }

  async saveAnimationDuration(duration: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put('animation_duration', duration);
      await this.pref.flush();
      AppStorage.setOrCreate('animationDuration', duration);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save animation duration: ${err}`);
    }
  }

  async loadAnimationDuration(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 400;
    try {
      const duration = await this.pref.get('animation_duration', 400);
      AppStorage.setOrCreate('animationDuration', duration);
      return duration as number;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load animation duration: ${err}`);
      return 400;
    }
  }

  async saveAnimationDamping(damping: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_ANIMATION_DAMPING, damping);
      await this.pref.flush();
      AppStorage.setOrCreate('animationDamping', damping);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save animation damping: ${err}`);
    }
  }

  async loadAnimationDamping(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 0.8;
    try {
      const damping = await this.pref.get(PreferenceUtil.KEY_ANIMATION_DAMPING, 0.5);
      AppStorage.setOrCreate('animationDamping', damping);
      return damping as number;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load animation damping: ${err}`);
      return 0.8;
    }
  }

  async saveAnimationResponse(response: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_ANIMATION_RESPONSE, response);
      await this.pref.flush();
      AppStorage.setOrCreate('animationResponse', response);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save animation response: ${err}`);
    }
  }

  async loadAnimationResponse(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 0.4;
    try {
      const response = await this.pref.get(PreferenceUtil.KEY_ANIMATION_RESPONSE, 0.5);
      AppStorage.setOrCreate('animationResponse', response);
      return response as number;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load animation response: ${err}`);
      return 0.4;
    }
  }

  async saveAnimationPresetMode(mode: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_ANIMATION_PRESET_MODE, mode);
      await this.pref.flush();
      AppStorage.setOrCreate('animationPresetMode', mode);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save animation preset mode: ${err}`);
    }
  }

  async loadAnimationPresetMode(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 0;
    try {
      const mode = await this.pref.get(PreferenceUtil.KEY_ANIMATION_PRESET_MODE, 0);
      AppStorage.setOrCreate('animationPresetMode', mode);
      return mode as number;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load animation preset mode: ${err}`);
      return 0;
    }
  }

  async savePointLightEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_POINT_LIGHT_ENABLED, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('isPointLightEnabled', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save point light enabled: ${err}`);
    }
  }

  async loadPointLightEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return true; // Default to true
    try {
      const enabled = await this.pref.get(PreferenceUtil.KEY_POINT_LIGHT_ENABLED, true);
      AppStorage.setOrCreate('isPointLightEnabled', enabled);
      return enabled as boolean;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load point light enabled: ${err}`);
      return true;
    }
  }

  async saveSplitViewEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_SPLIT_VIEW_ENABLED, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('isSplitViewEnabled', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save split view enabled: ${err}`);
    }
  }

  async loadSplitViewEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return false; // Default to false (Match UI default)
    try {
      const enabled = await this.pref.get(PreferenceUtil.KEY_SPLIT_VIEW_ENABLED, false); // Default to false
      AppStorage.setOrCreate('isSplitViewEnabled', enabled);
      return enabled as boolean;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load split view enabled: ${err}`);
      return false;
    }
  }

  /**
   * Synchronous load for Ability Initialization (Critical for launch animation)
   */
  loadSplitViewEnabledSync(context: common.Context): boolean {
    try {
        const pref = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
        const enabled = pref.getSync(PreferenceUtil.KEY_SPLIT_VIEW_ENABLED, false) as boolean; // Default false
        AppStorage.setOrCreate('isSplitViewEnabled', enabled);
        hilog.info(DOMAIN, TAG, `loadSplitViewEnabledSync: ${enabled}`);
        return enabled;
    } catch (e) {
        hilog.error(DOMAIN, TAG, `loadSplitViewEnabledSync failed: ${JSON.stringify(e)}`);
        return false;
    }
  }

  /**
   * Synchronous load for App Lock settings (Critical for launch animation)
   */
  loadAppLockSettingsSync(context: common.Context): void {
    try {
        const pref = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
        
        // 1. Password Status
        const password = pref.getSync(PreferenceUtil.KEY_APP_LOCK_PASSWORD, '') as string;
        AppStorage.setOrCreate('hasAppLock', !!password);
        
        // 2. Face Status
        const face = pref.getSync(PreferenceUtil.KEY_APP_LOCK_FACE, false) as boolean;
        AppStorage.setOrCreate('appLockFace', face);
        
        // 3. Fingerprint Status
        const fingerprint = pref.getSync(PreferenceUtil.KEY_APP_LOCK_FINGERPRINT, false) as boolean;
        AppStorage.setOrCreate('appLockFingerprint', fingerprint);

        // 4. Password Length
        const length = pref.getSync(PreferenceUtil.KEY_APP_LOCK_PASSWORD_LENGTH, 4) as number;
        AppStorage.setOrCreate('appLockPasswordLength', length);
        
        hilog.info(DOMAIN, TAG, `loadAppLockSettingsSync: hasAppLock=${!!password}, face=${face}, fingerprint=${fingerprint}, length=${length}`);
    } catch (e) {
        hilog.error(DOMAIN, TAG, `loadAppLockSettingsSync failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * Synchronous load for Animation settings (Critical for launch animation)
   */
  loadAnimationSettingsSync(context: common.Context): void {
    try {
        const pref = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
        
        // 1. Animation Toggle
        const enabled = pref.getSync(PreferenceUtil.KEY_ANIMATION_ENABLED, true) as boolean;
        AppStorage.setOrCreate('isAnimationEnabled', enabled);
        
        // 2. Duration
        const duration = pref.getSync(PreferenceUtil.KEY_ANIMATION_DURATION, 400) as number;
        AppStorage.setOrCreate('animationDuration', duration);
        
        // 3. Damping
        const damping = pref.getSync(PreferenceUtil.KEY_ANIMATION_DAMPING, 0.5) as number;
        AppStorage.setOrCreate('animationDamping', damping);
        
        // 4. Response
        const response = pref.getSync(PreferenceUtil.KEY_ANIMATION_RESPONSE, 0.6) as number;
        AppStorage.setOrCreate('animationResponse', response);
        
        // 5. Preset Mode
        const mode = pref.getSync(PreferenceUtil.KEY_ANIMATION_PRESET_MODE, 0) as number;
        AppStorage.setOrCreate('animationPresetMode', mode);

        // 6. Point Light
        const light = pref.getSync(PreferenceUtil.KEY_POINT_LIGHT_ENABLED, true) as boolean;
        AppStorage.setOrCreate('isPointLightEnabled', light);
        
        hilog.info(DOMAIN, TAG, `loadAnimationSettingsSync: enabled=${enabled}, duration=${duration}, damping=${damping}, response=${response}, mode=${mode}`);
    } catch (e) {
        hilog.error(DOMAIN, TAG, `loadAnimationSettingsSync failed: ${JSON.stringify(e)}`);
    }
  }

  public async isAIEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return true; // Default to enabled
    try {
      const val = await this.pref.get(PreferenceUtil.KEY_AI_ENABLED, true);
      return val as boolean;
    } catch (err) {
      return true;
    }
  }

  public async saveAIEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_AI_ENABLED, enabled);
      await this.pref.flush();
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save AI enabled: ${err}`);
    }
  }

  // 新年水印开关
  private static readonly KEY_NEW_YEAR_WATERMARK_ENABLED = 'new_year_watermark_enabled';

  public async loadNewYearWatermarkEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return true; // Default to true
    try {
      const val = await this.pref.get(PreferenceUtil.KEY_NEW_YEAR_WATERMARK_ENABLED, true);
      AppStorage.setOrCreate('isNewYearWatermarkEnabled', val);
      return val as boolean;
    } catch (err) {
      return true;
    }
  }

  public async saveNewYearWatermarkEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_NEW_YEAR_WATERMARK_ENABLED, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('isNewYearWatermarkEnabled', enabled);
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save new year watermark enabled: ${err}`);
    }
  }

  public async saveSearchDebounceEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put('search_debounce_enabled', enabled);
      await this.pref.flush();
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save search debounce enabled: ${err}`);
    }
  }

  // Background Watermark Image
  private static readonly KEY_WATERMARK_IMAGE = 'watermark_image_uri';
  private static readonly KEY_WATERMARK_OPACITY = 'watermark_opacity';

  public async loadWatermarkImage(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return '';
    try {
      const uri = await this.pref.get(PreferenceUtil.KEY_WATERMARK_IMAGE, '');
      AppStorage.setOrCreate('watermarkImage', uri);
      return uri as string;
    } catch (err) {
      return '';
    }
  }

  public async saveWatermarkImage(uri: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_WATERMARK_IMAGE, uri);
      await this.pref.flush();
      AppStorage.setOrCreate('watermarkImage', uri);
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save watermark image: ${err}`);
    }
  }

  public async loadWatermarkOpacity(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 0.2; // Default opacity
    try {
      const val = await this.pref.get(PreferenceUtil.KEY_WATERMARK_OPACITY, 0.2);
      AppStorage.setOrCreate('watermarkOpacity', val);
      return val as number;
    } catch (err) {
      return 0.2;
    }
  }

  public async saveWatermarkOpacity(opacity: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_WATERMARK_OPACITY, opacity);
      await this.pref.flush();
      AppStorage.setOrCreate('watermarkOpacity', opacity);
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save watermark opacity: ${err}`);
    }
  }

  // VIP Theme Toggle

  // Watermark Offset
  private static readonly KEY_WATERMARK_OFFSET_X = 'watermark_offset_x';
  private static readonly KEY_WATERMARK_OFFSET_Y = 'watermark_offset_y';

  public async loadWatermarkOffset(): Promise<WatermarkOffset> {
    await this.ensureInitialized();
    if (!this.pref) return new WatermarkOffset();
    try {
      const x = await this.pref.get(PreferenceUtil.KEY_WATERMARK_OFFSET_X, 0);
      const y = await this.pref.get(PreferenceUtil.KEY_WATERMARK_OFFSET_Y, 0);
      AppStorage.setOrCreate('watermarkOffsetX', x);
      AppStorage.setOrCreate('watermarkOffsetY', y);
      const offset = new WatermarkOffset();
      offset.x = x as number;
      offset.y = y as number;
      return offset;
    } catch (err) {
      return new WatermarkOffset();
    }
  }

  public async saveWatermarkOffset(x: number, y: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_WATERMARK_OFFSET_X, x);
      await this.pref.put(PreferenceUtil.KEY_WATERMARK_OFFSET_Y, y);
      await this.pref.flush();
      AppStorage.setOrCreate('watermarkOffsetX', x);
      AppStorage.setOrCreate('watermarkOffsetY', y);
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save watermark offset: ${err}`);
    }
  }

  public async getNewYearReminderDisabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return false;
    try {
      const val = await this.pref.get(PreferenceUtil.KEY_NEW_YEAR_REMINDER_DISABLED, false);
      return val as boolean;
    } catch (err) {
      return false;
    }
  }

  public async saveNewYearReminderDisabled(disabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_NEW_YEAR_REMINDER_DISABLED, disabled);
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, `New year reminder disabled status saved: ${disabled}`);
    } catch (err) {
       hilog.error(DOMAIN, TAG, `Failed to save new year reminder disabled status: ${err}`);
    }
  }

  public async loadTextWatermarkEnabled(): Promise<boolean> {
     await this.ensureInitialized();
     if (!this.pref) return true;
     try {
       const val = await this.pref.get(PreferenceUtil.KEY_TEXT_WATERMARK_ENABLED, true);
       AppStorage.setOrCreate('isTextWatermarkEnabled', val);
       return val as boolean;
     } catch (err) {
       return true;
     }
  }
 
   public async saveTextWatermarkEnabled(enabled: boolean) {
     await this.ensureInitialized();
     if (!this.pref) return;
     try {
       await this.pref.put(PreferenceUtil.KEY_TEXT_WATERMARK_ENABLED, enabled);
       await this.pref.flush();
       AppStorage.setOrCreate('isTextWatermarkEnabled', enabled);
     } catch (err) {
        hilog.error(DOMAIN, TAG, `Failed to save text watermark enabled: ${err}`);
     }
  }
 
   public async loadWatermarkTextContent(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return '记得订阅';
    try {
      const text = await this.pref.get(PreferenceUtil.KEY_WATERMARK_TEXT, '记得订阅');
      AppStorage.setOrCreate('watermarkText', text);
      return text as string;
    } catch (err) {
      return '记得订阅';
    }
  }
 
   public async saveWatermarkTextContent(text: string) {
     await this.ensureInitialized();
     if (!this.pref) return;
     try {
       await this.pref.put(PreferenceUtil.KEY_WATERMARK_TEXT, text);
       await this.pref.flush();
       AppStorage.setOrCreate('watermarkText', text);
     } catch (err) {
        hilog.error(DOMAIN, TAG, `Failed to save watermark text content: ${err}`);
     }
   }
 
   async saveThemeId(id: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_THEME_ID, id);
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, `saveThemeId: Successfully saved themeId=${id}`);
      
      // Update global state
      AppStorage.setOrCreate('activeThemeId', id);
      AppStorage.setOrCreate('showVipTheme', id === 'vip');
      AppStorage.setOrCreate('isNewYearTheme', id === 'new_year');
      
      // Notify widgets
      this.updateAllWidgets();
      
      // Notify repository to update snapshot
      const GlobalBus = await import('./GlobalBus');
      GlobalBus.GlobalBus.publish(GlobalBus.EVENT_THEME_CHANGED);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save theme id: ${err}`);
    }
  }

  async loadThemeId(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return 'default';
    try {
      let id = await this.pref.get(PreferenceUtil.KEY_THEME_ID, '') as string;
      
      // Migration from legacy boolean
      if (!id) {
          const isVip = await this.pref.get(PreferenceUtil.KEY_SHOW_VIP_THEME, false) as boolean;
          id = isVip ? 'vip' : 'default';
          // Save migration
          await this.saveThemeId(id);
      }

      AppStorage.setOrCreate('activeThemeId', id);
      AppStorage.setOrCreate('showVipTheme', id === 'vip');
      AppStorage.setOrCreate('isNewYearTheme', id === 'new_year');
      
      return id;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load theme id: ${err}`);
      return 'default';
    }
  }

  /**
   * Synchronous load for Ability Initialization
   */
  loadThemeIdSync(context: common.Context): string {
    try {
        const pref = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
        let id = pref.getSync(PreferenceUtil.KEY_THEME_ID, '') as string;
        
        // Migration logic - sync version
        if (!id) {
             const isVip = pref.getSync(PreferenceUtil.KEY_SHOW_VIP_THEME, false) as boolean;
             id = isVip ? 'vip' : 'default';
        }

        AppStorage.setOrCreate('activeThemeId', id);
        AppStorage.setOrCreate('showVipTheme', id === 'vip');
        AppStorage.setOrCreate('isNewYearTheme', id === 'new_year');
        
        hilog.info(DOMAIN, TAG, `loadThemeIdSync: ${id}`);
        return id;
    } catch (e) {
        hilog.error(DOMAIN, TAG, `loadThemeIdSync failed: ${JSON.stringify(e)}`);
        return 'default';
    }
  }

  /**
   * Synchronous version for FormExtensionBenefit or immediate use
   */
  getThemeIdSync(context: common.Context): string {
    try {
        const pref = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
        return pref.getSync(PreferenceUtil.KEY_THEME_ID, 'default') as string;
    } catch (e) {
        return 'default';
    }
  }

  // Deprecated: Use saveThemeId
  async saveShowVipTheme(enabled: boolean) {
     const id = enabled ? 'vip' : 'default';
     await this.saveThemeId(id);
  }

  public getThemeId(): string {
    // Try AppStorage first (UI process optimization)
    const id = AppStorage.get<string>('activeThemeId');
    if (id) return id;
    
    // Fallback to synchronous pref read if available (for Form/Ability context)
    if (this.context) {
        return this.getThemeIdSync(this.context);
    }
    
    return 'default';
  }

  private async updateAllWidgets() {
    hilog.info(DOMAIN, TAG, 'updateAllWidgets: Triggering manual widget updates...');
    try {
        // Use the official way to get running forms if possible, or fallback to saved IDs
        let formIds: string[] = [];
        try {
            const runningForms = await formProvider.getPublishedRunningFormInfos();
            formIds = runningForms.map((info: formInfo.RunningFormInfo) => info.formId);
            hilog.info(DOMAIN, TAG, `updateAllWidgets: Found ${formIds.length} running forms`);
        } catch (e) {
            hilog.warn(DOMAIN, TAG, 'updateAllWidgets: Failed to get running forms, falling back to preference list');
            formIds = await this.getFormIds();
        }

        const themeId = this.getThemeId();
        
        if (formIds.length > 0) {
            // Encode data as a valid binding object
            const bindingData = formBindingData.createFormBindingData({ 
                'activeThemeId': themeId 
            });
            
            for (const id of formIds) {
                if (id && id.trim() !== '') {
                    try {
                        await formProvider.updateForm(id, bindingData); 
                        hilog.info(DOMAIN, TAG, `updateAllWidgets: Successfully pushed theme update to form ${id}`);
                    } catch (err) {
                        const error = err as BusinessError;
                        hilog.error(DOMAIN, TAG, `updateAllWidgets: Failed to update form ${id}. error: ${error.code} ${error.message}`);
                        // If ID does not exist, prune it from our list if we are using the fallback list
                        if (error.code === 16501001 || (error.message && error.message.includes('not exist'))) {
                            this.removeFormId(id);
                        }
                    }
                }
            }
        }
    } catch (e) {
        const error = e as BusinessError;
        hilog.error(DOMAIN, TAG, `updateAllWidgets failed. code: ${error.code}, message: ${error.message}`);
    }
  }

  // Deprecated: Use loadThemeId
  async loadShowVipTheme(): Promise<boolean> {
     const id = await this.loadThemeId();
     return id === 'vip';
  }

  // =========================================
  // 会员系统相关方法
  // =========================================
  
  /**
   * 保存黑金主题状态 (原会员信息保存)
   * 简化为只保存 isVip 状态，忽略过期时间
   */
  public async saveMembership(level: string, expiry: number, isVip: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      // 纯本地开关，不再校验过期
      await this.pref.put('membership_level', level); // 保留字段兼容
      await this.pref.put('membership_expiry', expiry);
      await this.pref.put('is_vip', isVip);
      await this.pref.flush();
      
      // 同步到 AppStorage
      AppStorage.setOrCreate('membershipLevel', level);
      AppStorage.setOrCreate('membershipExpiry', expiry);
      AppStorage.setOrCreate('isVip', isVip);
      
      hilog.info(DOMAIN, TAG, `Theme setting saved: isBlackGold=${isVip}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save theme setting: ${err}`);
    }
  }

  /**
   * 加载黑金主题状态
   */
  public async loadMembership(): Promise<MembershipData> {
    await this.ensureInitialized();
    const defaultResult: MembershipData = { level: 'free', expiry: 0, isVip: false };
    if (!this.pref) return defaultResult;
    
    try {
      const level = await this.pref.get('membership_level', 'free') as string;
      const expiry = await this.pref.get('membership_expiry', 0) as number;
      const isVip = await this.pref.get('is_vip', false) as boolean;
      
      // 同步到 AppStorage
      AppStorage.setOrCreate('membershipLevel', level);
      AppStorage.setOrCreate('membershipExpiry', expiry);
      AppStorage.setOrCreate('isVip', isVip);
      
      hilog.info(DOMAIN, TAG, `Theme setting loaded: isBlackGold=${isVip}`);
      const result: MembershipData = { level: level, expiry: expiry, isVip: isVip };
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load theme setting: ${err}`);
      return defaultResult;
    }
  }

  /**
   * 清除会员信息（登出时调用）
   */
  public async clearMembership() {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put('membership_level', 'free');
      await this.pref.put('membership_expiry', 0);
      await this.pref.flush();
      
      AppStorage.setOrCreate('membershipLevel', 'free');
      AppStorage.setOrCreate('membershipExpiry', 0);
      
      hilog.info(DOMAIN, TAG, 'Membership cleared');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to clear membership: ${err}`);
    }
  }

  /**
   * 检查当前会员是否有效
   */
  public async isVipValid(): Promise<boolean> {
    const membership = await this.loadMembership();
    if (membership.level === 'lifetime') return true;
    if (membership.level === 'pro' && membership.expiry > 0) {
      return membership.expiry > Date.now();
    }
    return false;
  }

  // =========================================
  // 本地通知映射 (SubID -> ReminderID)
  // =========================================

  public async saveReminderId(subId: number, reminderId: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(`reminder_map_${subId}`, reminderId);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save reminder map: ${err}`);
    }
  }

  public async getReminderId(subId: number): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return -1;
    try {
      const id = await this.pref.get(`reminder_map_${subId}`, -1);
      return id as number;
    } catch (err) {
      return -1;
    }
  }

  public async saveSortOrder(order: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_SORT_ORDER, order);
      await this.pref.flush();
      hilog.info(DOMAIN, TAG, `Sort order saved: ${order}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save sort order: ${err}`);
    }
  }

  public async loadSortOrder(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return 'date_asc';
    try {
      const order = await this.pref.get(PreferenceUtil.KEY_SORT_ORDER, 'date_asc');
      hilog.info(DOMAIN, TAG, `Sort order loaded: ${order}`);
      return order as string;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to load sort order: ${err}`);
      return 'date_asc';
    }
  }

  public async removeReminderId(subId: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.delete(`reminder_map_${subId}`);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to remove reminder map: ${err}`);
    }
  }
  public async loadSmartGestureEnabled(): Promise<boolean> {
    await this.ensureInitialized();
    if (!this.pref) return false; // Default to false
    try {
      const val = await this.pref.get(PreferenceUtil.KEY_SMART_GESTURE_ENABLED, false);
      AppStorage.setOrCreate('isSmartGestureEnabled', val);
      return val as boolean;
    } catch (err) {
      return false;
    }
  }

  public async saveSmartGestureEnabled(enabled: boolean) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_SMART_GESTURE_ENABLED, enabled);
      await this.pref.flush();
      AppStorage.setOrCreate('isSmartGestureEnabled', enabled);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save smart gesture enabled: ${err}`);
    }
  }

  public async saveLastKnownVersion(version: string) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_LAST_KNOWN_VERSION, version);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save last known version: ${err}`);
    }
  }

  public async getLastKnownVersion(): Promise<string> {
    await this.ensureInitialized();
    if (!this.pref) return '';
    try {
      const version = await this.pref.get(PreferenceUtil.KEY_LAST_KNOWN_VERSION, '');
      return version as string;
    } catch (err) {
      return '';
    }
  }

  public async saveLastAgreementVersion(version: number) {
    await this.ensureInitialized();
    if (!this.pref) return;
    try {
      await this.pref.put(PreferenceUtil.KEY_LAST_AGREEMENT_VERSION, version);
      await this.pref.flush();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to save agreement version: ${err}`);
    }
  }

  public async getLastAgreementVersion(): Promise<number> {
    await this.ensureInitialized();
    if (!this.pref) return 0;
    try {
      const version = await this.pref.get(PreferenceUtil.KEY_LAST_AGREEMENT_VERSION, 0);
      return version as number;
    } catch (err) {
      return 0;
    }
  }
}
