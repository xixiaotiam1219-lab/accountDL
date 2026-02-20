import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { authentication } from '@kit.AccountKit';
import { PreferenceUtil } from './PreferenceUtil';
import { HuaweiAuthManager } from './HuaweiAuthManager';
import { GlobalBus, EVENT_LOGOUT } from './GlobalBus';

const TAG = 'AccountMonitor';
const DOMAIN = 0x0000;

export class AccountMonitor {
  private static instance: AccountMonitor;
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  private constructor() {}

  public static getInstance(): AccountMonitor {
    if (!AccountMonitor.instance) {
      AccountMonitor.instance = new AccountMonitor();
    }
    return AccountMonitor.instance;
  }

  public startMonitoring(): void {
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [
        commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGIN,
        commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGOUT
      ]
    };

    commonEventManager.createSubscriber(subscribeInfo)
      .then((commonEventSubscriber: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = commonEventSubscriber;
        commonEventManager.subscribe(this.subscriber, (error: BusinessError, data: commonEventManager.CommonEventData) => {
          if (error) {
            hilog.error(DOMAIN, TAG, `Failed to subscribe, code is ${error.code}, message is ${error.message}`);
            return;
          }

          if (data.event === commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGIN) {
            hilog.info(DOMAIN, TAG, 'System Account Logged In');
            // 可选：提示用户进行 App 内授权，或尝试静默登录
          } else if (data.event === commonEventManager.Support.COMMON_EVENT_DISTRIBUTED_ACCOUNT_LOGOUT) {
            hilog.info(DOMAIN, TAG, 'System Account Logged Out');
            // 系统账号退出，App 应该随之彻底清理
            hilog.warn(DOMAIN, TAG, 'Warning: System Logout Event received. Auto-logout is temporarily disabled for debugging.');
            // this.handleLogout(); // DISABLED FOR DEBUGGING
          }
        });
        hilog.info(DOMAIN, TAG, 'Account monitoring started');
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, `Failed to createSubscriber. Code: ${err.code}, message: ${err.message}`);
      });
  }

  public stopMonitoring(): void {
    if (this.subscriber) {
      commonEventManager.unsubscribe(this.subscriber, (err) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `Unsubscribe failed. Code: ${err.code}, message: ${err.message}`);
        } else {
          hilog.info(DOMAIN, TAG, 'Account monitoring stopped');
          this.subscriber = null;
        }
      });
    }
  }

  public async handleLogout() {
    hilog.info(DOMAIN, TAG, 'Triggering App Logout and clearing persistent session');
    


    // 强制清理 AppStorage
    AppStorage.setOrCreate('isLoggedIn', false);
    AppStorage.setOrCreate('unionId', '');
    AppStorage.setOrCreate('userName', '立即登录');
    AppStorage.setOrCreate('userAvatar', '');
    
    // 清理会员状态 (保留黑金主题设置)
    AppStorage.setOrCreate('membershipLevel', 'free');
    AppStorage.setOrCreate('membershipExpiry', 0);
    // AppStorage.setOrCreate('isVip', false); // Keep theme setting

    // 【关键】强制清除持久化的会话信息，不依赖当前 AppStorage 状态
    await PreferenceUtil.getInstance().clearSession();
    await PreferenceUtil.getInstance().clearMembership();

    // 清除应用锁设置 (用户退出登录时同步清空应用锁)
    await PreferenceUtil.getInstance().saveAppLockPassword('');
    await PreferenceUtil.getInstance().saveAppLockFace(false);
    await PreferenceUtil.getInstance().saveAppLockFingerprint(false);
    AppStorage.setOrCreate('hasAppLock', false);
    
    // 1. 在清理数据库前，先获取所有订阅并取消系统提醒
    try {
      const subs = await SubscriptionRepository.getInstance().queryAll();
      const notificationManagerModule = await import('../manager/LocalNotificationManager');
      const LocalNotificationManager = notificationManagerModule.LocalNotificationManager;
      await LocalNotificationManager.getInstance().cancelAllReminders(subs);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Failed to cancel reminders during logout: ${JSON.stringify(e)}`);
    }

    // 2. 清理本地数据库并广播登出事件
    SubscriptionRepository.getInstance().clearAllData().then(() => {
       hilog.info(DOMAIN, TAG, 'Local data cleared and broadcasting EVENT_LOGOUT');
       GlobalBus.publish(EVENT_LOGOUT);
    });
  }
  
  /**
   * 应用启动时校验华为账号状态
   * 直接尝试静默登录，如果失败说明系统华为账号已退出，则自动执行退出操作
   * @param context UIAbility 的 context（需先通过 HuaweiAuthManager.setContext 设置）
   */
  public async checkAccountStatusOnLaunch(): Promise<void> {
    const appIsLoggedIn = AppStorage.get<boolean>('isLoggedIn');
    
    // 如果应用内未登录，无需校验
    if (!appIsLoggedIn) {
      hilog.info(DOMAIN, TAG, 'App not logged in, skip account status check');
      return;
    }
    
    hilog.info(DOMAIN, TAG, 'Checking system Huawei account status on launch (silent login)...');
    
    try {
      // 直接调用静默登录，如果成功说明华为账号仍然有效
      await HuaweiAuthManager.getInstance().login(true);
      hilog.info(DOMAIN, TAG, 'Silent login successful, Huawei account still valid');
      
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(DOMAIN, TAG, `Silent login failed. Code: ${err.code}, Message: ${err.message}`);
      
      // 过滤网络错误 (例如 12300003)，避免因无网络误退出
      // 同时也过滤没有 code 的通用错误 (可能是 loginToBackend 抛出的网络/服务器异常)
      if (err.code === 12300003 || !err.code) {
         hilog.warn(DOMAIN, TAG, 'Silent login failed due to network/server issue (or generic error). Skipping auto-logout.');
         return;
      }

      // 静默登录失败，且有明确的错误码（非网络错误），说明系统华为账号已退出或授权已失效
      // 常见的授权失效码：
      // 1001502001: 账号未登录
      // 1001502002: 服务未授权
      // 1001502009: 换取 Token 失败 (可能也是网络问题，暂时先不自动退，安全起见)
      
      // 保守策略：只有明确是 "未登录" 相关的错误才自动退出
      // 如果不确定，宁可不退，让用户下次点击登录时再处理
      const AUTH_INVALID_CODES = [
          1001502001, // ACCOUNT_NOT_LOGIN
          1001502002, // APP_NOT_AUTHORIZED
      ];
      
      if (AUTH_INVALID_CODES.includes(err.code)) {
          hilog.warn(DOMAIN, TAG, 'System Huawei account logged out or authorization revoked. Triggering app logout.');
          this.handleLogout();
      } else {
          hilog.warn(DOMAIN, TAG, `Silent login failed with code ${err.code}. Conservatively skipping auto-logout.`);
      }
    }
  }
}

