import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration, common } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display, promptAction } from '@kit.ArkUI';
import { FloatingBallManager } from '../utils/FloatingBallManager';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { OCRManager } from '../utils/OCRManager';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NetworkMonitor } from '../utils/NetworkMonitor';
import { AccountMonitor } from '../utils/AccountMonitor';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { HuaweiAuthManager } from '../utils/HuaweiAuthManager';
import { UpdateManager } from '../utils/UpdateManager';
import { formBindingData, formProvider, formInfo } from '@kit.FormKit';
import { GlobalBus, EVENT_SYNC_COMPLETED, EVENT_LOGOUT, EVENT_LOGIN, EVENT_NOTIFY_PERMISSION_GRANTED } from '../utils/GlobalBus';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util, url } from '@kit.ArkTS';
import { WARRANTY_ICON_MAP_NAMES, WARRANTY_THEME_MAP, getWarrantyThemeColors } from '../utils/WarrantyConstants';
import { LocalIconManager } from '../utils/LocalIconManager';
import { LocalNotificationManager } from '../manager/LocalNotificationManager';

const DOMAIN = 0x0000;
export default class EntryAbility extends UIAbility {
  private commonSubscribers: commonEventManager.CommonEventSubscriber[] = [];
  private pendingImportWant: Want | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0xFEED, 'EntryAbility', 'Ability onCreate called');
    if (want && want.parameters) {
      hilog.info(0xFEED, 'EntryAbility', `onCreate Want parameters: ${JSON.stringify(want.parameters)}`);
    }
    this.pendingImportWant = want;
    this.handleRouterEvent(want);

    // Initialize Navigation Stack globally
    AppStorage.setOrCreate('pageStack', new NavPathStack());
    AppStorage.setOrCreate('tabBarVisible', true); // 默认显示
    AppStorage.setOrCreate('currentIndex', 0); // 默认首页

    // Initialize PreferenceUtil and Load Session
    PreferenceUtil.getInstance().loadPreference(this.context).then(() => {
      PreferenceUtil.getInstance().loadSession().then((session) => {
        const isLoggedIn = session['isLoggedIn'] as boolean;
        const unionId = session['unionId'] as string;
        const userName = session['userName'] as string;
        const userAvatar = session['userAvatar'] as string;

        hilog.info(DOMAIN, 'testTag', `Restoring session: LoggedIn=${isLoggedIn}`);

        AppStorage.setOrCreate('isLoggedIn', isLoggedIn);
        AppStorage.setOrCreate('unionId', unionId);
        AppStorage.setOrCreate('userName', userName || '立即登录');
        AppStorage.setOrCreate('userAvatar', userAvatar);

        // 如果已登录，先校验华为账号状态，再触发同步
        if (isLoggedIn) {
          hilog.info(DOMAIN, 'testTag', 'User logged in, checking account status and triggering auto-sync on launch');

          PreferenceUtil.getInstance().get('lastLoginTime', 0).then((time: Object) => {
            hilog.info(DOMAIN, 'testTag', `User logged in, last login: ${time as number}`);
          });

          // 校验系统华为账号状态
          AccountMonitor.getInstance().checkAccountStatusOnLaunch().then(() => {
            // 尝试静默登录以刷新 Session 和 Token
            HuaweiAuthManager.getInstance().login(true).then(() => {
              SubscriptionRepository.getInstance().syncWithCloud();
            }).catch((err: BusinessError) => {
              // 仅记录日志，不打扰用户
              hilog.warn(DOMAIN, 'testTag', `Silent login failed on launch: ${err.message}`);
            });
          });
        }

        // 无论是否登录，都尝试刷新一次卡片（推迟执行，不阻塞启动）
        setTimeout(() => {
           this.updateAllWidgets();
        }, 4000);
      });

      // 提前加载主题配置，确保 Index 页面首次渲染时 showVipTheme/isNewYearTheme 已有正确值
      PreferenceUtil.getInstance().loadThemeId();
    });

    // Initialize Repository (Standard Init for other uses)
    SubscriptionRepository.getInstance().init(this.context);

    // Starters - Immediate but non-blocking
    NetworkMonitor.getInstance().startMonitoring();
    AccountMonitor.getInstance().startMonitoring();

    // 延迟初始化非核心组件 (启动 1.5s 后)
    setTimeout(() => {
      // Initialize OCRManager
      OCRManager.getInstance().setContext(this.context);

      // Initialize HuaweiAuthManager
      HuaweiAuthManager.getInstance().setContext(this.context);

      // Initialize LocalIconManager
      LocalIconManager.getInstance().init(this.context);
    }, 1500);

    // Load and Apply Theme & Preferences
    PreferenceUtil.getInstance().loadPreference(this.context).then(() => {
      // 仅加载首屏渲染核心配置
      PreferenceUtil.getInstance().loadThemeId();
      PreferenceUtil.getInstance().loadSession().then((session) => {
        const isLoggedIn = session['isLoggedIn'] as boolean;
        AppStorage.setOrCreate('isLoggedIn', isLoggedIn);
        AppStorage.setOrCreate('unionId', session['unionId'] as string);
        AppStorage.setOrCreate('userName', (session['userName'] as string) || '立即登录');
        AppStorage.setOrCreate('userAvatar', session['userAvatar'] as string);
      });

      // 异步加载次要偏好设置
      PreferenceUtil.getInstance().loadTheme().then((mode) => {
        let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
        if (mode === 1) colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
        else if (mode === 2) colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        this.context.getApplicationContext().setColorMode(colorMode);
        AppStorage.setOrCreate('currentColorMode', colorMode);
      });
      
      PreferenceUtil.getInstance().loadAnimationEnabled();
      PreferenceUtil.getInstance().loadSplitViewEnabled();
      PreferenceUtil.getInstance().loadSmartGestureEnabled();
      PreferenceUtil.getInstance().loadAppLockSettingsSync(this.context);
    });

    // Register GlobalBus Listeners for Widget Sync
    // We must store the subscribers to prevent GC
    GlobalBus.subscribe(EVENT_SYNC_COMPLETED, () => {
      hilog.info(DOMAIN, 'testTag', 'Sync Completed, updating widgets');
      this.updateAllWidgets();
    }).then((s: commonEventManager.CommonEventSubscriber) => this.commonSubscribers.push(s));

    GlobalBus.subscribe(EVENT_LOGOUT, () => {
      hilog.info(DOMAIN, 'testTag', 'Logout detected, updating widgets and clearing snapshot');
      this.updateAllWidgets();
      // Clear snapshot on logout for security
      try {
        const filePath = this.context.filesDir + '/widget_snapshot.json';
        if (fs.accessSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      } catch (e) { /* ignore */ }
    }).then((s: commonEventManager.CommonEventSubscriber) => this.commonSubscribers.push(s));

    GlobalBus.subscribe(EVENT_LOGIN, () => {
      hilog.info(DOMAIN, 'testTag', 'Login detected, updating widgets');
      this.updateAllWidgets();
    }).then((s: commonEventManager.CommonEventSubscriber) => this.commonSubscribers.push(s));
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, 'testTag', `onConfigurationUpdate, colorMode: ${newConfig.colorMode}`);
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0xFEED, 'EntryAbility', 'Ability onNewWant called');
    if (want && want.parameters) {
      hilog.info(0xFEED, 'EntryAbility', `onNewWant Want parameters: ${JSON.stringify(want.parameters)}`);
    }
    this.handleRouterEvent(want);
    this.handleImportFile(want);
  }

  private handleImportFile(want: Want) {
    if (!want?.uri) return;

    const uri = want.uri;
    const type = want.type; // 获取 UTD 或 MIME 类型
    hilog.info(DOMAIN, 'testTag', `Handling Intent URI: ${uri}, Type: ${type}`);

    try {
      // 精确识别：如果 type 是我们的自定义 UTD，则认为是我们的专有包
      const isOurPackage = type === 'com.accountdl.package';
      if (uri.startsWith('accountdl://')) {
        // 1. Deep Linking Handling
        const urlObject = url.URL.parseURL(uri);
        const action = urlObject.params.get('action');
        const dataStr = urlObject.params.get('data'); // Potentially base64 data

        hilog.info(DOMAIN, 'testTag', `Deep Link Action: ${action}, Host: ${urlObject.hostname}`);

        if (urlObject.hostname === 'login' || uri.startsWith('accountdl://login')) {
          hilog.info(DOMAIN, 'testTag', 'Deep Link handling login action');
          AppStorage.setOrCreate('targetAction', 'Login');
        } else if (action === 'import' && dataStr) {
          const decodedUriData = decodeURIComponent(dataStr);
          const base64 = new util.Base64Helper();
          const decodedUint8 = base64.decodeSync(decodedUriData);
          const decoded = new util.TextDecoder('utf-8').decode(decodedUint8);
          const jsonData = JSON.parse(decoded) as Record<string, Object>;
          if (jsonData && jsonData.subscriptions && Array.isArray(jsonData.subscriptions)) {
            AppStorage.setOrCreate('importData', jsonData);
            hilog.info(DOMAIN, 'testTag', 'Deep Link Data set to AppStorage');
          } else {
            promptAction.showToast({ message: '链接数据有误', duration: 2500 });
          }
        }
      } else if (uri.startsWith('file://')) {
        // 2. File Handling (AirDrop / Huawei Share / File Manager)
        // 提示：由于已经扩充了 module.json5，普通的 .json 也能进入此处。
        if (type && type !== 'application/json' && type !== 'com.accountdl.package' && type !== 'general.json') {
          hilog.warn(DOMAIN, 'testTag', `Received file with unexpected type: ${type}`);
        }

        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(file.fd);
        hilog.info(DOMAIN, 'testTag', `Importing file: ${uri}, size: ${stat.size} bytes`);

        let buf = new ArrayBuffer(stat.size > 0 ? stat.size : 10 * 1024 * 1024);
        let readLen = fs.readSync(file.fd, buf);
        fs.closeSync(file);

        const content = new util.TextDecoder('utf-8').decode(new Uint8Array(buf, 0, readLen));
        const jsonData = JSON.parse(content) as Record<string, Object>;

        // 增加结构校验日志
        if (jsonData && jsonData.subscriptions && Array.isArray(jsonData.subscriptions)) {
          hilog.info(DOMAIN, 'testTag', `Valid JSON structure found. Subscriptions count: ${jsonData.subscriptions.length}`);
          AppStorage.setOrCreate('importData', jsonData);
          hilog.info(DOMAIN, 'testTag', 'File Import Data set to AppStorage');
        } else {
          hilog.error(DOMAIN, 'testTag', `Invalid JSON structure: missing 'subscriptions' array. Keys found: ${Object.keys(jsonData).join(', ')}`);
          promptAction.showToast({ message: '不支持的文件格式', duration: 2500 });
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', `Failed to process intent: ${JSON.stringify(e)}`);
    }
  }

  private async handleRouterEvent(want: Want) {
    hilog.info(DOMAIN, 'testTag', `Handling Router Event: ${JSON.stringify(want)}`);
    if (want && want.parameters && want.parameters.params) {
      try {
        let params: Record<string, Object> = JSON.parse(want.parameters.params as string);
        if (params && params.target) {
          const target = params.target as string;
          hilog.info(DOMAIN, 'testTag', `Router Target: ${target}`);

          if (target === 'ViewSubscriptionDetail' && params.data) {
            try {
              const subData = JSON.parse(params.data as string) as SubscriptionModel;
              hilog.info(DOMAIN, 'testTag', `Router Data: ${params.data}`);

              // 1. 立即设置快照数据，保证 UI 响应速度 (解决"唤起逻辑有问题"的卡顿感)
              AppStorage.setOrCreate('targetSubscription', subData);

              // 2. 后台尝试更新数据 (虽然详情页也会自己刷新，这里更新以保持全局状态一致)
              const uuid = subData.uuid;
              const id = subData.id;

              if (uuid || id) {
                // 异步执行，不阻塞 UI 启动
                setTimeout(async () => {
                  try {
                    await SubscriptionRepository.getInstance().init(this.context);
                    let latestSub: SubscriptionModel | null = null;
                    if (uuid) {
                      latestSub = await SubscriptionRepository.getInstance().findByUuid(uuid);
                    }
                    if (!latestSub && id) {
                      latestSub = await SubscriptionRepository.getInstance().findById(id);
                    }

                    if (latestSub) {
                      hilog.info(DOMAIN, 'testTag', `Async loaded latest data for ${uuid ? 'UUID: ' + uuid : 'ID: ' + id}`);
                      AppStorage.setOrCreate('targetSubscription', latestSub);
                    }
                  } catch (err) {
                    hilog.warn(DOMAIN, 'testTag', `Failed to async update subscription: ${JSON.stringify(err)}`);
                  }
                }, 0);
              }
            } catch (e) {
              hilog.error(DOMAIN, 'testTag', `Failed to parse subData: ${e}`);
            }
          }

          AppStorage.setOrCreate('targetAction', target);
        }
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', `Failed to parse router params: ${e}`);
      }
    }
  }

  async updateAllWidgets(): Promise<void> {
    try {
      hilog.info(DOMAIN, 'testTag', 'Updating widgets via getPublishedRunningFormInfos');

      // 获取桌面上所有活跃卡片 (API 20+)
      const runningForms: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      const formIds: string[] = runningForms.map((info: formInfo.RunningFormInfo): string => info.formId);

      if (!formIds || formIds.length === 0) {
        hilog.info(DOMAIN, 'testTag', 'No active forms found to update');
        return;
      }

      hilog.info(DOMAIN, 'testTag', `Updating ${formIds.length} widgets (IDs: ${formIds.join(',')})`);

      // Prepare Data
      // Ensure Repo Initialized
      await SubscriptionRepository.getInstance().init(this.context);
      const subs = await SubscriptionRepository.getInstance().queryAll();
      const isLoggedIn = AppStorage.get<boolean>('isLoggedIn');

      // Define classes for strong typing
      class CardItemData {
        id: string = '';
        title: string = '';
        content: string = '';
        icon: string = '';
        isExpiring: boolean = false;
        isLifetime: boolean = false;
        price: string = '';
        fullDate: string = '';
        isGroupBuy: boolean = false;
        isWarranty: boolean = false;
        isCard: boolean = false;
        colorStart?: string;
        colorEnd?: string;
        originalItem: string = '';
      }

      class WidgetFormData {
        widgetData: CardItemData[] = [];
        isLoggedIn: boolean = false;
        totalCount: number = 0;
        activeThemeId: string = 'default';
        formImages: Record<string, number> = {};
      }

      let widgetList: CardItemData[] = [];
      const formImages: Record<string, number> = {};
      let imageIndex = 0;


      const openedFiles: fs.File[] = [];

      if (isLoggedIn) {
        const tempDir = this.context.getApplicationContext().tempDir;

        // Use async processing for network images
        widgetList = await Promise.all(subs.map(async (item: SubscriptionModel): Promise<CardItemData> => {
          let iconKey = '';
          let colorStart: string | undefined = undefined;
          let colorEnd: string | undefined = undefined;

          if (item.icon && item.icon.startsWith('file://')) {
            // 自定义图片：使用 memory:// 协议
            const filePath = item.icon.replace('file://', '');
            try {
              if (fs.accessSync(filePath)) {
                const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
                openedFiles.push(file);
                const customImageKey = `customIcon_${imageIndex}_${Date.now()}`;
                formImages[customImageKey] = file.fd;
                iconKey = `memory://${customImageKey}`;
                imageIndex++;
              }
            } catch (e) {
              hilog.warn(DOMAIN, 'testTag', `Failed to load custom icon: ${filePath}`);
              iconKey = item.name?.charAt(0).toUpperCase() || '?';
            }
          } else if (item.recordType === 'groupBuy') {
            // 团购券：处理平台图标
            let rawPath = '';
            if (item.platform === 'meituan') rawPath = 'icons/美团.png';
            else if (item.platform === 'douyin') rawPath = 'icons/抖音.png';
            else if (item.platform === 'dianping') rawPath = 'icons/大众点评.png';

            if (rawPath) {
              const fileName = `platform_${item.platform}.png`;
              const targetPath = `${tempDir}/${fileName}`;
              try {
                let fileExists = false;
                try { fileExists = fs.accessSync(targetPath); } catch(e) {}

                if (!fileExists) {
                  const resourceManager = this.context.resourceManager;
                  const content = await resourceManager.getRawFileContent(rawPath);
                  const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
                  fs.writeSync(file.fd, content.buffer);
                  fs.closeSync(file);
                  fileExists = true;
                }

                if (fileExists) {
                  const file = fs.openSync(targetPath, fs.OpenMode.READ_ONLY);
                  openedFiles.push(file);
                  formImages[fileName] = file.fd;
                  iconKey = `memory://${fileName}`;
                }
              } catch (e) {
                hilog.error(DOMAIN, 'testTag', `Failed to copy platform icon: ${e}`);
              }
            }

            if (!iconKey) {
              iconKey = item.name?.charAt(0).toUpperCase() || '?';
            }
          } else if (item.recordType === 'warranty') {
            // 保修图标处理
            // 优先使用 category 作为图标查找依据，因为 name 可能是用户自定义的
            let warrantyName = item.name || '';
            if (item.category && WARRANTY_ICON_MAP_NAMES[item.category]) {
              warrantyName = item.category;
            } else if (item.subCategory && WARRANTY_ICON_MAP_NAMES[item.subCategory]) {
              warrantyName = item.subCategory;
            }

            const theme = WARRANTY_THEME_MAP[warrantyName] || 'blue';
            const colors = getWarrantyThemeColors(theme);
            colorStart = colors[0];
            colorEnd = colors[1];

            const svgPath = WARRANTY_ICON_MAP_NAMES[warrantyName];
            if (svgPath) {
              iconKey = `rawfile:${svgPath}`;
            } else {
              iconKey = item.name?.charAt(0).toUpperCase() || '?';
            }
          } else if (item.icon && (item.icon.startsWith('http://') || item.icon.startsWith('https://'))) {
            // 网络图片: 下载并使用 memory:// 协议
            try {

              const fileName = `net_${item.uuid || item.id}.png`;
              const targetPath = `${tempDir}/${fileName}`;
              let fileExists = false;

              try { fileExists = fs.accessSync(targetPath); } catch(e) {}

              if (!fileExists) {
                hilog.info(DOMAIN, 'testTag', `Downloading icon for widget: ${item.name}`);
                const httpRequest = http.createHttp();
                const resp = await httpRequest.request(item.icon, {
                  readTimeout: 5000,
                  connectTimeout: 5000
                });
                if (resp.responseCode === 200) {
                  const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
                  fs.writeSync(file.fd, resp.result as ArrayBuffer);
                  fs.closeSync(file);
                  fileExists = true;
                }
                httpRequest.destroy();
              }

              if (fileExists) {
                const file = fs.openSync(targetPath, fs.OpenMode.READ_ONLY);
                openedFiles.push(file);
                formImages[fileName] = file.fd;
                iconKey = `memory://${fileName}`;
              } else {
                iconKey = item.name?.charAt(0).toUpperCase() || '?';
              }
            } catch (e) {
              hilog.error(DOMAIN, 'testTag', `Failed to process net icon: ${JSON.stringify(e)}`);
              iconKey = item.name?.charAt(0).toUpperCase() || '?';
            }
          } else if (item.icon && item.icon.startsWith('resource:')) {
            iconKey = item.icon.substring(9);
          } else if (item.name && item.name.length > 0) {
            iconKey = item.name.charAt(0).toUpperCase();
          }

          if (!iconKey) {
            iconKey = item.name?.charAt(0).toUpperCase() || '?';
          }

          let cardItem = new CardItemData();
          cardItem.id = item.uuid || item.id?.toString() || '';
          cardItem.title = item.name || '未知订阅';
          cardItem.originalItem = JSON.stringify(item);

          const isLifetime = item.billingCycle === 'Lifetime';
          const isGroupBuy = item.recordType === 'groupBuy';
          const isWarranty = item.recordType === 'warranty';
          const isCard = item.recordType === 'card';
          // card 类型虽然 billingCycle=Lifetime，仍需要真实到期日
          const days = (isLifetime && !isWarranty && !isCard) ? 999 : DateUtil.getDaysUntil(item.nextBillingDate);
          const dateStr = DateUtil.formatShortDate(item.nextBillingDate);

          cardItem.isGroupBuy = isGroupBuy;
          cardItem.isWarranty = isWarranty;
          cardItem.isCard = isCard;
          cardItem.isLifetime = isLifetime;

          if (isGroupBuy) {
            const statusText: string = item.usageStatus === 'used' ? '已使用' : (item.usageStatus === 'expired' ? '已过期' : (DateUtil.getDaysUntil(item.nextBillingDate) < 0 ? '已过期' : `剩 ${DateUtil.getDaysUntil(item.nextBillingDate)} 天`));
            cardItem.content = item.merchantName ? `${item.merchantName} | ${statusText}` : statusText;
          } else if (isWarranty) {
            const days = DateUtil.getDaysUntil(item.nextBillingDate);
            const statusStr = days < 0 ? '过保' : '在保';
            cardItem.content = `${statusStr}:${dateStr}`;
          } else if (isCard) {
            // 卡证：显示到期日
            cardItem.content = days < 0 ? '已过期' : (days === 0 ? '今日到期' : `到期:${dateStr}`);
          } else {
            cardItem.content = isLifetime ? `永久买断` : `到期:${dateStr}`;
          }

          // 普通订阅和保修在剩余3天内标红；团购券如果是未使用且剩余3天内也标红
          if (isGroupBuy) {
            cardItem.isExpiring = item.usageStatus === 'unused' && days <= 3;
          } else {
            cardItem.isExpiring = days <= 3;
          }

          cardItem.icon = iconKey;
          cardItem.colorStart = colorStart;
          cardItem.colorEnd = colorEnd;

          let priceStr = `${item.currency === 'USD' ? '$' : '¥'}${item.price}`;
          if (!isGroupBuy && !isWarranty && !isCard) {
            if (item.billingCycle === 'Monthly') priceStr += '/月';
            else if (item.billingCycle === 'Yearly') priceStr += '/年';
            else if (item.billingCycle === 'Quarterly') priceStr += '/季';
            else if (item.billingCycle === 'Lifetime') priceStr += '/永久';
            else if (item.billingCycle === 'Indefinite') priceStr += '/不定';
          } else if (isWarranty) {
            priceStr = '保修';
          } else if (isCard) {
            priceStr = item.cardBalance !== undefined && item.cardBalance !== null
              ? `余额 ¥${item.cardBalance.toFixed(2)}`
              : (item.cardType || '卡证');
          }
          cardItem.price = priceStr;
          return cardItem;
        }));
      }

      let formData = new WidgetFormData();
      formData.totalCount = subs.length;
      formData.widgetData = widgetList;
      formData.isLoggedIn = isLoggedIn ?? false;
      formData.activeThemeId = PreferenceUtil.getInstance().getThemeId();

      if (Object.keys(formImages).length > 0) {
        formData.formImages = formImages;
      }

      // --- 新增：卡片列表排序逻辑，团购已使用/已过期置底 ---
      formData.widgetData.sort((a, b) => {
        try {
          const aObj = JSON.parse(a.originalItem) as SubscriptionModel;
          const bObj = JSON.parse(b.originalItem) as SubscriptionModel;

          const aProcessed = aObj.recordType === 'groupBuy' && (aObj.usageStatus === 'used' || aObj.usageStatus === 'expired');
          const bProcessed = bObj.recordType === 'groupBuy' && (bObj.usageStatus === 'used' || bObj.usageStatus === 'expired');

          if (aProcessed && !bProcessed) return 1;
          if (!aProcessed && bProcessed) return -1;
          return 0;
        } catch (e) {
          return 0;
        }
      });

      hilog.info(DOMAIN, 'testTag', `updateAllWidgets: Pushing update to ${formIds.length} widgets. items=${formData.widgetData.length}, total=${formData.totalCount}, images=${Object.keys(formImages).length}`);

      let bindingData = formBindingData.createFormBindingData(formData);

      // Update Each Form Sequentially and Wait
      for (const formId of formIds) {
        try {
          await formProvider.updateForm(formId, bindingData);
          hilog.info(DOMAIN, 'testTag', `Updated form ${formId}`);
        } catch (err) {
          // Cast to BusinessError to access code/message
          let error = err as BusinessError;
          hilog.error(DOMAIN, 'testTag', `Failed to update form ${formId}: ${error.code} ${error.message}`);
          // 16501001: The ID of the form to be operated does not exist.
          if (error.code === 16501001) {
            hilog.warn(DOMAIN, 'testTag', `Cleaning up non-existent formId: ${formId}`);
            PreferenceUtil.getInstance().removeFormId(formId);
          }
        }
      }

      // Do NOT close FDs here! Per HarmonyOS docs, FDs should remain open
      // and be released when UIAbility process is destroyed.

    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, 'testTag', `updateAllWidgets failed: ${JSON.stringify(error)}`);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    NetworkMonitor.getInstance().stopMonitoring();
    AccountMonitor.getInstance().stopMonitoring();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 关键修正：在加载 UI 内容前，同步加载平行视界状态
    // 这确保 Index 页面初始化时能直接获取到正确的 isSplitViewEnabled 值，
    // 从而避免从默认值(false)到保存值(true)的跳变动画
    PreferenceUtil.getInstance().loadSplitViewEnabledSync(this.context);

    // 关键修正：同步加载智感握姿状态
    PreferenceUtil.getInstance().loadSmartGestureEnabledSync(this.context);

    // 关键修正：同步加载主题状态，防止 TabBar +号图标颜色在启动时闪烁
    PreferenceUtil.getInstance().loadThemeIdSync(this.context);

    // 关键修正：同步加载应用锁配置，防止启动时面板跳变和布局闪烁
    PreferenceUtil.getInstance().loadAppLockSettingsSync(this.context);

    // 关键修正：同步加载动画配置，防止启动动画参数缺失
    PreferenceUtil.getInstance().loadAnimationSettingsSync(this.context);

    // 关键修正：同步加载 HDS Tabs 状态 (API 23 Features)
    PreferenceUtil.getInstance().loadHdsTabsEnabledSync(this.context);

    // 设置窗口全屏布局（底部沉浸式需要此设置）
    let windowClass: window.Window = windowStage.getMainWindowSync();
    let isLayoutFullScreen = true;
    windowClass.setWindowLayoutFullScreen(isLayoutFullScreen).then(() => {
      hilog.info(DOMAIN, 'testTag', 'Succeeded in setting the window layout to full-screen mode.');

      // 获取顶部状态栏高度（用于UI避让）
      let topType = window.AvoidAreaType.TYPE_SYSTEM;
      let topAvoidArea = windowClass.getWindowAvoidArea(topType);
      let topRectHeight = topAvoidArea.topRect.height;
      AppStorage.setOrCreate('topRectHeight', topRectHeight);
      AppStorage.setOrCreate('statusBarHeight', topRectHeight);
      hilog.info(DOMAIN, 'testTag', `Top status bar height: ${topRectHeight}px`);

      // 预计算 isWide 状态，防止启动时的布局跳变
      try {
        const displayClass = display.getDefaultDisplaySync();
        // 修正：使用 getWindowProperties().windowRect.width 计算宽度
        // 注意：display.getDefaultDisplaySync() 获取的是物理屏幕信息，densityPixels 是屏幕密度
        // windowRect.width 是 px 单位，需要除以 densityPixels 转换为 vp
        // 但是 getWindowProperties().windowRect.width 也是 px
        // 此处逻辑需确保单位转换正确
        const widthVp = windowClass.getWindowProperties().windowRect.width / displayClass.densityPixels;
        const isWide = widthVp >= 600;
        AppStorage.setOrCreate('isWide', isWide);
        hilog.info(DOMAIN, 'testTag', `Pre-calculated isWide: ${isWide} (widthVp: ${widthVp})`);
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', `Failed to calculate isWide: ${e}`);
      }

      // 获取底部导航区域高度
      let bottomType = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR;
      let bottomAvoidArea = windowClass.getWindowAvoidArea(bottomType);
      let bottomRectHeight = bottomAvoidArea.bottomRect.height;
      AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
      hilog.info(DOMAIN, 'testTag', `Bottom navigation indicator height: ${bottomRectHeight}px`);

      // 注册监听函数，动态获取避让区域数据
      windowClass.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          let topRectHeight = data.area.topRect.height;
          AppStorage.setOrCreate('topRectHeight', topRectHeight);
          AppStorage.setOrCreate('statusBarHeight', topRectHeight);
          hilog.info(DOMAIN, 'testTag', `Top avoid area changed: ${topRectHeight}px`);
        } else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          let bottomRectHeight = data.area.bottomRect.height;
          AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
          hilog.info(DOMAIN, 'testTag', `Bottom avoid area changed: ${bottomRectHeight}px`);
        }
      });
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', `Failed to set the window layout to full-screen mode. Code is ${err.code}, message is ${err.message}`);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // Check for updates silently
      setTimeout(() => {
        UpdateManager.getInstance().checkUpdate(this.context as common.UIAbilityContext, true);
      }, 2000); // Delay check to prioritize startup rendering

      // 提醒自检修复 (延迟执行，静默自愈)
      setTimeout(async () => {
        await LocalNotificationManager.getInstance().selfCheckReminders();
      }, 5000); // 启动5秒后执行，不影响首屏加载

      // 延迟处理导入数据，确保 promptAction 弹出层可用
      if (this.pendingImportWant) {
        this.handleImportFile(this.pendingImportWant);
        this.pendingImportWant = null; // 处理完即清空
      }

      // 请求通知授权
      notificationManager.requestEnableNotification(this.context).then(() => {
        hilog.info(DOMAIN, 'testTag', '[ANS] requestEnableNotification success');
        // 关键：授权成功后发送全局总线事件，让首页等组件及时刷新提醒预约状态
        GlobalBus.publish(EVENT_NOTIFY_PERMISSION_GRANTED);
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', '[ANS] requestEnableNotification failed, code is %{public}d', err.code);
      });
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');

    // 如果不是从闪控球返回应用（例如点击图标或从多任务返回），则自动清除所有残留的闪控球
    if (!FloatingBallManager.getInstance().getReturningFromBall()) {
      hilog.info(DOMAIN, 'testTag', 'App returned not from FloatingBall, stopping ball if any');
      FloatingBallManager.getInstance().stop();
    }

    // 立即重置状态，确保下一次返回时重新判断
    FloatingBallManager.getInstance().setReturningFromBall(false);
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
