import { PasswordLockPage } from '../view/PasswordLockPage';
import { HomeView } from '../view/HomeView';
import { SubscriptionDetailOverlay } from '../view/SubscriptionDetailOverlay';
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
import { hdsEffect, hdsMaterial, HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationMenuItemOptions, HdsNavigationTitleMode, HdsNavigationAttribute,
  HdsTabs,
  HdsTabsController,
  HdsTabsAttribute,
  HdsBarStyle,
  bleedIconStyle } from '@kit.UIDesignKit';
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
import { commonEventManager, deviceInfo } from '@kit.BasicServicesKit';

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
  // Track the current tab mode (4 tabs or 5 tabs) to handle transitions
  private is4Tabs: boolean = true;

  @StorageLink('currentIndex') currentIndex: number = 0;
  @State showLoginSheet: boolean = false;
  @StorageLink('isHdsTabsEnabled') @Watch('onHdsTabsChange') isHdsTabsEnabled: boolean = true;
  @StorageLink('targetAction') @Watch('onTargetActionChange') targetAction: string = '';
  @StorageLink('hdsTabLightSource') hdsTabLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.BRIGHT;

  onTabBarVisibleChange() {
    if (this.isPointLightEnabled) {
      if (this.tabBarVisible) {
        animateTo({ duration: 400, curve: Curve.FastOutSlowIn }, () => {
          this.hdsTabLightSource = hdsEffect.PointLightSourceType.BRIGHT;
          // 移除 addButtonLightSource，保持加号按钮初始熄灭
        });
      } else {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.hdsTabLightSource = hdsEffect.PointLightSourceType.NONE;
          this.addButtonLightSource = hdsEffect.PointLightSourceType.NONE;
        });
      }
    } else {
      this.hdsTabLightSource = hdsEffect.PointLightSourceType.NONE;
      this.addButtonLightSource = hdsEffect.PointLightSourceType.NONE;
    }
  }

  onHdsTabsChange() {
    // Re-sync currentIndex when HdsTabs toggle changes to avoid index mismatch
    // HdsTabs uses 5 tabs when split view is disabled (index 2 is Add)
    // Regular Tabs uses 4 tabs (Add is floating)
    // IMPORTANT: Wait for next tick to ensure state is stable before switching index
    setTimeout(() => {
      if (this.isHdsTabsEnabled) {
        // Switching TO HdsTabs
        // Let checkTabModeTransition handle the logic and state update based on current layout
        this.checkTabModeTransition();
      } else {
        // Switching FROM HdsTabs TO CustomTabs (always 4 tabs)
        // If we were in 5-tabs mode, we need to adjust 5 -> 4
        if (!this.is4Tabs) {
           if (this.currentIndex === 3) this.currentIndex = 2;
           else if (this.currentIndex === 4) this.currentIndex = 3;
           this.is4Tabs = true;
        }
      }
    }, 0);
  }
  @StorageLink('tabBarVisible') @Watch('onTabBarVisibleChange') tabBarVisible: boolean = true; // Tab 栏可见性
  @StorageLink('animationDuration') animationDuration: number = 0;

  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') @Watch('onTabBarVisibleChange') isPointLightEnabled: boolean = true;

  // 全局详情页状态
  @StorageLink('isDetailVisible') isDetailVisible: boolean = false;
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
  @State hdsBarStyle: HdsBarStyle = HdsBarStyle.COLLAPSE; // HdsTabs 状态：展开或折叠

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
            this.currentIndex = 0;
            this.indicatorScale = { x: 1.0, y: 1.0 } as Scale;
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
      } else if (this.targetAction === 'Login') {
        hilog.info(0xFEED, 'Index', 'Handling Login action');
        AppStorage.setOrCreate('targetAction', '');
        if (!this.isLoggedIn) {
          if (this.isWide && this.isSplitViewEnabled) {
            this.pageStack.removeByName('Login');
            this.pageStack.pushPathByName('Login', null);
          } else {
            this.showLoginSheet = true;
          }
        }
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
      AppStorage.setOrCreate('windowWidthVp', widthVp);

      if (this.isWide !== newIsWide) {
        this.isWide = newIsWide;
        AppStorage.setOrCreate('isWide', this.isWide);
      }

      // 优化：不再使用异步 load，直接从 AppStorage 获取
      // EntryAbility 已经同步 load 过 preference 到 AppStorage 了
      let prefEnabled = AppStorage.get<boolean>('isSplitViewEnabled');
      
      // Fallback to false if still undefined
      const isSplitEnabled = prefEnabled ?? false;

      if (this.isWide) {
        if (isSplitEnabled && !this.isSplitViewEnabled) {
          this.isSplitViewEnabled = true;
        } else if (!isSplitEnabled && this.isSplitViewEnabled) {
          this.isSplitViewEnabled = false;
        }
      } else {
        if (this.isSplitViewEnabled) {
          this.isSplitViewEnabled = false;
        }
      }

      // 状态同步后，立即刷新占位图可见性
      this.updatePlaceholderVisibility();
      this.checkTabModeTransition();
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
    // Check App Lock - 修正：优先使用 AppStorage 同步获取的状态，全局配置已在 EntryAbility 中读取
    const hasLock = AppStorage.get<boolean>('hasAppLock');
    this.isLocked = hasLock ?? false;

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
        
        // 当屏幕尺寸发生变化（如展开/折叠）时，强制重新读取一次平行视界配置
        // 确保配置能及时生效，而不需要点击触发
        PreferenceUtil.getInstance().loadSplitViewEnabled().then((enabled) => {
           if (this.isWide) {
             this.isSplitViewEnabled = enabled;
           }
        });
      });
    } catch (e) {}

    // 0. 会员状态已在 EntryAbility 中预加载，此处只需检查过期并移除遮罩
    
    // Initialize memory with saved state
    this.refreshWideStatus(); // 首次加载时同步物理状态
    
    // Check for updates silently 被挪至 EntryAbility.ets

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

    // 注意：原本的云端自动静默登录与数据同步逻辑，现已移动至 EntryAbility.ets 处理

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

    // 初始同步一次点光源状态，防止启动时的状态真空期
    this.onTabBarVisibleChange();
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

  updateTabBarVisibility(): void {
    // Unified TabBar visibility logic:
    // Hide TabBar when stack is not empty, UNLESS we are in split-screen mode on a wide screen.
    setTimeout(() => {
      let visible = true;
      if (this.isWide && this.isSplitViewEnabled) {
        visible = true;
      } else {
        visible = this.pageStack.size() === 0;
      }
      this.tabBarVisible = visible;
    }, 0);
  }

  onSplitViewChange(): void {
    this.updatePlaceholderVisibility();
    this.updateTabBarVisibility();
    this.checkTabModeTransition();
  }

  checkTabModeTransition() {
    // Only applies if HdsTabs is enabled. Custom Tabs always use 4 tabs.
    if (!this.isHdsTabsEnabled) {
      this.is4Tabs = true; // Reset state for custom tabs
      return;
    }
    
    // Determine current mode
    // 4 Tabs: Split View Enabled OR Narrow Screen
    // 5 Tabs: Split View Disabled AND Wide Screen
    const currentIs4Tabs = this.isSplitViewEnabled || !this.isWide;
    
    if (this.is4Tabs !== currentIs4Tabs) {
      hilog.info(0x0000, 'Index', `Tab Mode Transition: ${this.is4Tabs ? '4 -> 5' : '5 -> 4'}`);
      
      if (this.is4Tabs && !currentIs4Tabs) {
        // 4 -> 5 Transition (Add button inserted at index 2)
        // Original: 0, 1, 2(Stats), 3(Settings)
        // New: 0, 1, 2(Add), 3(Stats), 4(Settings)
        if (this.currentIndex === 2) {
          this.currentIndex = 3;
        } else if (this.currentIndex === 3) {
          this.currentIndex = 4;
        }
      } else if (!this.is4Tabs && currentIs4Tabs) {
        // 5 -> 4 Transition (Add button removed from index 2)
        // Original: 0, 1, 2(Add), 3(Stats), 4(Settings)
        // New: 0, 1, 2(Stats), 3(Settings)
        if (this.currentIndex === 3) {
          this.currentIndex = 2;
        } else if (this.currentIndex === 4) {
          this.currentIndex = 3;
        }
      }
      
      this.is4Tabs = currentIs4Tabs;
    }
  }

  onAddClick(): void {
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
  @StorageLink('addButtonLightSource') addButtonLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE; // 初始为 NONE
  private tabsController: HdsTabsController = new HdsTabsController();

  getIndicatorId(): string {
    return 'tab_indicator_' + (this.isHdsTabsEnabled ? (this.is4Tabs ? 'hds4' : 'hds5') : 'custom');
  }

  @Builder
  HdsTabBuilder(index: number, name: string, icon: Resource, selectedIcon?: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      // 选中背景圈
      if (this.currentIndex === index) {
        Column()
          .width(this.hdsBarStyle === HdsBarStyle.EXPAND ? 48 : 64)
          .height(48) // 稍微统一高度为 48
          .borderRadius(40)
          .backgroundColor(this.isNewYearTheme ? 'rgba(230, 0, 0, 0.1)' : (this.showVipTheme ? 'rgba(255, 215, 0, 0.1)' : 'rgba(10, 89, 247, 0.1)'))
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.hdsTabLightSource,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .geometryTransition(this.getIndicatorId())
          .animation({ curve: curves.springMotion(0.4, 0.84) })
      }

      Column() {
        SymbolGlyph(this.currentIndex === index && selectedIcon ? selectedIcon : icon)
          .fontSize(22)
          .fontColor([this.currentIndex === index ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary')])
          .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
          .scale({ x: this.currentIndex === index ? 1.08 : 1.0, y: this.currentIndex === index ? 1.08 : 1.0 })
          .animation({ duration: 300, curve: Curve.EaseOut })
        Text(name)
          .fontSize(10)
          .margin({ top: 4 })
          .fontColor(this.currentIndex === index ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary'))
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  // 包装构建器，解决 tabBar 传参时的语法和 Context 问题
  @Builder TabBar0() { this.HdsTabBuilder(0, '首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill')) }
  @Builder TabBar1() { this.HdsTabBuilder(1, '日历', $r('sys.symbol.calendar'), $r('sys.symbol.calendar_fill')) }
  @Builder TabBarStats() { this.HdsTabBuilder((this.isSplitViewEnabled || !this.isWide) ? 2 : 3, '统计', $r('sys.symbol.square_grid_2x2'), $r('sys.symbol.square_fill_grid_2x2')) }
  @Builder TabBarSettings() { this.HdsTabBuilder((this.isSplitViewEnabled || !this.isWide) ? 3 : 4, '我的', $r('sys.symbol.person'), $r('sys.symbol.person_fill')) }

  @Builder TabBarAdd() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
          .fontWeight(FontWeight.Bold)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.onAddClick();
    })
    .hitTestBehavior(HitTestMode.Block) // Block touch propagation to prevent HdsTabs switch
  }

  @Builder
  AddMenuSheetBuilder() {
    AddMenuSheet()
  }

  @Builder
  MiniBarBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.hdsBarStyle === HdsBarStyle.COLLAPSE) {
        // 折叠态：仅显示一个 + 号开关
        this.MiniBarItemBuilder($r('sys.symbol.plus'), undefined, () => {
          if (this.isAnimationEnabled) {
            animateTo({ curve: curves.springMotion(0.4, 0.82) }, () => {
              this.hdsBarStyle = HdsBarStyle.EXPAND;
            });
          } else {
            this.hdsBarStyle = HdsBarStyle.EXPAND;
          }
        })
      } else {
        // 展开态：包含 [收起开关(箭头)] + [四个功能图标]
        // 彻底压减间隙，收起图标专门调窄，解决“比例失调”问题
        Row() {
          // 1. 收起开关 (宽度调窄至 32)
          this.MiniBarItemBuilder($r('sys.symbol.chevron_right'), undefined, () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.82) }, () => {
                this.hdsBarStyle = HdsBarStyle.COLLAPSE;
              });
            } else {
              this.hdsBarStyle = HdsBarStyle.COLLAPSE;
            }
          }, 32)

          // 功能图标区域：使用 Scroll 包装，防止紧凑
          Scroll() {
            Row() {
              this.MiniBarItemBuilder($r('sys.symbol.doc_text_badge_clock'), '服务', () => {
                const params: Record<string, Object> = { 'initialType': 'subscription' };
                this.pageStack.pushPathByName('AddSubscription', params);
              })

              this.MiniBarItemBuilder($r('sys.symbol.bag'), '团购', () => {
                const params: Record<string, Object> = { 'initialType': 'groupBuy' };
                this.pageStack.pushPathByName('AddSubscription', params);
              })

              this.MiniBarItemBuilder($r('sys.symbol.shield_checkered'), '保修', () => {
                const params: Record<string, Object> = { 'initialType': 'warranty' };
                this.pageStack.pushPathByName('AddSubscription', params);
              })

              this.MiniBarItemBuilder($r('sys.symbol.creditcard'), '卡证', () => {
                const params: Record<string, Object> = { 'initialType': 'card' };
                this.pageStack.pushPathByName('AddSubscription', params);
              })

              this.MiniBarItemBuilder($r('sys.symbol.star'), '推荐', () => {
                this.pageStack.removeByName('SubscriptionMarketplace');
                this.pageStack.pushPathByName('SubscriptionMarketplace', null);
              })
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .layoutWeight(1)
          .margin({ left: 4 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 })),
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
        ))
      }
    }
    .width(this.hdsBarStyle === HdsBarStyle.EXPAND ? 'auto' : 56) // 折叠时固定宽度
    .height('100%')
  }

  @Builder
  MiniBarItemBuilder(icon: Resource, label?: string, action: () => void = () => {}, customWidth: number = 48) {
    Column() {
      // 图标容器
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
        .fontWeight(FontWeight.Bold)

      if (label) {
        Text(label)
          .fontSize(10)
          .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .fontWeight(FontWeight.Medium)
          .margin({ top: 1 })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(customWidth) // 使用自定义宽度，收起按钮为 32，功能按钮为 48
    .height(48)
    .onClick(() => {
      action();
    })
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
          selectedIcon: $r('sys.symbol.house_fill'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.84) }, () => {
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
          selectedIcon: $r('sys.symbol.calendar_fill'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.84) }, () => {
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
                this.addButtonLightSource = hdsEffect.PointLightSourceType.BRIGHT;
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
          selectedIcon: $r('sys.symbol.square_fill_grid_2x2'),
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.84) }, () => {
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
          selectedIcon: $r('sys.symbol.person_fill'),
          showRedDot: this.hasNewVersion,
          indicatorScale: this.indicatorScale,
          isCompact: this.smartHandMode !== 'center',
          onSelect: () => {
            if (this.isAnimationEnabled) {
              animateTo({ duration: 400, curve: curves.springMotion(0.4, 0.84) }, () => {
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

    return {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      content: {
        title: { mainTitle: mainTitle },
        stackBuilder: (): void => this.TitleBarOverlayBuilder()
      }
    } as HdsNavigationTitleBarOptions;
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
            if (this.isHdsTabsEnabled) {
              if (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) {
                // Determine 4 Tabs Mode (Split View / Wide Screen OR Phone / Narrow Screen)
                // Use 4 Tabs if:
                // 1. Split View is enabled (Wide Screen with Sidebar)
                // 2. Not Wide Screen (Phone Mode) - Default 4 Tabs behavior
                if (this.isSplitViewEnabled || !this.isWide) {
                  // --- 4 Tabs Mode ---
                  HdsTabs({
                    index: this.currentIndex,
                    controller: this.tabsController,
                    barPosition: BarPosition.End
                  }) {
                    TabContent() {
                      HomeView({ isVisible: this.currentIndex === 0 })
                    }
                    .tabBar(this.TabBar0)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      CalendarView({ isVisible: this.currentIndex === 1 })
                    }
                    .tabBar(this.TabBar1)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      StatsView({ isVisible: this.currentIndex === 2 })
                    }
                    .tabBar(this.TabBarStats)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      SettingsView({ isVisible: this.currentIndex === 3 })
                    }
                    .tabBar(this.TabBarSettings)
                    .backgroundColor(Color.Transparent)
                  }
                  .barPosition(BarPosition.End)
                  .vertical(false)
                  .barOverlap(true)
                  .barBackgroundColor(Color.Transparent)
                  .barFloatingStyle({
                    barSideMargin: 24,
                    barBottomMargin: this.getUIContext().px2vp(this.bottomRectHeight) + 8,
                    // barOpacity:0,
                    adaptToHandedness: this.isSmartGestureEnabled && !this.isWide, // Enable single-hand mode only on narrow screens
                    lightColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')),
                    miniBar: {
                      miniBarBuilder: () => {
                        this.MiniBarBuilder()
                      },
                      miniBarStyle: this.hdsBarStyle,
                      onBarStyleChange: (miniStyle: HdsBarStyle, tabStyle: HdsBarStyle, miniBarWidth: number,
                        tabBarWidth: number,) => {
                        this.hdsBarStyle = miniStyle;
                      },
                    },
                    systemMaterialEffect: {
                      materialType: hdsMaterial.MaterialType.IMMERSIVE,
                      materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
                    }
                  })
                  .animationDuration(0)
                  .scrollable(false)
                  .onChange((index: number) => {
                    const self = this;
                    if (this.isAnimationEnabled) {
                      animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
                        self.currentIndex = index;
                      })
                    } else {
                      self.currentIndex = index;
                    }
                    if (!self.isInternalRedirect && self.isDetailVisible) {
                      self.isDetailVisible = false;
                    }
                  })
                  .width('100%')
                  .height('100%')
                  .key('hds_tabs_4') // Force unique key for 4-tabs mode
                } else {
                  // --- 5 Tabs Mode (Wide Screen without Split View) ---
                  HdsTabs({
                    index: this.currentIndex,
                    controller: this.tabsController,
                    barPosition: BarPosition.End
                  }) {
                    TabContent() {
                      HomeView({ isVisible: this.currentIndex === 0 })
                    }
                    .tabBar(this.TabBar0)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      CalendarView({ isVisible: this.currentIndex === 1 })
                    }
                    .tabBar(this.TabBar1)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      // Placeholder for Add Button action
                      Column().width('100%').height('100%')
                    }
                    .tabBar(this.TabBarAdd)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      StatsView({ isVisible: this.currentIndex === 3 })
                    }
                    .tabBar(this.TabBarStats)
                    .backgroundColor(Color.Transparent)

                    TabContent() {
                      SettingsView({ isVisible: this.currentIndex === 4 })
                    }
                    .tabBar(this.TabBarSettings)
                    .backgroundColor(Color.Transparent)
                  }
                  .barPosition(BarPosition.End)
                  .vertical(false)
                  .barOverlap(true)
                  .barBackgroundColor(Color.Transparent)
                  .barFloatingStyle({
                    barSideMargin: 24,
                    barBottomMargin: this.getUIContext().px2vp(this.bottomRectHeight) + 8,
                    adaptToHandedness: this.isSmartGestureEnabled,
                    lightColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')),
                    // No miniBar in 5-tabs mode
                    systemMaterialEffect: {
                      materialType: hdsMaterial.MaterialType.IMMERSIVE,
                      materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
                    }
                  })
                  .animationDuration(0)
                  .scrollable(false)
                  .onChange((index: number) => {
                    const self = this;

                    // Note: Index 2 click is now handled by onClick in TabBarAdd to prevent tab switch flicker.
                    // However, if onChange still fires for index 2, we must ensure we don't get stuck there.
                    if (index === 2) {
                       self.onAddClick();
                       // Fallback: If interception failed, force revert
                       setTimeout(() => {
                         self.tabsController.changeIndex(self.currentIndex);
                       }, 0);
                       return;
                    }

                    if (this.isAnimationEnabled) {
                      animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
                        self.currentIndex = index;
                      })
                    } else {
                      self.currentIndex = index;
                    }
                    if (!self.isInternalRedirect && self.isDetailVisible) {
                      self.isDetailVisible = false;
                    }
                  })
                  .width('100%')
                  .height('100%')
                  .key('hds_tabs_5') // Force unique key for 5-tabs mode
                }
              } else {
                this.CustomFloatingTabBar()
              }
            }
          else {
              Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
                TabContent() {
                  HomeView({ isVisible: this.currentIndex === 0 })
                }
                .tabBar(null)
                .backgroundColor(Color.Transparent)

                TabContent() {
                  CalendarView({ isVisible: this.currentIndex === 1 })
                }
                .tabBar(null)
                .backgroundColor(Color.Transparent)

                TabContent() {
                  StatsView({ isVisible: this.currentIndex === 2 })
                }
                .tabBar(null)
                .backgroundColor(Color.Transparent)

                TabContent() {
                  SettingsView({ isVisible: this.currentIndex === 3 })
                }
                .tabBar(null)
                .backgroundColor(Color.Transparent)
              }
              .backgroundColor(Color.Transparent)
              .barHeight(0)
              .scrollable(false)
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

        // --- Floating TabBar (Only visible when HdsTabs is disabled) ---
        if (!this.isHdsTabsEnabled) {
          this.CustomFloatingTabBar()
        }

        // Global Detail Overlay
        if (this.isDetailVisible && this.detailData) {
          SubscriptionDetailOverlay({ data: this.detailData })
            .zIndex(1000)
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
    // 1. 如果详情页显示，优先关闭详情页
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
  @Prop selectedIcon: Resource | undefined = undefined;
  @Prop showRedDot: boolean = false;
  onSelect: () => void = () => {};
  @State scaleVal: number = 1.0;
  @StorageLink('isPointLightEnabled') @Watch('onVisibleChange') isPointLightEnabled: boolean = true;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @Prop indicatorScale: Scale = { x: 1.0, y: 1.0 };
  @Prop isCompact: boolean = false;
  @StorageLink('tabBarVisible') @Watch('onVisibleChange') tabBarVisible: boolean = true;
  @State itemLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.BRIGHT;

  onVisibleChange() {
    if (this.isPointLightEnabled) {
      if (this.tabBarVisible) {
        animateTo({ duration: 400, curve: Curve.FastOutSlowIn }, () => {
          this.itemLightSource = hdsEffect.PointLightSourceType.BRIGHT;
        });
      } else {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.itemLightSource = hdsEffect.PointLightSourceType.NONE;
        });
      }
    } else {
      this.itemLightSource = hdsEffect.PointLightSourceType.NONE;
    }
  }

  aboutToAppear() {
    this.onVisibleChange();
  }

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
              .backgroundColor(this.isNewYearTheme ? 'rgba(230, 0, 0, 0.1)' : (this.showVipTheme ? 'rgba(255, 215, 0, 0.08)' : 'rgba(255, 255, 255, 0.08)'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THIN) // Thin 比 ULTRA_THIN 稍重一点，增强玻璃感
              .borderRadius(28)

            // 2. 边缘光晕：更柔和的边界
            Column()
              .width('100%')
              .height('100%')
              .border({
                width: 0.5,
                // 降低描边不透明度：0.3/0.4 -> 0.2，更隐形
                color: this.isNewYearTheme ? 'rgba(230, 0, 0, 0.25)' : (this.showVipTheme ? 'rgba(255, 230, 200, 0.25)' : 'rgba(255, 255, 255, 0.2)'),
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
          // 4. 移除原有阴影，由 HDS BRIGHT 光效提供更自然的景深感，避免颜色叠加产生的“莫名光晕”
          .hitTestBehavior(HitTestMode.Transparent)
          .geometryTransition('tab_indicator_custom')
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.itemLightSource,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
        }

        Column() {
          SymbolGlyph(this.currentIndex === this.index && this.selectedIcon ? this.selectedIcon : this.icon)
            .fontSize(this.isCompact ? 18 : 22)
            .fontColor([this.currentIndex === this.index ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary')])
            .scale({ x: (this.currentIndex === this.index ? 1.05 : 1.0) * this.scaleVal, y: (this.currentIndex === this.index ? 1.05 : 1.0) * this.scaleVal })
            .fontWeight(this.currentIndex === this.index ? FontWeight.Bold : FontWeight.Normal)
            .animation({ duration: 350, curve: curves.springMotion(0.4, 0.84) })

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
