import { PasswordLockPage } from '../view/PasswordLockPage';
import { HomeView } from '../view/HomeView';
import { SettingsView } from '../view/SettingsView';
import { StatsView } from '../view/StatsView';
import { CalendarView } from '../view/CalendarView';
import { LoginSheet } from '../view/LoginSheet';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { HuaweiAuthManager } from '../utils/HuaweiAuthManager';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { display, mediaquery, promptAction, curves } from '@kit.ArkUI';
import { UpdateManager } from '../utils/UpdateManager';
import { hdsEffect, HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, HdsNavigationAttribute,
  HdsTabs } from '@kit.UIDesignKit';
import { SubscriptionDetailOverlay } from '../view/SubscriptionDetailOverlay';
import { QueryResultsOverlay } from '../view/QueryResultsOverlay';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { preferences } from '@kit.ArkData';
import { PreferenceUtil, MembershipInfo } from '../utils/PreferenceUtil';
import { BackgroundWatermark } from '../view/BackgroundWatermark';
import { ImportSheet } from '../view/ImportSheet';
import { IconLibraryPage } from '../view/IconLibraryPage';
import { ExportData, HarmonyShareManager } from '../utils/HarmonyShareManager';
import { motion } from '@kit.MultimodalAwarenessKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { WebViewParam } from '../view/WebViewPage';
import { AddMenuSheet } from '../view/AddMenuSheet';

interface Scale {
  x: number;
  y: number;
}

@Entry
@Component
struct Index {
  @StorageLink('isLocked') isLocked: boolean = false;
  @Provide('pageStack') pageStack: NavPathStack = AppStorage.get<NavPathStack>('pageStack') || new NavPathStack();
  @StorageLink('isLoggedIn') @Watch('onLoginStatusChange') isLoggedIn: boolean = false;
  @StorageLink('isOnline') isOnline: boolean = true;
  @StorageLink('appLockPasswordLength') passwordLength: number = 4;
  @StorageLink('isWide') isWide: boolean = false;
  @StorageLink('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('hasNewVersion') hasNewVersion: boolean = false;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true; // 会员配色开关
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('currentColorMode') @Watch('onConfigChange') currentColorMode: number = 0;
  private listener = mediaquery.matchMediaSync('(width >= 600vp)');
  @State currentIndex: number = 0;
  @State showLoginSheet: boolean = false;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @StorageLink('targetAction') @Watch('onTargetActionChange') targetAction: string = '';
  @State tabBarVisible: boolean = true; // Tab 栏可见性
  @StorageLink('animationDuration') animationDuration: number = 300;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  // 全局详情页状态
  @StorageLink('isDetailVisible') isDetailVisible: boolean = false;
  @StorageLink('isQueryResultsVisible') isQueryResultsVisible: boolean = false;
  @StorageLink('detailSubscriptionData') detailData: SubscriptionModel | undefined = undefined;
  @StorageLink('isSplitViewEnabled') @Watch('onSplitViewChange') isSplitViewEnabled: boolean = false;
  @State placeholderOpacity: number = 0;
  @State splitViewBeforeFold: boolean = true; // Remember split view state before folding
  @StorageLink('isTabBarCollapsed') isTabBarCollapsed: boolean = false; // TabBar collapse state
  @StorageLink('isSmartGestureEnabled') @Watch('onSmartGestureChange') isSmartGestureEnabled: boolean = false;
  @StorageLink('collapseSide') collapseSide: 'left' | 'right' = 'right'; // TabBar collapse direction
  @StorageLink('smartHandMode') smartHandMode: 'left' | 'right' | 'center' = 'center'; // Smart Gesture Mode
  @State tabBarScale: number = 1.0; // 用于位置切换时的动效反馈
  @State indicatorScale: Scale = { x: 1.0, y: 1.0 }; // 液滴挤压变形

  // 全局导入状态
  @StorageLink('importData') @Watch('onImportDataChange') importData: ExportData | null = null;
  @State showImportSheet: boolean = false;
  @State localImportSubs: SubscriptionModel[] = [];
  @State isInternalRedirect: boolean = false; // 标记是否为内部跳转，防止 onChange 误关闭详情页

  // 标题栏状态
  @State rotateAngle: number = 0;
  @State isRotating: boolean = false;
  @State isBellPressed: boolean = false;
  @State bellLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isSharePressed: boolean = false;
  @State shareLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isRefreshPressed: boolean = false;
  @State refreshLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  onConfigChange() {
    hilog.info(0x0000, 'Index', 'onConfigChange: Color mode changed, refreshing wide status');
    this.refreshWideStatus();
  }

  onTargetActionChange() {
    // 关键：将所有逻辑包裹在 setTimeout 中，确保在渲染周期外执行，避免 "changed during render" 错误
    setTimeout(() => {
      if (!this.targetAction) {
        return;
      }

      if (this.targetAction === 'AddSubscription') {
        hilog.info(0xFEED, 'Index', 'Handling AddSubscription action');
        AppStorage.setOrCreate('hasShownUpcomingSheet', true);
        AppStorage.setOrCreate('targetAction', '');
        this.onAddClick();
      } else if (this.targetAction === 'ViewSubscriptionDetail') {
        hilog.info(0xFEED, 'Index', 'Handling ViewSubscriptionDetail action');
        const targetSub = AppStorage.get<SubscriptionModel>('targetSubscription');
        if (targetSub) {
          this.isInternalRedirect = true;
          AppStorage.setOrCreate('targetAction', '');

          // 1. 切换 Tab 和清空堆栈
          if (this.currentIndex !== 0) {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.currentIndex = 0;
                this.indicatorScale = { x: 1.25, y: 0.8 } as Scale;
              })
              setTimeout(() => {
                animateTo({ duration: 400, curve: curves.springMotion() }, () => {
                  this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
                })
              }, 150)
            } else {
              this.currentIndex = 0;
              this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
            }
            this.tabsController.changeIndex(0);
          }
          if (this.pageStack.size() > 0) {
            this.pageStack.clear();
          }

          // 2. 延迟触发详情页
          setTimeout(() => {
            this.detailData = targetSub;
            AppStorage.setOrCreate('detailSubscriptionData', targetSub);

            setTimeout(() => {
              this.detailData = targetSub;
              AppStorage.setOrCreate('detailSubscriptionData', targetSub);
              if (this.isAnimationEnabled) {
                animateTo({ duration: 400, curve: Curve.FastOutSlowIn }, () => {
                  this.isDetailVisible = true;
                });
              } else {
                this.isDetailVisible = true;
              }

              setTimeout(() => {
                this.isInternalRedirect = false;
              }, 500);
            }, 50);
          }, 300);
        }
      } else if (this.targetAction === 'DirectAddSubscription') {
        hilog.info(0xFEED, 'Index', 'Handling DirectAddSubscription action');
        const targetSub = AppStorage.get<SubscriptionModel>('targetSubscription');
        if (targetSub) {
          AppStorage.setOrCreate('targetAction', '');
          this.pageStack.pushPathByName('AddSubscription', targetSub);
        }
      } else if (this.targetAction === 'ViewCalendar') {
        hilog.info(0xFEED, 'Index', 'Handling ViewCalendar action');
        AppStorage.setOrCreate('targetAction', '');
        this.currentIndex = 1;
        this.tabsController.changeIndex(1);
      } else if (this.targetAction === 'ViewStats') {
        hilog.info(0xFEED, 'Index', 'Handling ViewStats action');
        AppStorage.setOrCreate('targetAction', '');
        this.currentIndex = 2;
        this.tabsController.changeIndex(2);
      }
    }, 0);
  }

  onWidthChange(mediaQueryResult: mediaquery.MediaQueryResult) {
    // mediaquery 可能在某些形态切换瞬间不准，我们辅助以 refreshWideStatus
    this.refreshWideStatus();
    this.updateTabBarVisibility();
  }

  onPageShow() {
    // 强制检查宽度。启动时已在 aboutToAppear 同步检查过，此处仅作为生命周期兜底
    this.refreshWideStatus();

    // Notify components that app is in foreground
    const context = getContext(this) as common.UIAbilityContext;
    context.eventHub.emit('onForeground');
  }

  private refreshWideStatus() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const windowClass = context.windowStage.getMainWindowSync();
      const rect = windowClass.getWindowProperties().windowRect;
      const widthVp = this.getUIContext().px2vp(rect.width);

      const newIsWide = widthVp >= 600;
      hilog.info(0x0000, 'Index', `refreshWideStatus: widthVp=${widthVp}, newIsWide=${newIsWide}`);

      if (this.isWide !== newIsWide) {
        this.isWide = newIsWide;
        AppStorage.setOrCreate('isWide', this.isWide);
      }

      // 优化：不再使用异步 load，直接从 AppStorage 获取或同步判定
      // EntryAbility 已经同步 load 过 preference 到 AppStorage 了
      const prefEnabled = AppStorage.get<boolean>('isSplitViewEnabled') ?? false;

      if (this.isWide) {
        if (prefEnabled && !this.isSplitViewEnabled) {
          this.isSplitViewEnabled = true;
        } else if (!prefEnabled && this.isSplitViewEnabled) {
          this.isSplitViewEnabled = false;
        }
      } else {
        if (this.isSplitViewEnabled) {
          this.isSplitViewEnabled = false;
        }
      }
      
      // 状态同步后，立即刷新占位图可见性
      this.updatePlaceholderVisibility();
    } catch (e) {
      hilog.error(0x0000, 'Index', `refreshWideStatus failed: ${JSON.stringify(e)}`);
    }
  }

  onPageHide() {
    // Notify components that app is in background
    const context = getContext(this) as common.UIAbilityContext;
    context.eventHub.emit('onBackGround');
  }

  aboutToAppear() {
    // Check App Lock - 修正：优先使用 AppStorage 同步获取的状态，防止异步加载导致的启动跳变
    const hasLock = AppStorage.get<boolean>('hasAppLock');
    if (hasLock !== undefined) {
      this.isLocked = hasLock;
    } else {
      // Fallback: 兜底异步加载
      PreferenceUtil.getInstance().getAppLockPassword().then(password => {
        if (password) {
          this.isLocked = true;
        }
      });
    }

    // Initialize pageStack handle for others
    if (!AppStorage.get<NavPathStack>('pageStack')) {
      AppStorage.setOrCreate('pageStack', this.pageStack);
    }

    this.listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.onWidthChange(result);
    });

    // 监听窗口尺寸变化，这是最可靠的同步点
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const windowClass = context.windowStage.getMainWindowSync();
      windowClass.on('windowSizeChange', (size: window.Size) => {
        hilog.info(0x0000, 'Index', `windowSizeChange: ${size.width}x${size.height}`);
        this.refreshWideStatus();
      });
    } catch (e) {}

    // 0. 会员状态已在 EntryAbility 中预加载，此处只需检查过期并移除遮罩
    PreferenceUtil.getInstance().loadMembership().then((_: MembershipInfo) => {
      // 检查本地缓存过期情况（即使离线）
      this.checkMembershipExpiry();
    });

    // Load Split Navigation preference
    PreferenceUtil.getInstance().get('isWide', false).then((val: preferences.ValueType) => {
      const isWideVal = val as boolean;
      if (isWideVal) {
        this.isWide = isWideVal;
      }
    });
    // Initialize memory with saved state
    this.refreshWideStatus(); // 首次加载时同步物理状态
    // Load New Year Watermark Preference
    PreferenceUtil.getInstance().loadNewYearWatermarkEnabled();

    this.isWide = this.listener.matches;
    AppStorage.setOrCreate('isWide', this.isWide);

    // Check for updates silently
    setTimeout(() => {
      UpdateManager.getInstance().checkUpdate(getContext(this) as common.UIAbilityContext, true);
    }, 2000); // Delay check to prioritize startup rendering

    // 定期检查 pageStack 大小，更新 Tab 栏可见性和占位界面
    // 注册导航拦截器，监听页面跳转
    this.pageStack.setInterception({
      willShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar, operation: NavigationOperation, animated: boolean) => {
        this.updateTabBarVisibility();
        this.updatePlaceholderVisibility();
      }
    });

    if (this.targetAction) {
      this.onTargetActionChange();
    }

    // 如果此前的状态是已登录，则自动尝试静默登录以刷新 Session
    if (this.isLoggedIn) {
      PreferenceUtil.getInstance().get('lastLoginTime', 0).then((time: Object) => {
        hilog.info(0x0000, 'Index', `User logged in, last login: ${time as number}`);
      });
      HuaweiAuthManager.getInstance().login(true).then(() => {
        SubscriptionRepository.getInstance().syncWithCloud();
        // 检查会员状态并提醒即将到期
        this.checkMembershipExpiry();
      }).catch((err: BusinessError) => {
        // 仅记录日志，不打扰用户，也不退出登录（此时 AccountMonitor 已经处理过是否退出的逻辑了）
      });
    }

    // Initialize Smart Gesture
    if (this.isSmartGestureEnabled) {
      this.subscribeSmartGesture();
    }

    // 检查是否有挂起的导入数据
    if (this.importData) {
      this.checkImportData();
    }

    // 检查协议更新
    this.checkUserAgreementUpdate();
  }

  /**
   * 检查用户协议更新（只有在手动提升 LATEST_AGREEMENT_VERSION 且已登录时触发）
   */
  async checkUserAgreementUpdate() {
    // 只有已登录用户才需要收到协议更新的消息提醒
    if (!this.isLoggedIn) {
      return;
    }

    // --- 这里的数字需要你在每次更新 user_agreement.html 且想让用户强制知道时手动加 1 ---
    const LATEST_AGREEMENT_VERSION = 109;

    try {
      const lastConfirmedVersion: number = await PreferenceUtil.getInstance().getLastAgreementVersion();

      // 如果本地记录的已确认版本 小于 当前代码要求的最新版本
      if (lastConfirmedVersion < LATEST_AGREEMENT_VERSION) {
        hilog.info(0x0000, 'Index', `Agreement update detected: ${lastConfirmedVersion} -> ${LATEST_AGREEMENT_VERSION}`);

        promptAction.showDialog({
          title: '用户协议更新',
          message: '为了更好地为您提供服务，我们更新了\r\n《用户协议》及免责声明。\r\n请您在继续使用前请点击“了解更多”进行详细阅读。\r\n点击“我知道了”默认代表您已同意更新后的《用户协议》及免责声明。\r\n若您不同意《用户协议》及免责声明中的内容，您可以在我的-撤销隐私协议进行数据注销处理并退出本应用。',
          buttons: [
            { text: '了解更多', color: $r('app.color.text_secondary') },
            { text: '我知道了', color: $r('app.color.brand_color') }
          ]
        }).then(async (result: promptAction.ShowDialogSuccessResponse) => {
          // 优先保存状态，防止后续导航或异常导致保存失败
          await PreferenceUtil.getInstance().saveLastAgreementVersion(LATEST_AGREEMENT_VERSION);

          if (result.index === 0) {
            this.pageStack.pushPathByName('WebView', new WebViewParam($rawfile('user_agreement.html'), '用户协议'));
          }
        });
      }

      // 同时仍然备份一下 APP 版本号作为一般记录（可选）
      const flags: number = 0;
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(flags);
      await PreferenceUtil.getInstance().saveLastKnownVersion(`${info.versionName} (${info.versionCode})`);

    } catch (e) {
      hilog.error(0x0000, 'Index', `checkUserAgreementUpdate failed: ${JSON.stringify(e)}`);
    }
  }

  onImportDataChange() {
    if (this.importData) {
      this.checkImportData();
    }
  }

  private checkImportData() {
    if (!this.importData) return;
    if (!this.importData.subscriptions || !Array.isArray(this.importData.subscriptions)) {
      promptAction.showToast({ message: '数据解析失败', duration: 2500 });
      AppStorage.setOrCreate('importData', null);
      return;
    }
    this.localImportSubs = this.importData.subscriptions;
    this.showImportSheet = true;
  }

  aboutToDisappear() {
    this.unsubscribeSmartGesture();
  }

  onSmartGestureChange() {
    // Save state
    PreferenceUtil.getInstance().saveSmartGestureEnabled(this.isSmartGestureEnabled);

    if (this.isSmartGestureEnabled) {
      this.subscribeSmartGesture();
    } else {
      this.unsubscribeSmartGesture();
      // Reset to center mode when disabled
      animateTo({ duration: 600, curve: curves.springMotion(0.4, 0.8) }, () => {
        this.smartHandMode = 'center';
      });
    }
  }

  private subscribeSmartGesture() {
    try {
      motion.on('holdingHandChanged', (data: motion.HoldingHandStatus) => {
        hilog.info(0x0000, 'Index', `SmartGesture: holdingHandChanged=${data}`);

        if (data === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          // 左手窄模式：立即响应
          animateTo({ duration: 600, curve: curves.springMotion(0.4, 0.8) }, () => {
            this.smartHandMode = 'left';
            // 如果已收起，则切换收起方向；否则保持展开状态
            if (this.isTabBarCollapsed) {
              this.collapseSide = 'left';
            }
          });
        } else if (data === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          // 右手窄模式：立即响应
          animateTo({ duration: 600, curve: curves.springMotion(0.4, 0.8) }, () => {
            this.smartHandMode = 'right';
            // 如果已收起，则切换收起方向；否则保持展开状态
            if (this.isTabBarCollapsed) {
              this.collapseSide = 'right';
            }
          });
        } else {
          // 双手或无握姿 -> 恢复中心位置（但不自动展开）
          animateTo({ duration: 600, curve: curves.springMotion(0.4, 0.8) }, () => {
            this.smartHandMode = 'center';
            // Remove auto-expand logic: isTabBarCollapsed remains as is
          });
        }
      });
      hilog.info(0x0000, 'Index', 'subscribeSmartGesture succeeded');
    } catch (err) {
      let error = err as BusinessError;
      hilog.error(0x0000, 'Index', `Failed to subscribeSmartGesture: ${error.code} ${error.message}`);
    }
  }

  private unsubscribeSmartGesture() {
    try {
      motion.off('holdingHandChanged');
      hilog.info(0x0000, 'Index', 'unsubscribeSmartGesture succeeded');
    } catch (e) {}
  }

  /**
   * 检查会员状态，即将到期时提醒用户续费
   * 每日只提醒一次，避免频繁打扰
   */
  async checkMembershipExpiry() {
    const membership: MembershipInfo = await PreferenceUtil.getInstance().loadMembership();

    // 永久会员无需检查
    if (membership.level === 'lifetime') {
      return;
    }

    // 检查是否为 Pro 会员
    if (membership.level === 'pro' && membership.expiry > 0) {
      const now = Date.now();
      const daysLeft = Math.ceil((membership.expiry - now) / (1000 * 60 * 60 * 24));

      // 检查今天是否已经提醒过（避免每次启动都弹窗）
      const today = new Date().toDateString();
      const lastCheckDate = AppStorage.get<string>('lastExpiryCheckDate') || '';

      if (lastCheckDate === today) {
        // 今天已经提醒过（无论是即将到期还是已过期），跳过
        return;
      }

      // 已过期
      if (daysLeft <= 0) {
        // 更新本地状态为非 VIP
        AppStorage.setOrCreate('isVip', false);
        AppStorage.setOrCreate('lastExpiryCheckDate', today);

        // 弹窗提醒
        promptAction.showDialog({
          title: '会员已过期',
          message: '您的 Pro 会员已到期，云同步和云推送功能已暂停。\n\n您的本地数据不会丢失，云端数据也将保留 30 天，续费后可恢复同步。',
          buttons: [
            { text: '稍后再说', color: $r('app.color.text_secondary') },
            { text: '立即续费', color: $r('app.color.brand_color') }
          ]
        }).then(result => {
          if (result.index === 1) {
            this.pageStack.pushPathByName('Membership', null);
          }
        });
        return;
      }

      // 即将到期（3天内）
      if (daysLeft <= 3 && daysLeft > 0) {
        AppStorage.setOrCreate('lastExpiryCheckDate', today);

        promptAction.showDialog({
          title: '会员即将到期',
          message: `您的 Pro 会员将在 ${daysLeft} 天后到期，到期后云同步和云推送功能将暂停。\n\n立即续费可继续享受 VIP 权益。`,
          buttons: [
            { text: '稍后再说', color: $r('app.color.text_secondary') },
            { text: '立即续费', color: $r('app.color.brand_color') }
          ]
        }).then(result => {
          if (result.index === 1) {
            this.pageStack.pushPathByName('Membership', null);
          }
        });
      }
    }
  }

  onLoginStatusChange() {
    if (!this.isLoggedIn) {
      // Delay clear to avoid render conflict if triggered during build
      // Also check if stack is already empty to avoid redundant updates
      if (this.pageStack.size() > 0) {
        setTimeout(() => {
          this.pageStack.clear();
        }, 0);
      }
    }
  }

  updatePlaceholderVisibility() {
    // Only show placeholder if screen is wide AND split view is enabled AND stack is empty
    const shouldShow = this.isWide && this.isSplitViewEnabled && this.pageStack.size() === 0;

    if (shouldShow && this.placeholderOpacity === 0) {
      // 首次显示或状态切换回主屏时：淡入显示
      if (this.isAnimationEnabled) {
        animateTo({ duration: 400, curve: Curve.EaseInOut }, () => {
          this.placeholderOpacity = 1;
        });
      } else {
        this.placeholderOpacity = 1;
      }
    }
    else if (!shouldShow && this.placeholderOpacity === 1) {
      // 切换到二级页面或关闭平行世界时：立即隐藏
      this.placeholderOpacity = 0;
    }
  }

  updateTabBarVisibility() {
    // Unified TabBar visibility logic:
    // Hide TabBar when stack is not empty, UNLESS we are in split-screen mode on a wide screen.
    setTimeout(() => {
      if (this.isWide && this.isSplitViewEnabled) {
        // Split-view mode: TabBar (Side Navigation) stays visible
        this.tabBarVisible = true;
      } else {
        // Phone mode OR Tablet without Split-view: Hide TabBar on sub-pages
        this.tabBarVisible = this.pageStack.size() === 0;
      }
    }, 0);
  }

  onSplitViewChange() {
    this.updatePlaceholderVisibility();
    this.updateTabBarVisibility();
  }

  onAddClick() {
    if (!this.isLoggedIn) {
      if (this.isWide && this.isSplitViewEnabled) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
    } else {
      this.showAddSheet = true;
    }
  }

  @StorageLink('showAddSheet') showAddSheet: boolean = false;

  @State addButtonScale: number = 1.0;
  @State addButtonAngle: number = 0;
  @State addButtonLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  private tabsController: TabsController = new TabsController();

  @Builder TabBuilder(index: number, name: string, icon: Resource) {
    if (index === 2) {
      // 中间的 "添加" 按钮 (Rudder Style)
      Column() {
        Column() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor([Color.White])
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r('app.color.brand_color'))
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 10, color: '#40007AFF', offsetY: 6 })
        .margin({ bottom: 20 }) // Make it protrude upwards
        .scale({ x: this.addButtonScale, y: this.addButtonScale })
        .onClick(() => {
          animateTo({ duration: 50, curve: Curve.Sharp }, () => {
            this.addButtonScale = 0.8;
          });
          setTimeout(() => {
            animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
              this.addButtonScale = 1.0;
            });
            this.onAddClick();
          }, 50);
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    } else {
      // 普通 Tab - unused in custom bar but kept for reference
      TabBarItem({
        index: index,
        currentIndex: this.currentIndex,
        name: name,
        icon: icon,
        onSelect: () => {
          this.currentIndex = index;
          this.tabsController.changeIndex(index);
        }
      })
    }
  }

  @Builder AddMenuSheetBuilder() {
    AddMenuSheet()
  }

  @Builder CustomFloatingTabBar() {
    Row() {
      if (this.isTabBarCollapsed) {
        // 收起状态：显示展开按钮
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.collapseSide === 'right' ? $r('sys.symbol.chevron_left') : $r('sys.symbol.chevron_right'))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
        }
        .width('100%')
        .height('100%')
        .padding({ top: 2, bottom: 2 })
        .onClick(() => {
          if (this.isAnimationEnabled) {
            animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
              this.isTabBarCollapsed = false;
            })
          } else {
            this.isTabBarCollapsed = false;
          }
        })
      } else {
        // 展开状态：显示完整 TabBar
        // 首页
        TabBarItem({
          index: 0,
          currentIndex: this.currentIndex,
          name: '首页',
          icon: $r('sys.symbol.house'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.currentIndex = 0;
                this.indicatorScale = { x: 1.3, y: 0.7 } as Scale;
              })
              setTimeout(() => {
                animateTo({ duration: 400, curve: curves.springMotion() }, () => {
                  this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
                })
              }, 150)
            } else {
              this.currentIndex = 0;
            }
            this.tabsController.changeIndex(0);
          }
        })

        // 日历
        TabBarItem({
          index: 1,
          currentIndex: this.currentIndex,
          name: '日历',
          icon: $r('sys.symbol.calendar'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.currentIndex = 1;
                this.indicatorScale = { x: 1.3, y: 0.7 } as Scale;
              })
              setTimeout(() => {
                animateTo({ duration: 400, curve: curves.springMotion() }, () => {
                  this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
                })
              }, 150)
            } else {
              this.currentIndex = 1;
            }
            this.tabsController.changeIndex(1);
          }
        })

        // 中间按钮 (Add)
        Column() {
          Column() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(this.smartHandMode !== 'center' ? 22 : 28)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
              .rotate({ angle: this.addButtonAngle })
          }
          .width(this.smartHandMode !== 'center' ? 36 : 56)
          .height(this.smartHandMode !== 'center' ? 36 : 56)
          .borderRadius(this.smartHandMode !== 'center' ? 18 : 28)
          .linearGradient(this.isNewYearTheme ? {
            angle: 135,
            colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
          } : (this.showVipTheme ? {
            angle: 135,
            colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
          } : {
            angle: 0,
            colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]]
          }))
          .backgroundColor(Color.Transparent)
          .justifyContent(FlexAlign.Center)
          .shadow({ radius: 10, color: this.isNewYearTheme ? '#40FF2400' : (this.showVipTheme ? '#40E6C07B' : '#40007AFF'), offsetY: 6 })
          .animation({ duration: this.isAnimationEnabled ? 300 : 0 })
          .scale({ x: this.addButtonScale, y: this.addButtonScale })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              if (this.isAnimationEnabled && this.isPointLightEnabled) {
                animateTo({ duration: 100, curve: Curve.Sharp }, () => {
                  this.addButtonScale = 0.8;
                });
                this.addButtonLightSource = hdsEffect.PointLightSourceType.SOFT;
              }
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              animateTo({ duration: 400, curve: Curve.Friction }, () => {
                this.addButtonScale = 1.0;
              });
              this.addButtonLightSource = hdsEffect.PointLightSourceType.NONE;
            }
          })
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.addButtonLightSource,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER // Add button is solid circle, border is fine here
            })
            .buildEffect())
          .onClick(() => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
                this.addButtonAngle += 90;
              })
            } else {
              this.addButtonAngle += 90;
            }
            // slight delay to match the visual feel of "press then action"
            setTimeout(() => {
              this.onAddClick();
            }, 100);
          })
          .margin({ bottom: this.smartHandMode !== 'center' ? 0 : 20 }) // Compact: Center aligned (0 margin); Normal: Protrude (20 margin)
        }
          .width(this.smartHandMode !== 'center' ? 40 : 70)
          .height(56)
        .justifyContent(FlexAlign.Center)

        // 统计
        TabBarItem({
          index: 2,
          currentIndex: this.currentIndex,
          name: '统计',
          icon: $r('sys.symbol.square_grid_2x2'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.currentIndex = 2;
                this.indicatorScale = { x: 1.3, y: 0.7 } as Scale;
              })
              setTimeout(() => {
                animateTo({ duration: 400, curve: curves.springMotion() }, () => {
                  this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
                })
              }, 150)
            } else {
              this.currentIndex = 2;
            }
            this.tabsController.changeIndex(2);
          }
        })

        // 我的
        TabBarItem({
          index: 3,
          currentIndex: this.currentIndex,
          name: '我的',
          icon: $r('sys.symbol.person'),
          showRedDot: this.hasNewVersion,
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.currentIndex = 3;
                this.indicatorScale = { x: 1.3, y: 0.7 } as Scale;
              })
              setTimeout(() => {
                animateTo({ duration: 400, curve: curves.springMotion() }, () => {
                  this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
                })
              }, 150)
            } else {
              this.currentIndex = 3;
            }
            this.tabsController.changeIndex(3);
          }
        })
      }
    }
    .width(this.isTabBarCollapsed ? '56vp' :
      (this.smartHandMode !== 'center' ? '220vp' : // Ultra-Compact Width
        (this.isWide ? (this.isSplitViewEnabled ? 'calc(50% - 24vp)' : '60%') : '92%')))
    .height(56) // Restored to 56
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(28) // Half of 56
    .shadow({ radius: 16, color: 'rgba(0,0,0,0.08)', offsetY: 4 })
    .justifyContent(FlexAlign.SpaceAround)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4 })
    .margin({
      bottom: this.getUIContext().px2vp(this.bottomRectHeight) + 8,
      left: this.isTabBarCollapsed ?
        (this.collapseSide === 'left' ? '12vp' :
          (this.collapseSide === 'right' ? 'calc(100% - 68vp)' : // 56 + 12
            (this.isWide ? (this.isSplitViewEnabled ? 'calc(25% - 28vp)' : 'calc(50% - 28vp)') : 'calc(50% - 28vp)'))) : // Center Collapsed
        // Expanded Logic
        (this.smartHandMode === 'left' ? '12vp' :
          (this.smartHandMode === 'right' ?
            (this.isWide && this.isSplitViewEnabled ? 'calc(50% - 232vp)' : 'calc(100% - 232vp)') : // 220 + 12
            (this.isWide ? (this.isSplitViewEnabled ? '12vp' : '20%') : '4%')))
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]) // 延伸到导航区域
    .opacity(this.tabBarVisible ? 1 : 0) // 透明度动画
    .translate({ y: this.tabBarVisible ? 0 : 100 }) // 平移动画
    .scale({ x: this.tabBarScale, y: this.tabBarScale })
    .animation({ duration: 400, curve: curves.springMotion(0.4, 0.8) }) // 动画效果 - 加快速度
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionEnd((event: GestureEvent) => {
          if (!this.isTabBarCollapsed) {
            if (event.offsetX > 50) {
              animateTo({ duration: 500, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.collapseSide = 'right';
                this.isTabBarCollapsed = true;
                this.tabBarScale = 0.95;
              })
              setTimeout(() => { animateTo({ duration: 400, curve: curves.springMotion() }, () => { this.tabBarScale = 1.0 }) }, 200);
            } else if (event.offsetX < -50) {
              animateTo({ duration: 500, curve: curves.springMotion(0.4, 0.8) }, () => {
                this.collapseSide = 'left';
                this.isTabBarCollapsed = true;
                this.tabBarScale = 0.95;
              })
              setTimeout(() => { animateTo({ duration: 400, curve: curves.springMotion() }, () => { this.tabBarScale = 1.0 }) }, 200);
            }
          }
        })


    )

  }

  @Builder PlaceholderBuilder() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(120)
        .height(120)
        .borderRadius(30)
        .margin({ bottom: 24 })

      Text('记得订阅')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      Text('在左侧选择功能开始使用')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('50%')
    .height('100%')
    .margin({ left: '50%' })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(this.isNewYearTheme ? BlurStyle.NONE : BlurStyle.Thin) // 新年主题下完全透明，普通模式保留微弱模糊感
    .opacity(this.placeholderOpacity)
    .hitTestBehavior(this.isWide && this.isSplitViewEnabled && this.pageStack.size() === 0 ? HitTestMode.Default : HitTestMode.None)
  }

  // 同步数据方法
  async syncData() {
    if (this.isRotating) return;
    this.isRotating = true;
    this.rotateAngle += 360;
    AppStorage.setOrCreate('isSyncing', true);
    SubscriptionRepository.getInstance().syncWithCloud();
    setTimeout(() => {
      this.isRotating = false;
      AppStorage.setOrCreate('isSyncing', false);
    }, 800);
  }

  @Builder TitleBarOverlayBuilder() {
    Row({ space: 8 }) {
      Blank()

      if (this.currentIndex === 0) {
        // 提醒管理按钮
        HeaderActionButton({
          icon: $r('sys.symbol.bell'),
          action: () => {
            getContext(this).eventHub.emit('openReminderSheet');
          }
        })

        // 手动分享按钮
        HeaderActionButton({
          icon: $r('sys.symbol.share'),
          action: () => {
            if (!this.isLoggedIn) {
              if (this.isWide && this.isSplitViewEnabled) {
                this.pageStack.removeByName('Login');
                this.pageStack.pushPathByName('Login', null);
              } else {
                this.showLoginSheet = true;
              }
              return;
            }
            HarmonyShareManager.getInstance().activeShare();
          }
        })

        // 刷新按钮 (旋转)
        HeaderActionButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          angle: this.rotateAngle,
          action: () => {
            this.syncData();
          }
        })
      } else if (this.currentIndex === 1) {
        // 日历页面帮助按钮
        HeaderActionButton({
          icon: $r('sys.symbol.questionmark_circle'),
          action: () => {
            getContext(this).eventHub.emit('openCalendarHelp');
          }
        })
      } else if (this.currentIndex === 2) {
        // 统计页面刷新按钮 (旋转)
        HeaderActionButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          angle: this.rotateAngle,
          action: () => {
            this.syncData();
          }
        })
      }
    }
    .width('100%')
    .height(56) // Match minimal title bar height
    .alignItems(VerticalAlign.Center)
    .padding({ right: 16 })
    .hitTestBehavior(HitTestMode.Transparent) // Allow clicks on Blank() to pass through
  }

  // 构建标题栏配置
  getTitleBarOptions(): HdsNavigationTitleBarOptions {
    let mainTitle = '订阅概览';
    if (this.currentIndex === 1) {
      mainTitle = '订阅日历';
    } else if (this.currentIndex === 2) {
      mainTitle = '统计分析';
    } else if (this.currentIndex === 3) {
      mainTitle = '我的';
    }

    // Construct object step-by-step to avoid untyped object literal errors
    let title: Record<string, Object> = { 'mainTitle': mainTitle };
    let content: Record<string, Object> = {
      'title': title,
      'stackBuilder': (): void => this.TitleBarOverlayBuilder()
    };
    let options: Record<string, Object> = {
      'avoidLayoutSafeArea': true,
      'enableComponentSafeArea': false,
      'content': content
    };

    return options as Object as HdsNavigationTitleBarOptions;
  }

  @Builder NavigationBuilder(name: string, param: Object) {
    if (name === 'AddSubscription') {
      // Placeholder for potential AddSubscription navigation
    } else if (name === 'IconLibraryPage') {
      IconLibraryPage()
    }
  }



  @Builder
  PasswordLockSheetBuilder() {
    PasswordLockPage({
      mode: 'verify',
      onSuccess: () => {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.isLocked = false;
        });
      }
    })
    // Let PasswordLockPage handle background with blur
      .backgroundColor(Color.Transparent)
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // Wrapper for blur effect
      Stack({ alignContent: Alignment.BottomStart }) {
        // 1. New Year Watermark (Layer 0 - Above background color, below content)
        // 1. Background Watermark (Layer 0)
        BackgroundWatermark()

        // Background / Base Layer
        Row() {
          // --- Main Content Area ---
          HdsNavigation(this.pageStack) {
            Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
              TabContent() { HomeView({ isVisible: this.currentIndex === 0 }) }.tabBar(null).backgroundColor(Color.Transparent)
              TabContent() { CalendarView({ isVisible: this.currentIndex === 1 }) }.tabBar(null).backgroundColor(Color.Transparent)
              TabContent() { StatsView({ isVisible: this.currentIndex === 2 }) }.tabBar(null).backgroundColor(Color.Transparent)
              TabContent() { SettingsView({ isVisible: this.currentIndex === 3 }) }.tabBar(null).backgroundColor(Color.Transparent)
            }
            .backgroundColor(Color.Transparent)
            .barHeight(0)
            .scrollable(false)
            .onAppear(() => {
              // 状态同步已经在 refreshWideStatus 中处理，无需在此重复异步读取
            })
            .animationDuration(this.animationDuration)
            .onChange((index: number) => {
              this.currentIndex = index;
              // 只有非内部跳转时，才在切换 Tab 时自动关闭详情页
              if (!this.isInternalRedirect && this.isDetailVisible) {
                this.isDetailVisible = false;
              }
            })
            .width('100%')
            .height('100%')
          }
          .navBarWidth('50%')
          .navDestination(this.NavigationBuilder)
          .mode(this.isSplitViewEnabled ? NavigationMode.Auto : NavigationMode.Stack)
          .layoutWeight(1)
          .height('100%')
          .hideBackButton(true)
          .titleBar(undefined)
          .titleMode(HdsNavigationTitleMode.MINI)
          .hideTitleBar(true)
          .hideToolBar(true)
          .backgroundColor(Color.Transparent) // Transparent to show watermark
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')

        // Right panel placeholder (only render in wide split mode)
        if (this.isWide && this.isSplitViewEnabled) {
          this.PlaceholderBuilder()
        }

        // --- Floating TabBar (Always Visible) ---
        this.CustomFloatingTabBar()

        // Global Detail Overlay
        // 移除 currentIndex === 0 的限制，让它能在 Index 层面统一展示（反正跳转后已经在首页了）
        // 详情页浮层 (全局)
        if (this.isDetailVisible && this.detailData) {
          SubscriptionDetailOverlay({ data: this.detailData })
            .zIndex(1000)
        }

        // 查询结果浮层 (全局)
        if (this.isQueryResultsVisible) {
          QueryResultsOverlay()
            .zIndex(1001)
        }
      }
      .width('100%')
      .height('100%')
      .blur(this.isLocked ? 80 : 0) // Apply privacy blur when locked
      .animation({ duration: 300 })





      Column()
        .bindSheet($$this.showLoginSheet, this.LoginSheetBuilder(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          preferType: SheetType.BOTTOM,
          title: { title: '登录', subtitle: '使用华为账号登录' }
        })
      Column()
        .bindSheet($$this.showImportSheet, this.ImportSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          preferType: SheetType.BOTTOM,
        })
      Column()
        .bindSheet($$this.showAddSheet, this.AddMenuSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          title: { title: '添加订阅' },
          preferType: SheetType.BOTTOM,
        })
      Column()
        .bindSheet($$this.isLocked, this.PasswordLockSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: false,
          showClose: false,
          backgroundColor: Color.Transparent,
          maskColor: Color.Transparent,
          preferType: SheetType.BOTTOM,

          shouldDismiss: ((sheetDismiss: SheetDismiss) => {
            // Prevent dismissal by doing nothing
            hilog.info(0x0000, 'Index', 'Attempt to dismiss lock sheet blocked');
          })
        })
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r('app.color.page_background'))

  }

  @Builder ImportSheetBuilder() {
    ImportSheet({
      isShow: $showImportSheet,
      importData: $localImportSubs,
      onCancel: () => {
        this.showImportSheet = false;
        AppStorage.setOrCreate('importData', null);
      },
      onImport: async () => {
        const loading = promptAction.showToast({ message: '正在导入...' });
        let importedCount = 0;
        const repo = SubscriptionRepository.getInstance();
        for (const item of this.localImportSubs) {
          await repo.upsert(item, true); // skipRefresh: true
          importedCount++;
        }
        // 批量更新完成后，统一触发一次快照更新和全局刷新
        await repo.updateWidgetSnapshotSync('batch_import');
        getContext(this).eventHub.emit('refreshData');
        this.showImportSheet = false;
        promptAction.showToast({ message: `成功导入 ${importedCount} 条数据` });
        AppStorage.setOrCreate('importData', null);
      }
    })
  }





  @Builder LoginSheetBuilder() {
    LoginSheet({
      isShow: this.showLoginSheet,
      onSuccess: () => {
        this.showLoginSheet = false;
        promptAction.showToast({ message: '登录成功' });
      },
      onClose: () => {
        this.showLoginSheet = false;
      }
    })
  }

  onBackPress(): boolean | void {
    // 0. 如果详情页显示，优先关闭详情页
    if (this.isDetailVisible) {
      AppStorage.setOrCreate('isDetailClosing', true);
      animateTo({
        duration: this.isAnimationEnabled ? this.animationDuration : 0,
        curve: Curve.FastOutSlowIn
      }, () => {
        this.isDetailVisible = false;
      })
      setTimeout(() => {
        AppStorage.setOrCreate('isDetailClosing', false);
      }, this.isAnimationEnabled ? this.animationDuration + 50 : 50);
      return true;
    }

    // 1. 如果页面栈有数据，优先手动弹出
    if (this.pageStack.size() > 0) {
      this.pageStack.pop();
      return true;
    }

    // 2. 如果当前不在首页，则返回首页
    if (this.currentIndex !== 0) {

      this.currentIndex = 0;
      return true;
    }

    // 3. 如果已经在首页且页面栈没有其他页面，则弹出退出确认
    this.showExitConfirm();
    return true;
  }

  showExitConfirm() {
    AlertDialog.show({
      title: '退出应用',
      message: '确定要退出记得订阅吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      offset: { dx: 0, dy: -20 },
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出',
        fontColor: Color.Red,
        action: () => {
          // 退出应用
          const context = getContext(this) as common.UIAbilityContext;
          context.terminateSelf();
        }
      }
    })
  }
}

@Component
struct TabBarItem {
  @Prop index: number;
  @Prop currentIndex: number;
  @Prop name: string;
  @Prop icon: Resource;
  @Prop showRedDot: boolean = false;
  onSelect: () => void = () => {};
  @State scaleVal: number = 1.0;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @Prop indicatorScale: Scale = { x: 1.0, y: 1.0 };
  @Prop isCompact: boolean = false;

  build() {
    Column() {
      // 全包式胶囊背景 (56vp 高度)
      Stack({ alignContent: Alignment.Center }) {
        if (this.currentIndex === this.index) {
          // 2.0 优化版：更纯净的"水滴"质感，降低色调干扰
          Stack() {
            // 1. 晶透基底：极淡的背景，主要靠模糊撑起质感
            Column()
              .width('100%')
              .height('100%')
              // 降低不透明度：0.12 -> 0.08，避免显脏
              .backgroundColor(this.isNewYearTheme ? 'rgba(255, 215, 0, 0.1)' : (this.showVipTheme ? 'rgba(255, 215, 0, 0.08)' : 'rgba(255, 255, 255, 0.08)'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THIN) // Thin 比 ULTRA_THIN 稍重一点，增强玻璃感
              .borderRadius(28)

            // 2. 边缘光晕：更柔和的边界
            Column()
              .width('100%')
              .height('100%')
              .border({
                width: 0.5,
                // 降低描边不透明度：0.3/0.4 -> 0.2，更隐形
                color: this.isNewYearTheme ? 'rgba(255, 215, 0, 0.25)' : (this.showVipTheme ? 'rgba(255, 230, 200, 0.25)' : 'rgba(255, 255, 255, 0.2)'),
                radius: 28
              })

            // 3. 表面流光：大幅降低梯度，仅保留顶部微弱反光
            Column()
              .width('100%')
              .height('100%')
              .linearGradient({
                direction: GradientDirection.Top,
                colors: [
                  // 顶部高光减弱：0.4/0.5 -> 0.25，防止过曝
                  [this.isNewYearTheme ? 'rgba(255, 255, 255, 0.3)' : 'rgba(255, 255, 255, 0.25)', 0.0],
                  ['rgba(255, 255, 255, 0.0)', 0.4],
                  ['rgba(255, 255, 255, 0.0)', 1.0]
                ]
              })
              .borderRadius(28)
          }
          .width('100%')
          .height('100%')
          .borderRadius(28)
          // 4. 移除原有阴影，由 HDS SOFT 光效提供更自然的景深感，避免颜色叠加产生的“莫名光晕”
          .hitTestBehavior(HitTestMode.Transparent)
          .geometryTransition('tab_indicator')
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.isPointLightEnabled ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        }

        Column() {
          SymbolGlyph(this.icon)
            .fontSize(this.isCompact ? 18 : 22)
            .fontColor([this.currentIndex === this.index ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary')])
            .scale({ x: (this.currentIndex === this.index ? 1.1 : 1.0) * this.scaleVal, y: (this.currentIndex === this.index ? 1.1 : 1.0) * this.scaleVal })
            .fontWeight(this.currentIndex === this.index ? FontWeight.Bold : FontWeight.Normal)
            .animation({ duration: 350, curve: curves.springMotion(0.4, 0.8) })

          Text(this.name)
            .fontSize(this.isCompact ? 8 : 9)
            .fontColor(this.currentIndex === this.index ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary'))
            .margin({ top: 1 })
            .opacity(this.currentIndex === this.index ? 1.0 : 0.6)
            .fontWeight(this.currentIndex === this.index ? FontWeight.Medium : FontWeight.Normal)
        }
        .justifyContent(FlexAlign.Center)

        if (this.showRedDot) {
          Circle({ width: 6, height: 6 })
            .fill(Color.Red)
            .position({ right: 6, top: 12 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.isCompact ? 32 : 54)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Transparent)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          animateTo({ duration: 100, curve: Curve.Sharp }, () => {
            this.scaleVal = 0.9;
          });
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 400, curve: curves.springMotion() }, () => {
          this.scaleVal = 1.0;
        });
      }
    })
    .onClick(() => {
      this.onSelect();
    })
  }
}


@Component
struct HeaderActionButton {
  @Require @Prop icon: Resource;
  @Require action: () => void = () => {};
  @Prop angle: number = 0;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @State isPressed: boolean = false;
  @State lightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  build() {
    Button() {
      SymbolGlyph(this.icon)
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
        .rotate({ angle: this.angle })
        .animation({ duration: 800, curve: Curve.FastOutSlowIn })


    }
    .width(40)
    .height(40)
    .type(ButtonType.Circle)
    .backgroundColor(Color.Transparent)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.lightSource,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .onTouch((event: TouchEvent) => {
      if (this.isPointLightEnabled) {
        if (event.type === TouchType.Down) {
          this.isPressed = true;
          this.lightSource = hdsEffect.PointLightSourceType.BRIGHT;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.isPressed = false;
          this.lightSource = hdsEffect.PointLightSourceType.NONE;
        }
      }
    })
    .onClick(() => {
      this.action();
    })
  }
}
