import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction } from '@kit.ArkUI';
import { PreferenceUtil } from './PreferenceUtil';
import { GlobalBus, EVENT_LOGIN } from './GlobalBus';

const TAG = 'HuaweiAuthManager';
const DOMAIN = 0x0000;

export interface HuaweiAuthResult {
  authorizationCode: string;
  unionID?: string;
  nickName?: string;
  avatarUri?: string;
}

export class HuaweiAuthManager {
  private static instance: HuaweiAuthManager;
  private uiAbilityContext: Context | null = null;

  private constructor() {}
  
  /**
   * 设置 UIAbility Context（应在 EntryAbility 中调用）
   */
  public setContext(context: Context): void {
    this.uiAbilityContext = context;
  }
  
  /**
   * 获取有效的 UIAbility Context
   */
  public getContext(): Context | null {
    return this.uiAbilityContext;
  }

  public static getInstance(): HuaweiAuthManager {
    if (!HuaweiAuthManager.instance) {
      HuaweiAuthManager.instance = new HuaweiAuthManager();
    }
    return HuaweiAuthManager.instance;
  }

  /**
   * 执行华为 ID 登录流程（纯本地模式）
   * @param silent 是否静默登录（若为 true，则尝试不拉起授权页）
   */
  public async login(silent: boolean = false): Promise<void> {
    try {
      // 1. Create Huawei ID Provider
      const huaweiIdProvider = new authentication.HuaweiIDProvider();
      
      // 2. Create Login Request
      // Request 'profile' and 'openid' scopes to get user info and unionID
      const request = huaweiIdProvider.createAuthorizationWithHuaweiIDRequest();
      request.scopes = ['profile', 'openid'];
      request.forceAuthorization = !silent;

      // 3. Execute Request - 必须传入有效的 UIAbility context
      if (!this.uiAbilityContext) {
        throw new Error('UIAbility context not initialized. Please call setContext() first.');
      }
      const controller = new authentication.AuthenticationController(this.uiAbilityContext);
      
      hilog.info(DOMAIN, TAG, silent ? 'Attempting silent login...' : 'Attempting interactive login...');
      
      const response: authentication.AuthenticationResponse = await controller.executeRequest(request);

      hilog.info(DOMAIN, TAG, 'Huawei Auth Response: ' + JSON.stringify(response));

      // 4. Handle Response
      const responseAny = response as Object as Record<string, Object>;
      const authResult = (responseAny.data ? responseAny.data : responseAny) as HuaweiAuthResult;

      const unionId = authResult.unionID;
      const nickname = authResult.nickName;
      const avatar = authResult.avatarUri;

      hilog.info(DOMAIN, TAG, `UnionID: ${unionId}, Nickname: ${nickname}`);

      // 自动登录账号一致性检查
      if (silent && unionId) {
          const oldUnionId = AppStorage.get<string>('unionId');
          if (oldUnionId && oldUnionId !== unionId) {
              hilog.warn(DOMAIN, TAG, `UnionID mismatch. Old: ${oldUnionId}, New: ${unionId}. Triggering logout.`);
              throw new Error("System account changed");
          }
      }

      if (unionId) {
        // 本地保存用户信息
        const finalName = nickname || '华为用户';
        const finalAvatar = avatar || '';

        // Update AppStorage
        AppStorage.setOrCreate('isLoggedIn', true);
        AppStorage.setOrCreate('unionId', unionId);
        AppStorage.setOrCreate('userName', finalName);
        AppStorage.setOrCreate('userAvatar', finalAvatar);
        
        hilog.info(DOMAIN, TAG, `Local login success for ID: ${unionId}`);

        // Persist Session
        await PreferenceUtil.getInstance().saveSession(true, unionId, finalName, finalAvatar);
        
        // Notify Widget Update
        GlobalBus.publish(EVENT_LOGIN);
        
        // 登录成功提示
        if (!silent) {
            promptAction.showToast({ message: `${finalName}，欢迎回来` });
        }
      } else {
        throw new Error('未获取到华为账号信息');
      }

    } catch (error) {
       const err = error as BusinessError;
       hilog.error(DOMAIN, TAG, `Login failed. Code: ${err.code}, Message: ${err.message}`);
       
       // 仅在非静默模式时提示
       if (!silent) {
          promptAction.showToast({ message: '登录失败，请重试' });
       }
       
       // 重新抛出异常，让调用方可以处理
       throw new Error(`Login failed: ${err.code} - ${err.message}`);
    }
  }
}
