import { SubscriptionModel } from '../model/SubscriptionModel';
import { SubscriptionCard } from './SubscriptionCard';
import { NewYearSubscriptionCard } from './NewYearSubscriptionCard';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { DateUtil } from '../utils/DateUtil';
import { prompt, curves, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { EVENT_SYNC_COMPLETED, EVENT_DATA_CHANGED, GlobalBus } from '../utils/GlobalBus';
import { LoginSheet } from './LoginSheet';
import { SubscriptionIcon } from './SubscriptionIcon';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { hdsEffect, HdsNavDestination, HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';

import { ReminderSetupPanel } from './ReminderSetupPanel';
import { LocalIconManager } from '../utils/LocalIconManager';
import { HarmonyShareManager } from '../utils/HarmonyShareManager';
import { commonEventManager } from '@kit.BasicServicesKit';

// 导航参数类型
class AddSubscriptionNavParams {
  initialType: string = 'subscription';
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct HomeView {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('isOnline') isOnline: boolean = true;

  @StorageLink('isSyncing') isSyncing: boolean = false;
  @StorageLink('isLoggedIn') @Watch('onLoggedInChange') isLoggedIn: boolean = false;

  onLoggedInChange() {
    if (this.isLoggedIn) {
      this.loadLocalData();
      this.checkAIConfig();
    }
  }
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = true;
  @StorageProp('isInitialSyncDone') isInitialSyncDone: boolean = false;
  @StorageLink('isDetailVisible') @Watch('onDetailVisibleChange') isDetailVisible: boolean = false;
  @StorageLink('isDetailClosing') @Watch('onDetailClosingChange') isDetailClosing: boolean = false;

  onDetailVisibleChange() {
    // 移除在此处的刷新逻辑，统一移动到 onDetailClosingChange 中处理
    // 避免在关闭动画过程中刷新列表导致 geometryTransition 失效或组件状态异常
  }
  @State subscriptions: SubscriptionModel[] = [];
  @StorageProp('isWide') isWide: boolean = false;
  @StorageLink('isSplitViewEnabled') isSplitViewEnabled: boolean = true;
  @State rotateAngle: number = 0;
  @State isRotating: boolean = false;
  @State showLoginSheet: boolean = false;
  @State showUpcomingSheet: boolean = false;
  @State isUpcomingItemsVisible: boolean = false;

  @State isLoading: boolean = true;
  @State animatedExpense: number = 0;
  @State sortOrder: string = 'date_asc'; // date_asc, date_desc, price_desc, price_asc, name_asc
  @State pendingNavigationItem: SubscriptionModel | null = null;
  @State showSyncGuide: boolean = false; // 控制同步指南显示
  @StorageLink('homeCurrentTab') currentTab: 'subscription' | 'groupBuy' = 'subscription'; // 订阅/团购切换

  onDetailClosingChange() {
    if (!this.isDetailClosing) {
      // 动画结束后刷新列表，确保数据是最新的（包含排序变动）
      this.loadLocalData();
      
      if (this.pendingNavigationItem) {
        this.navigateToEdit(this.pendingNavigationItem);
        this.pendingNavigationItem = null;
      }
    }
  }

  navigateToEdit(item: SubscriptionModel) {
    if (!this.isOnline) {
      prompt.showToast({ message: '无法连接到服务器,请检查设备的网络连接' });
      return;
    }
    this.pageStack.removeByName('AddSubscription');
    this.pageStack.pushPathByName('AddSubscription', item);
  }


  // Interaction State
  @State isDashboardPressed: boolean = false;
  @State dashboardLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isSortPressed: boolean = false;
  @State sortLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isRefreshPressed: boolean = false;
  @State refreshLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isBellPressed: boolean = false;
  @State bellLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isSharePressed: boolean = false;
  @State shareLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Unified Animation System
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  // Animation States
  @Prop @Watch('onVisibleChange') isVisible: boolean = false;
  @State animStep1: boolean = false; // Dashboard
  @State animStep2: boolean = false; // Title
  @State animStep3: boolean = false; // List

  onVisibleChange() {
    if (this.isVisible) {
      // Sequence
      if (this.isAnimationEnabled) {
        const duration = this.animationDuration;
        const interval = duration * 0.15; // 15% of duration as stagger
        const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);

        animateTo({ duration: duration, curve: springCurve }, () => { this.animStep1 = true });
        setTimeout(() => { animateTo({ duration: duration, curve: springCurve }, () => { this.animStep2 = true }) }, interval);
        setTimeout(() => { animateTo({ duration: duration, curve: springCurve }, () => { this.animStep3 = true }) }, interval * 2);
      } else {
        this.animStep1 = true;
        this.animStep2 = true;
        this.animStep3 = true;
      }
      this.immersiveListening();
    } else {
      // Reset on exit to prepare for next entrance
      this.animStep1 = false;
      this.animStep2 = false;
      this.animStep3 = false;

      this.immersiveDisablingListening();
    }
  }

  reTriggerAnimation() {
    this.animStep1 = false;
    this.animStep2 = false;
    this.animStep3 = false;
    setTimeout(() => {
      this.onVisibleChange();
    }, 20);
  }

  @StorageLink('topRectHeight') topRectHeight: number = 0;

  async loadLocalData() {
    if (!this.isLoggedIn) {
      this.subscriptions = [];
      this.isLoading = false;
      this.animateExpense(0); // Reset animation to 0
      return;
    }

    const data = await SubscriptionRepository.getInstance().queryAll();

    // Get duration from storage or default
    const duration = this.animationDuration;
    const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);

    if (this.isAnimationEnabled) {
      animateTo({ duration: duration, curve: springCurve }, () => {
        this.subscriptions = this.sortSubscriptions([...data]);
        this.isLoading = false;
      });
    } else {
      this.subscriptions = this.sortSubscriptions([...data]);
      this.isLoading = false;
    }

    // 触发数字滚动动画
    this.calculateAndAnimateExpense();

    this.checkAndShowUpcomingSheet();
  }

  checkAndShowUpcomingSheet() {
    if (AppStorage.get<boolean>('hasShownUpcomingSheet')) {
      return;
    }
    const upcoming = this.getUpcomingRenewals();
    if (upcoming.length > 0) {
      setTimeout(() => {
        if (!AppStorage.get<boolean>('hasShownUpcomingSheet')) {
          this.showUpcomingSheet = true;
          AppStorage.setOrCreate('hasShownUpcomingSheet', true);
        }
      }, 500);
    }
  }



  async checkAndMigrateIcons() {
    // 使用本地图标库迁移 (纯离线)
    await LocalIconManager.getInstance().init(getContext(this));

    const legacyItems = this.subscriptions.filter(s => s.icon && s.icon.startsWith('resource:') && s.icon !== 'resource:petalone');
    if (legacyItems.length === 0) return;

    let updatedCount = 0;

    for (const item of legacyItems) {
      try {
        // 使用本地图标库搜索
        const appInfo = await LocalIconManager.getInstance().searchApp(item.name);

        if (appInfo && appInfo.icon) {
          item.icon = appInfo.icon;
          await SubscriptionRepository.getInstance().update(item);
          updatedCount++;
        }
      } catch (e) {
        console.error(`Icon migration failed for ${item.name}: ${JSON.stringify(e)}`);
      }
    }

    if (updatedCount > 0) {
      prompt.showToast({ message: `已自动优化 ${updatedCount} 个图标` });
      // Reload data to reflect changes
      const data = await SubscriptionRepository.getInstance().queryAll();
      this.subscriptions = this.sortSubscriptions([...data]);
    }
  }

  async aboutToAppear() {
    this.onVisibleChange();
    // Load persisted sort order before loading data
    this.sortOrder = await PreferenceUtil.getInstance().loadSortOrder();
    this.loadLocalData();
    setTimeout(() => {
      this.syncData();
    }, 500);
    this.subscribeToGlobalEvents();

    // Check for migrations after a short delay to avoid blocking startup
    // Check for migrations after a short delay to avoid blocking startup
    setTimeout(() => {
      this.checkAndMigrateIcons();
    }, 2000);
  }

  async checkAIConfig() {
    if (!this.isLoggedIn) return;

    const key = await PreferenceUtil.getInstance().getAIKey();
    const reminded = await PreferenceUtil.getInstance().getAIConfigReminded();

    if (!key && !reminded) {
      // 标记为已提醒，避免再次干扰
      await PreferenceUtil.getInstance().saveAIConfigReminded(true);

      AlertDialog.show({
        title: '开启 AI 自动识别',
        message: '检测到您尚未配置智谱 AI 密钥。配置后即可极大提升订阅信息识别成功率。是否前往配置？',
        autoCancel: false,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '下次再说',
          action: () => {}
        },
        secondaryButton: {
          value: '前往配置',
          fontColor: this.showVipTheme ? $r('app.color.vip_text_on_gold') : $r('app.color.brand_color'),
          action: () => {
            this.pageStack.pushPathByName('AIConfig', null);
          }
        }
      });
    }
  }

  aboutToDisappear() {
    // Subscribers will be handled by system GC if component is destroyed,
    // but the references are held in this.busSubscribers as long as HomeView exists.
    this.immersiveDisablingListening();
    let context = getContext(this) as common.UIAbilityContext;
    context.eventHub.off('onBackGround', this.onBackGround);
    context.eventHub.off('onForeground', this.onForeground);
  }

  private busSubscribers: commonEventManager.CommonEventSubscriber[] = [];

  async subscribeToGlobalEvents() {
    GlobalBus.subscribe(EVENT_SYNC_COMPLETED, () => {
      // 仅在非详情页展示状态下刷新，避免打断动画
      if (!this.isDetailVisible && !this.isDetailClosing) {
        this.loadLocalData();
      }
      this.checkAIConfig();
    }).then(s => this.busSubscribers.push(s));

    GlobalBus.subscribe(EVENT_DATA_CHANGED, () => {
      // 仅在非详情页展示状态下刷新，避免打断动画
      if (!this.isDetailVisible && !this.isDetailClosing) {
        this.loadLocalData();
      }
    }).then(s => this.busSubscribers.push(s));

    GlobalBus.subscribe('EVENT_LOGOUT', () => {
      this.subscriptions = [];
      this.loadLocalData();
    }).then(s => this.busSubscribers.push(s));

    // Listen for global data refresh from Index
    getContext(this).eventHub.on('refreshData', () => {
      hilog.info(0x0000, 'HomeView', 'Data refreshed from global import');
      this.loadLocalData();
    });

    // Listen for reminder sheet open event from Index
    getContext(this).eventHub.on('openReminderSheet', () => {
      hilog.info(0x0000, 'HomeView', 'Opening reminder sheet');
      this.showReminderSheet = true;
    });

    // ShareKit Lifecycle Events
    let context = getContext(this) as common.UIAbilityContext;
    context.eventHub.on('onBackGround', this.onBackGround);
    context.eventHub.on('onForeground', this.onForeground);
  }

  // Global import logic moved to Index.ets

  // --- ShareKit Implementation (Delegated) ---

  private immersiveListening() {
    HarmonyShareManager.getInstance().setContext(getContext(this) as common.UIAbilityContext);
    HarmonyShareManager.getInstance().register();
  }

  private immersiveDisablingListening() {
    HarmonyShareManager.getInstance().unregister();
  }

  private onBackGround = () => {
    this.immersiveDisablingListening();
  }

  private onForeground = () => {
    if (this.isVisible) {
      this.immersiveListening();
      this.loadLocalData();
    }
  }

  getTotalMonthlyExpense(): string {
    let total = 0;
    const now = new Date();
    this.subscriptions.forEach(sub => {
      // 永久/不定/团购项目仅在购买当月计入支出（全额）
      if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
        // 处理团购退款逻辑：如果是 'expired' 状态，或者 'unused' 且已过期，则不计入
        if (sub.recordType === 'groupBuy') {
          const days = DateUtil.getDaysUntil(sub.nextBillingDate);
          if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
            return;
          }
        }
        if (DateUtil.isSameMonth(new Date(sub.nextBillingDate), now)) {
          total += sub.price;
        }
        return;
      }
      // 均摊计算
      let price = sub.price;
      if (sub.billingCycle === 'Yearly') {
        price = price / 12;
      } else if (sub.billingCycle === 'Quarterly') {
        price = price / 3;
      }
      total += price;
    });
    return total.toFixed(2);
  }

  getUpcomingRenewals(): SubscriptionModel[] {
    return this.subscriptions.filter((item: SubscriptionModel) => {
      // 永久项目无自动续费提醒，“不定周期”如果有到期日则提醒
      // 如果关闭了自动续费，也不提示近期续费
      if (item.billingCycle === 'Lifetime') return false;
      if (item.isAutoRenewal === false) return false;

      const days = DateUtil.getDaysUntil(item.nextBillingDate);
      return days >= 0 && days <= 3;
    }).sort((a, b) => a.nextBillingDate - b.nextBillingDate);
  }

  getItemDescription(item: SubscriptionModel): string {
    let cycleText = '';
    switch (item.billingCycle) {
      case 'Monthly':
        cycleText = '月';
        break;
      case 'Quarterly':
        cycleText = '季';
        break;
      case 'Yearly':
        cycleText = '年';
        break;
      case 'Lifetime':
        cycleText = '永久';
        break;
      case 'Indefinite':
        cycleText = '不定';
        break;
    }

    let desc = `¥${item.price} / ${cycleText}`;
    if (item.subCategory) {
      desc += ` · ${item.subCategory}`;
    }
    return desc;
  }

  async manualRenew(item: SubscriptionModel) {
    const nextDate = new Date(item.nextBillingDate);
    if (item.billingCycle === 'Monthly') {
      nextDate.setMonth(nextDate.getMonth() + 1);
    } else if (item.billingCycle === 'Quarterly') {
      nextDate.setMonth(nextDate.getMonth() + 3);
    } else if (item.billingCycle === 'Yearly') {
      nextDate.setFullYear(nextDate.getFullYear() + 1);
    }
    item.nextBillingDate = nextDate.getTime();
    item.lastModified = new Date().getTime();
    await SubscriptionRepository.getInstance().update(item);
    this.loadLocalData();
    prompt.showToast({ message: `已续费 ${item.name}` });
  }



  getSortOrderText(): string {
    switch (this.sortOrder) {
      case 'date_asc': return '日期 (最近)';
      case 'date_desc': return '日期 (最远)';
      case 'price_desc': return '金额 (高→低)';
      case 'price_asc': return '金额 (低→高)';
      case 'name_asc': return '名称 (A-Z)';
      default: return '默认';
    }
  }

  // 根据当前 Tab 过滤列表
  getFilteredSubscriptions(): SubscriptionModel[] {
    if (this.currentTab === 'groupBuy') {
      return this.subscriptions.filter(item => item.recordType === 'groupBuy');
    }
    // 默认显示订阅记录（包括没有 recordType 字段的旧数据）
    return this.subscriptions.filter(item => !item.recordType || item.recordType === 'subscription');
  }

  // 获取团购券使用状态文本
  getUsageStatusText(status?: 'unused' | 'used' | 'expired'): string {
    switch (status) {
      case 'used': return '已使用';
      case 'expired': return '已过期';
      default: return '未使用';
    }
  }

  // 获取团购券使用状态颜色
  getUsageStatusColor(status?: 'unused' | 'used' | 'expired'): ResourceColor {
    switch (status) {
      case 'used': return $r('app.color.text_secondary');
      case 'expired': return Color.Red;
      default: return '#4CAF50'; // 绿色
    }
  }

  // 获取平台名称
  getPlatformName(platform?: 'meituan' | 'douyin'): string {
    switch (platform) {
      case 'meituan': return '美团';
      case 'douyin': return '抖音';
      default: return '未知';
    }
  }

  sortSubscriptions(items: SubscriptionModel[]): SubscriptionModel[] {
    return items.sort((a, b) => {
      // 团购券置底逻辑：已使用、已过期的置底
      if (a.recordType === 'groupBuy' || b.recordType === 'groupBuy') {
        const aProcessed = a.recordType === 'groupBuy' && (a.usageStatus === 'used' || a.usageStatus === 'expired');
        const bProcessed = b.recordType === 'groupBuy' && (b.usageStatus === 'used' || b.usageStatus === 'expired');

        if (aProcessed && !bProcessed) return 1;
        if (!aProcessed && bProcessed) return -1;
        // 如果两个都是已处理或两个都未处理，则继续走下面的常规排序逻辑
      }

      switch (this.sortOrder) {
        case 'date_asc':
          // Lifetime (Permanant) is "Infinity" -> Bottom
          const isALifetime = a.billingCycle === 'Lifetime';
          const isBLifetime = b.billingCycle === 'Lifetime';
          if (isALifetime && !isBLifetime) return 1;
          if (!isALifetime && isBLifetime) return -1;
          return a.nextBillingDate - b.nextBillingDate;

        case 'date_desc':
          // Lifetime (Permanant) is "Infinity" -> Top
          const isALifetimeDesc = a.billingCycle === 'Lifetime';
          const isBLifetimeDesc = b.billingCycle === 'Lifetime';
          if (isALifetimeDesc && !isBLifetimeDesc) return -1;
          if (!isALifetimeDesc && isBLifetimeDesc) return 1;
          return b.nextBillingDate - a.nextBillingDate;

        case 'price_desc':
          return b.price - a.price;

        case 'price_asc':
          return a.price - b.price;

        case 'name_asc':
          // Priority: Chinese (Pinyin) > English/Other
          const isAChinese = /[\u4e00-\u9fa5]/.test(a.name.charAt(0));
          const isBChinese = /[\u4e00-\u9fa5]/.test(b.name.charAt(0));

          if (isAChinese && !isBChinese) return -1;
          if (!isAChinese && isBChinese) return 1;

          return a.name.localeCompare(b.name, 'zh-CN');

        default:
        // Default like date_asc
          const isALifetimeDef = a.billingCycle === 'Lifetime';
          const isBLifetimeDef = b.billingCycle === 'Lifetime';
          if (isALifetimeDef && !isBLifetimeDef) return 1;
          if (!isALifetimeDef && isBLifetimeDef) return -1;
          return a.nextBillingDate - b.nextBillingDate;
      }
    });
  }

  applySort(order: string) {
    this.sortOrder = order;
    PreferenceUtil.getInstance().saveSortOrder(order);
    if (this.isAnimationEnabled) {
      const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);
      animateTo({ duration: this.animationDuration, curve: springCurve }, () => {
        this.subscriptions = this.sortSubscriptions(this.subscriptions);
      });
    } else {
      this.subscriptions = this.sortSubscriptions(this.subscriptions);
    }
  }

  calculateAndAnimateExpense() {
    let total = 0;
    const now = new Date();
    this.subscriptions.forEach(sub => {
      // 永久/不定/团购项目仅在购买当月计入支出（全额）
      if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
        if (DateUtil.isSameMonth(new Date(sub.nextBillingDate), now)) {
          total += sub.price;
        }
        return;
      }
      // 均摊计算
      let price = sub.price;
      if (sub.billingCycle === 'Yearly') {
        price = price / 12;
      } else if (sub.billingCycle === 'Quarterly') {
        price = price / 3;
      }
      total += price;
    });
    this.animateExpense(total);
  }

  animateExpense(target: number) {
    // 如果未开启动画，直接更新
    if (!this.isAnimationEnabled) {
      this.animatedExpense = target;
      return;
    }

    // 如果数值没有变化，无需动画
    if (Math.abs(this.animatedExpense - target) < 0.01) {
      return;
    }

    const duration = this.animationDuration;
    const startValue = this.animatedExpense;
    const diff = target - startValue;
    const startTime = Date.now();

    const timer = setInterval(() => {
      const now = Date.now();
      const progress = Math.min((now - startTime) / duration, 1.0);

      // EaseOutCubic function: 1 - pow(1 - x, 3)
      const ease = 1 - Math.pow(1 - progress, 3);

      this.animatedExpense = startValue + (diff * ease);

      if (progress >= 1) {
        this.animatedExpense = target;
        clearInterval(timer);
      }
    }, 16); // ~60fps
  }




  @Builder LoginSheetBuilder() {
    LoginSheet({
      isShow: this.showLoginSheet,
      onSuccess: () => { this.showLoginSheet = false },
      onClose: () => { this.showLoginSheet = false }
    })
  }

  @Builder DashboardDecoration() {
    if (this.isNewYearTheme) {
      // 极简福字印章 - 缩小比例，模仿传统印章感
      Text('福')
        .fontSize(40) // 显著缩小，避免侵占或溢出
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFD700')
        .opacity(0.15)
        .rotate({ angle: 180 })
        .position({ bottom: 12, right: 12 })
        .hitTestBehavior(HitTestMode.None)
    }
  }



  @Builder DashboardCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Decoration (Layer 1 - on top of stack bg)
      if (this.isNewYearTheme) {
        this.DashboardDecoration()
      }

      // 2. Content (Layer 2)
      Column() {
        Row() {
          Text("本月预估支出")
            .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .fontSize(14)
          Blank()
          Text(this.subscriptions.length + " 个订阅")
            .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .fontSize(13)
            .backgroundColor(this.isNewYearTheme ? '#33FFFFFF' : (this.showVipTheme ? '#1A302008' : '#33FFFFFF'))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 }).borderRadius(14)
        }
        .width('100%').margin({ bottom: 8 })

        Row({ space: 4 }) {
          Text('¥')
            .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .fontSize(20).fontWeight(FontWeight.Bold).margin({ top: 8 })
          Text(this.animatedExpense.toFixed(2))
            .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .fontSize(40).fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)

        Row() {
          SymbolGlyph($r('sys.symbol.share'))
            .fontSize(12)
            .fontColor([this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
          Text(" 碰一碰/隔空传送 已就绪")
            .fontSize(10)
            .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .opacity(0.8)
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.isNewYearTheme ? '#40302008' : (this.showVipTheme ? '#40302008' : '#22FFFFFF'))
        .borderRadius(10)
        .margin({ top: 8 })
        .onClick(() => { this.showSyncGuide = true })

        if (this.getUpcomingRenewals().length > 0) {
          Column() {
            Divider()
              .color(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
              .opacity(0.1).margin({ top: 16, bottom: 12 })
            Row() {
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(16)
                .fontColor([this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
                .margin({ right: 6 })

              Text() {
                Span(this.getUpcomingRenewals()[0].recordType === 'groupBuy' ? '团购券 ' : '服务 ')
                Span(`${this.getUpcomingRenewals()[0].name}`)
                Span(` 等 ${this.getUpcomingRenewals().length} 项近期${this.getUpcomingRenewals()[0].recordType === 'groupBuy' ? '过期' : '续费'}`)
              }
              .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
              .fontSize(13).fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(16)
                .fontColor([this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
                .opacity(0.7)
            }
            .width('100%')
            .onClick(() => {
              if (this.isAnimationEnabled) {
                animateTo({ duration: this.animationDuration, curve: curves.springMotion(this.animationResponse, this.animationDamping) }, () => {
                  this.showUpcomingSheet = true;
                });
              } else {
                this.showUpcomingSheet = true;
              }
            })
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .margin({ bottom: 24 })
    .linearGradient(this.isNewYearTheme ? {
      angle: 135,
      colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] as [ResourceColor, number][]
    } : (this.showVipTheme ? {
      angle: 135,
      colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] as [ResourceColor, number][]
    } : {
      angle: 135,
      colors: [[$r('app.color.brand_gradient_start'), 0.0], [$r('app.color.brand_gradient_end'), 1.0]] as [ResourceColor, number][]
    }))
    .shadow({ radius: 30, color: this.isNewYearTheme ? '#40D93025' : (this.showVipTheme ? '#40E6C07B' : '#40007AFF'), offsetY: 12 })
    .borderRadius(28)
    .clip(true)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.dashboardLight,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.isDashboardPressed ? 0.98 : 1, y: this.isDashboardPressed ? 0.98 : 1 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isDashboardPressed = true;
          this.dashboardLight = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isDashboardPressed = false;
        this.dashboardLight = hdsEffect.PointLightSourceType.NONE;
      }
    })
    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
  }

  @Builder EmptyState() {
    Column() {
      SymbolGlyph(this.currentTab === 'groupBuy' ? $r('sys.symbol.bag') : $r('sys.symbol.plus')).fontSize(56).fontColor([$r('app.color.text_secondary')]).margin({ bottom: 16 })
      Text(this.currentTab === 'groupBuy' ? "暂无团购" : "暂无服务").fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).margin({ bottom: 8 })
      Text(this.isLoggedIn ? (this.currentTab === 'groupBuy' ? "点击下方+按钮添加团购券" : "点击下方+按钮添加服务") : "请先登录后添加").fontSize(14).fontColor($r('app.color.text_secondary'))
    }
    .width('100%').padding({ top: 40, bottom: 40 }).justifyContent(FlexAlign.Center)
    .onClick(() => {
       if (!this.isLoggedIn) {
        if (this.isWide && this.isSplitViewEnabled) {
          this.pageStack.removeByName('Login');
          this.pageStack.pushPathByName('Login', null);
        } else {
          this.showLoginSheet = true;
        }
        return;
      }
      AppStorage.setOrCreate('showAddSheet', true);
    })
  }

  @Builder ReminderEmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.bell_slash'))
        .fontSize(64)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ bottom: 20 })
      Text("暂无可设置提醒的订阅")
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })
      Text("终身订阅项无需设置续费提醒。\n您可以点击“添加订阅”来管理更多订阅。")
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }

  @Builder SyncGuideSheet() {
    Column() {


      Scroll() {
        Column({ space: 24 }) {
          // 场景1：碰一碰
          Column({ space: 12 }) {
            Column() {
              Text("方式一：碰一碰").fontSize(16).fontWeight(FontWeight.Bold)
              Text("只需碰一碰，可直接向别的设备或好友分享记得订阅的订阅信息等，还可以连续触碰多个设备，轻松实现多人分享。").fontSize(14).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
            }.alignItems(HorizontalAlign.Start).width('100%')
            Video({
              src: $rawfile('touch.mp4'),
              controller: new VideoController()
            })
              .width('100%')
              .height(180)
              .objectFit(ImageFit.Contain)
              .autoPlay(true)
              .loop(true)
              .controls(false)
              .borderRadius(16)
              .backgroundColor('#0A000000')
          }

          // 场景2：一抓一放
          Column({ space: 12 }) {
            Column() {
              Text("方式二：隔空传送").fontSize(16).fontWeight(FontWeight.Bold)
              Text("在屏幕前做出“抓取”动作，移到另一台设备上方“放开,即可直接向别的设备或好友分享《记得订阅》的订阅信息”。").fontSize(14).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
            }.alignItems(HorizontalAlign.Start).width('100%')
            Video({
              src: $rawfile('Swing_share.mp4'),
              controller: new VideoController()
            })
              .width('100%')
              .height(180)
              .objectFit(ImageFit.Contain)
              .autoPlay(true)
              .loop(true)
              .controls(false)
              .borderRadius(16)
              .backgroundColor('#0A000000')
          }

          Text("Tips：该功能需要两台设备均处于亮屏解锁状态，且双方均已安装最新版本的《记得订阅》并开启华为分享。此功能要求双方手机为 HarmonyOS 5 及以上版本，多人分享需发送端设备支持 HarmonyOS 6 及以上版本。")
            .fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Start).width('100%').margin({ top: 12 })
        }.padding({ left: 20, right: 20, bottom: 40 })
      }
    }
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder UpcomingRenewalsSheet() {
    Column() {
      // Handle Bar
      Row()
        .width(40)
        .height(4)
        .backgroundColor($r('app.color.text_secondary'))
        .opacity(0.2)
        .borderRadius(2)
        .margin({ top: 8, bottom: 20 })

      // Title
      Column() {
        Text('近期到期订阅')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('以下订阅即将到期')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, bottom: 16 })

      Scroll() {
        Column() {
          ForEach(this.getUpcomingRenewals(), (item: SubscriptionModel, idx: number) => {
            Column() {
              Row() {
                SubscriptionIcon({
                  icon: item.recordType === 'groupBuy' ? this.getGroupBuyIcon(item) : item.icon,
                  name: item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name,
                  iconSize: 40,
                  iconRadius: 10,
                  showGroupBadge: item.recordType === 'groupBuy'
                })
                  .margin({ right: 12 })

                Column() {
                  Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text(this.getItemDescription(item))
                    .fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start).layoutWeight(1)

                Column() {
                  Text(DateUtil.formatDate(item.nextBillingDate)).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ bottom: 4 })
                  Row({ space: 8 }) {
                    Button({ type: ButtonType.Normal, stateEffect: true }) {
                      SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([Color.Red])
                    }
                    .width(36).height(28).backgroundColor($r('app.color.page_background')).borderRadius(14)
                    .onClick(() => { this.deleteSubscription(item); })

                    Button(item.recordType === 'groupBuy' ? '已使用' : '已续费')
                      .fontSize(12)
                      .height(28)
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
                      .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                      .onClick(() => {
                        if (item.recordType === 'groupBuy') {
                          // 团购券核销逻辑：标记为已使用，并更新最后修改时间
                          item.usageStatus = 'used';
                          item.realUsageTime = new Date().getTime();
                          item.lastModified = new Date().getTime();
                          SubscriptionRepository.getInstance().update(item);
                          this.loadLocalData();
                          prompt.showToast({ message: `已核销 ${item.name}` });
                        } else {
                          this.manualRenew(item);
                        }
                      })
                  }
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%').padding({ top: 12, bottom: 12 })
              .bindContextMenu(this.SubscriptionContextMenu(item), ResponseType.LongPress)
            }
            .opacity(this.isUpcomingItemsVisible ? 1 : 0)
            .translate({ y: this.isUpcomingItemsVisible ? 0 : 20 })
            .animation({
              delay: (this.isAnimationEnabled && idx) ? idx * 50 : 0,
              duration: this.isAnimationEnabled ? this.animationDuration : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
            })
          }, (item: SubscriptionModel) => item.uuid + '_' + item.icon)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .edgeEffect(EdgeEffect.Spring)
      // 限制最大高度，避免列表过长时占满全屏
      .constraintSize({ maxHeight: '75%' })
      .onAppear(() => {
         if (this.isAnimationEnabled) {
             // Reset state first to ensure animation triggers if reopened
             this.isUpcomingItemsVisible = false;
             setTimeout(() => {
                 this.isUpcomingItemsVisible = true;
             }, 50);
         } else {
             this.isUpcomingItemsVisible = true;
         }
      })
      .onDisAppear(() => {
          this.isUpcomingItemsVisible = false;
      })
    }
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder SubscriptionContextMenu(item: SubscriptionModel) {
    Menu() {
      MenuItem({ content: '一键续费', startIcon: $r('sys.symbol.arrow_clockwise') })
        .onClick(() => {
          this.manualRenew(item);
        })
      MenuItem({ content: '删除订阅', startIcon: $r('sys.symbol.trash') })
        .onClick(() => {
          this.deleteSubscription(item);
        })
    }
  }

  @Builder DeleteButton(item: SubscriptionModel, isStart: boolean = false) {
    SwipeDeleteButton({
      item: item,
      isStart: isStart,
      onDelete: (i) => { this.deleteSubscription(i) }
    })
  }

  @Builder SheetTitleBuilder() {
    Row() {
      // Left Icon: Back (Action) or Bell (Decoration)
      // Left Icon: Back (Action) or Bell (Decoration)
      Row() {
        if (this.isReminderSetupVisible) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('app.color.text_primary')])
          }
          .backgroundColor(Color.Transparent)
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.closeReminderSetup();
          })
        } else {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(24)
            .fontColor([$r('app.color.text_primary')])
        }
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      // Title Section
      Column() {
        if (this.isReminderSetupVisible) {
          Text('设置提醒')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.activeReminderItem ? this.activeReminderItem.name : '设置提醒时间')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text('提醒管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('管理订阅的到期通知')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1) // Take remaining space

      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 24 }) // Reduced left padding since we have button placeholder
    .alignItems(VerticalAlign.Center)
  }

  @Builder SubscriptionItemAnimated(item: SubscriptionModel, index: number) {
    Column() {
      SubscriptionCard({ data: item, index: index })
        .onClick(() => {
          if (this.isDetailVisible || this.isDetailClosing) {
            this.pendingNavigationItem = item;
            return;
          }
          this.navigateToEdit(item);
        })
        .bindContextMenu(this.SubscriptionContextMenu(item), ResponseType.LongPress)
    }
    .zIndex(2)
    .transition(
      this.isAnimationEnabled
        ? TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({
          curve: curves.springMotion(this.animationResponse, this.animationDamping),
          delay: index * 50
        })
          .combine(TransitionEffect.translate({ y: 30 }).animation({
            curve: curves.springMotion(this.animationResponse, this.animationDamping),
            delay: index * 50
          }))
          .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({
            curve: curves.springMotion(this.animationResponse, this.animationDamping),
            delay: index * 50
          })),
        TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
      )
        : undefined
    )
  }

  async syncData() {
    if (this.isSyncing) return;
    this.isSyncing = true;
    this.rotateAngle = 0;
    this.isRotating = true;

    // Simple rotation simulation for the icon
    const interval = setInterval(() => {
      if (!this.isRotating) {
        clearInterval(interval);
        return;
      }
      animateTo({ duration: this.isAnimationEnabled ? 100 : 0, curve: Curve.Linear }, () => {
        this.rotateAngle += 30;
      })
    }, 100);

    try {
      await SubscriptionRepository.getInstance().syncWithCloud();
    } catch (error) {
      hilog.error(0x0000, 'HomeView', 'Sync failed: %{public}s', JSON.stringify(error));
      prompt.showToast({ message: '同步失败，请重试' });
    } finally {
      this.isSyncing = false;
      this.isRotating = false;
      clearInterval(interval);
      if (this.isAnimationEnabled) {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.rotateAngle = 0;
        });
      } else {
        this.rotateAngle = 0;
      }
    }
  }



  build() {
    HdsNavDestination() {

    Stack({ alignContent: Alignment.Top }) {
      // 主内容区域
      Column() {
        if (this.isWide && !this.isSplitViewEnabled) {
          Grid() {
            // 1. Top Spacer (Span 2)
            GridItem() {
              Column().height(76 + this.getUIContext().px2vp(this.topRectHeight))
            }.columnStart(0).columnEnd(1)

            // 2. Dashboard & Header (Span 2)
            GridItem() {
              Column() {
                Column() {
                  this.DashboardCard()
                }
                .opacity(this.animStep1 ? 1 : 0)
                .translate({ y: this.animStep1 ? 0 : 50 })

                Row() {
                  Text("订阅列表").fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                  Blank()

                  // Sort Menu
                  Row() {
                    Text(this.getSortOrderText())
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ right: 4 })

                    SymbolGlyph($r('sys.symbol.sort'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .height(32)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(16)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: this.sortLight,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({ x: this.isSortPressed ? 0.95 : 1, y: this.isSortPressed ? 0.95 : 1 })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      if (this.isAnimationEnabled && this.isPointLightEnabled) {
                        this.isSortPressed = true;
                        this.sortLight = hdsEffect.PointLightSourceType.BRIGHT;
                      }
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isSortPressed = false;
                      this.sortLight = hdsEffect.PointLightSourceType.NONE;
                    }
                  })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .bindMenu([
                    { value: '日期 (最近)', action: () => this.applySort('date_asc') },
                    { value: '日期 (最远)', action: () => this.applySort('date_desc') },
                    { value: '金额 (从高到低)', action: () => this.applySort('price_desc') },
                    { value: '金额 (从低到高)', action: () => this.applySort('price_asc') },
                    { value: '名称 (A-Z)', action: () => this.applySort('name_asc') }
                  ])
                }
                .width('100%').margin({ bottom: 16 })
                .opacity(this.animStep2 ? 1 : 0)
                .translate({ y: this.animStep2 ? 0 : 50 })
              }
              .width('100%')
            }.columnStart(0).columnEnd(1)

            // New Year Countdown Card (Grid)
            if (this.currentTab === 'subscription') {
              GridItem() {
                NewYearSubscriptionCard()
              }
              .columnStart(0).columnEnd(1)
              .opacity(this.animStep2 ? 1 : 0)
              .translate({ y: this.animStep2 ? 0 : 50 })
            }

            if (this.isLoading) {
              GridItem() {
                Column({ space: 16 }) {
                  LoadingProgress().width(48).height(48)
                  Text("正在加载订阅数据...").fontSize(14).fontColor($r('app.color.text_secondary'))
                }
                .width('100%').height(200).justifyContent(FlexAlign.Center)
              }
              .columnStart(0).columnEnd(1)
            } else if (this.getFilteredSubscriptions().length === 0) {
              GridItem() {
                this.EmptyState()
              }
              .columnStart(0).columnEnd(1)
            } else {
              ForEach(this.getFilteredSubscriptions(), (item: SubscriptionModel, index: number) => {
                GridItem() {
                  this.SubscriptionItemAnimated(item, index)
                }
              }, (item: SubscriptionModel) => JSON.stringify(item))
            }

            // Bottom Spacer
            GridItem() { Column().height(120) }.columnStart(0).columnEnd(1)
          }
          .columnsTemplate('1fr 1fr')
          .rowsGap(12)
          .columnsGap(12)
          .padding({ left: 16, right: 16 })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
          .opacity(this.animStep3 ? 1 : 0)
          .translate({ y: this.animStep3 ? 0 : 50 })

        } else {
          List({ space: 0 }) {
            // 顶部占位，避免被标题栏遮挡
            ListItem() {
              Column() {
                Blank()
                  .height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight))
              }
            }

            ListItem() {
              Column() {
                Column() {
                  this.DashboardCard()
                }
                .opacity(this.animStep1 ? 1 : 0)
                .translate({ y: this.animStep1 ? 0 : 50 })



                Row() {
                  // 订阅/团购切换按钮
                  // 订阅/团购切换按钮
                  Row() {
                    Button() {
                      Text("服务")
                        .fontSize(14)
                        .fontWeight(this.currentTab === 'subscription' ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(this.currentTab === 'subscription' ?
                          (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                          $r('app.color.text_secondary'))
                    }
                    .linearGradient(this.currentTab === 'subscription' ?
                      (this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined)) : undefined)
                    .backgroundColor(this.currentTab === 'subscription' ?
                      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                      Color.Transparent)
                    .borderRadius(14)
                    .padding({ left: 20, right: 20, top: 6, bottom: 6 })
                    .onClick(() => {
                      animateTo({ duration: this.isAnimationEnabled ? 300 : 0, curve: Curve.EaseInOut }, () => {
                        this.currentTab = 'subscription';
                      });
                    })

                    Button() {
                      Text("团购")
                        .fontSize(14)
                        .fontWeight(this.currentTab === 'groupBuy' ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(this.currentTab === 'groupBuy' ?
                          (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                          $r('app.color.text_secondary'))
                    }
                    .linearGradient(this.currentTab === 'groupBuy' ?
                      (this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined)) : undefined)
                    .backgroundColor(this.currentTab === 'groupBuy' ?
                      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                      Color.Transparent)
                    .borderRadius(14)
                    .padding({ left: 20, right: 20, top: 6, bottom: 6 })
                    .onClick(() => {
                      animateTo({ duration: this.isAnimationEnabled ? 300 : 0, curve: Curve.EaseInOut }, () => {
                        this.currentTab = 'groupBuy';
                      });
                    })
                  }
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(16)
                  .padding(4)

                  Blank()

                  // Sort Menu
                  Row() {
                    Text(this.getSortOrderText())
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ right: 4 })

                    SymbolGlyph($r('sys.symbol.sort'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .height(32)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(16)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: this.sortLight,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({ x: this.isSortPressed ? 0.95 : 1, y: this.isSortPressed ? 0.95 : 1 })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      if (this.isAnimationEnabled && this.isPointLightEnabled) {
                        this.isSortPressed = true;
                        this.sortLight = hdsEffect.PointLightSourceType.BRIGHT;
                      }
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isSortPressed = false;
                      this.sortLight = hdsEffect.PointLightSourceType.NONE;
                    }
                  })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .bindMenu([
                    { value: '日期 (最近)', action: () => this.applySort('date_asc') },
                    { value: '日期 (最远)', action: () => this.applySort('date_desc') },
                    { value: '金额 (从高到低)', action: () => this.applySort('price_desc') },
                    { value: '金额 (从低到高)', action: () => this.applySort('price_asc') },
                    { value: '名称 (A-Z)', action: () => this.applySort('name_asc') }
                  ])
                }
                .width('100%').margin({ bottom: 16 })
                .opacity(this.animStep2 ? 1 : 0)
                .translate({ y: this.animStep2 ? 0 : 50 })
              }
              .padding({ left: 16, right: 16 }).width('100%')
            }

            if (this.currentTab === 'subscription') {
              ListItem() {
                NewYearSubscriptionCard()
                  .margin({ bottom: 16, left: 16, right: 16 })
              }
            }

            if (this.isLoading) {
              ListItem() {
                Column({ space: 16 }) {
                  LoadingProgress()
                    .width(48)
                    .height(48)
                  Text("正在加载订阅数据...")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .height(200)
                .justifyContent(FlexAlign.Center)
              }
              .transition(TransitionEffect.OPACITY.animation({
                duration: this.isAnimationEnabled ? this.animationDuration : 0,
                curve: Curve.EaseOut
              }))
            } else if (this.getFilteredSubscriptions().length === 0) {
              ListItem() {
                this.EmptyState()
              }
              .padding({ left: 24, right: 24 })
              .transition(TransitionEffect.OPACITY.animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0 }))
            } else {
              ForEach(this.getFilteredSubscriptions(), (item: SubscriptionModel, index: number) => {
                ListItem() {
                  Column() {
                    this.SubscriptionItemAnimated(item, index)
                  }
                  .margin({ bottom: 12, left: 16, right: 16 })
                }
                .swipeAction({
                  start: { builder: () => { this.DeleteButton(item, true) } },
                  end: { builder: () => { this.DeleteButton(item, false) } }
                })
              }, (item: SubscriptionModel) => JSON.stringify(item))
            }
            ListItem() { Column().height(120) }
          }
          .width('100%').height('100%').scrollBar(BarState.Off)
          .opacity(this.animStep3 ? 1 : 0)
          .translate({ y: this.animStep3 ? 0 : 50 })
        }
      }
      .width('100%').height('100%').backgroundColor(Color.Transparent)
      .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
        if (isVisible && currentRatio >= 1.0) { this.loadLocalData(); }
      })
      .bindSheet($$this.showLoginSheet, this.LoginSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        backgroundColor: $r('app.color.page_background'),
        showClose: true,
        preferType: SheetType.BOTTOM,
        title: { title: '登录', subtitle: '使用华为账号登录' }
      })
      Column()
        .bindSheet($$this.showUpcomingSheet, this.UpcomingRenewalsSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          preferType: SheetType.BOTTOM
        })
      Column()
        .bindSheet($$this.showSyncGuide, this.SyncGuideSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          preferType: SheetType.BOTTOM,
          title: { title: '近场同步/分享订阅数据' }
        })
      Column()
        .bindSheet($$this.showReminderSheet, this.ReminderSheetBuilder(), {
          detents: [550],
          backgroundColor: $r('app.color.page_background'),
          preferType: SheetType.BOTTOM,
          showClose: false,
        })


    }




    }
    .hideBackButton(true)
    .hideTitleBar(false)

    .backgroundColor(Color.Transparent)
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '订阅概览' },
        menu: {
          value: [
            {
              content: {
                label: '提醒管理',
                icon: $r('sys.symbol.bell'),
                action: (): void => {
                  getContext(this).eventHub.emit('openReminderSheet');
                }
              }
            } as HdsNavigationMenuItemOptions,
            {
              content: {
                label: '分享',
                icon: $r('sys.symbol.share'),
                action: (): void => {
                  if (!this.isLoggedIn) {
                    if (this.isWide && this.isSplitViewEnabled) {
                      this.pageStack.removeByName('Login');
                      this.pageStack.pushPathByName('Login', null);
                    } else {
                      if (this.isAnimationEnabled) {
                      animateTo({
                        duration: this.animationDuration,
                        curve: curves.springMotion(this.animationResponse, this.animationDamping)
                      }, () => {
                        this.showLoginSheet = true;
                      });
                    } else {
                      this.showLoginSheet = true;
                    }
                    }
                    return;
                  }
                  HarmonyShareManager.getInstance().activeShare();
                }
              }
            } as HdsNavigationMenuItemOptions
          ]
        }
      }
    })
  }

  @State showReminderSheet: boolean = false;
  @State activeReminderItem: SubscriptionModel | null = null;
  @State isReminderSetupVisible: boolean = false;
  @State reminderSheetWidth: number = 0;

  openReminderSetup(item: SubscriptionModel) {
    this.activeReminderItem = item;
    // Animate transition to setup panel
    if (this.isAnimationEnabled) {
      animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
        this.isReminderSetupVisible = true;
      });
    } else {
      this.isReminderSetupVisible = true;
    }
  }

  closeReminderSetup() {
    if (this.isAnimationEnabled) {
      animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
        this.isReminderSetupVisible = false;
        this.showReminderSheet = false;
      });
    } else {
      this.isReminderSetupVisible = false;
      this.showReminderSheet = false;
    }
    // Optionally clear active item after animation?
    // Better to keep it until closed to avoid UI flicker during slide out.
  }

  getGroupBuyIcon(sub: SubscriptionModel): string {
    if (sub.platform === 'meituan') return 'resource:meituan_logo';
    if (sub.platform === 'douyin') return 'resource:douyin_logo';
    if (sub.platform === 'dianping') return 'resource:dianping_logo';
    return sub.icon ?? '';
  }

  @Builder ReminderSheetBuilder() {
    ReminderSetupPanel({
      subscriptions: $subscriptions,
      isSetupVisible: $isReminderSetupVisible,
      activeItem: $activeReminderItem,
      sheetWidth: $reminderSheetWidth,
      onSave: async (item, days, time) => {
        console.info(`[HomeView] Updating reminder: days=${days}, time=${time}`);
        item.reminderDaysBefore = days;
        item.reminderTime = time;
        item.lastModified = new Date().getTime();
        await SubscriptionRepository.getInstance().update(item);
        this.loadLocalData();
        this.closeReminderSetup();
      },
      onCancel: () => {
        this.closeReminderSetup();
      },
      onRemove: async (item) => {
        item.reminderDaysBefore = undefined;
        item.reminderTime = undefined;
        item.lastModified = new Date().getTime();
        await SubscriptionRepository.getInstance().update(item);
        this.loadLocalData();
        this.closeReminderSetup();
      }
    })
  }

  async deleteSubscription(item: SubscriptionModel) {
    if (item.id) {
      AlertDialog.show({
        title: '确认删除', message: `您确定要删除“${item.name}”订阅吗？`, autoCancel: true, alignment: DialogAlignment.Center, offset: { dx: 0, dy: -20 },
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: {
          value: '删除', fontColor: Color.Red,
          action: async () => {
            await SubscriptionRepository.getInstance().delete(item.id as number);
            this.loadLocalData();
            prompt.showToast({ message: '已删除' });
          }
        }
      })
    }
  }
}

@Component
struct SwipeDeleteButton {
  @Prop item: SubscriptionModel;
  @Prop isStart: boolean = false;
  onDelete: (item: SubscriptionModel) => void = () => {};
  @State isPressed: boolean = false;
  @State lightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('isOnline') isOnline: boolean = true;

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
    }
    .width(48).height(48)
    .backgroundColor(Color.Red)
    .margin({
      bottom: 12,
      left: this.isStart ? 24 : 0,
      right: this.isStart ? 0 : 24
    })
    .zIndex(1)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.lightSource,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.isPressed ? 0.9 : 1, y: this.isPressed ? 0.9 : 1 })
    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isPressed = true;
          this.lightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.lightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
    .onClick(() => {
      if (!this.isOnline) {
        prompt.showToast({ message: '无法连接到服务器，请检查设备的网络连接' });
        return;
      }
      this.onDelete(this.item);
    })
  }
}

class ExportData {
  version: number = 1;
  timestamp: number = 0;
  subscriptions: SubscriptionModel[] = [];
}
