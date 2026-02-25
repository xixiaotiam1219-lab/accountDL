import { SubscriptionModel } from '../model/SubscriptionModel';
import { promptAction, SymbolGlyphModifier, curves, LengthMetrics } from '@kit.ArkUI';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { DateUtil } from '../utils/DateUtil';
import { EVENT_SYNC_COMPLETED, EVENT_LOGOUT, EVENT_DATA_CHANGED, GlobalBus } from '../utils/GlobalBus';
import { resolveIcon } from '../utils/MemberServiceConfig';
import { SubscriptionIcon } from './SubscriptionIcon';
import { commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect, hdsMaterial, HdsNavDestination, HdsNavigationMenuItemOptions,
  ScrollEffectType } from '@kit.UIDesignKit';

interface LinearGradientValue {
  angle?: number | string;
  direction?: GradientDirection;
  colors: [ResourceColor, number][];
  repeating?: boolean;
}

interface SubscriptionRange {
  start: number;
  end: number;
  isCurrentMonth: boolean;
}

interface PopupEvent {
  isVisible: boolean;
}

@Observed
export class GroupBuySegment {
  left: number = 0;
  width: number = 0;
  isConsumed: boolean = false; // 是否为已核销后的部分
  isAtStart: boolean = false; // 是否为整条的起点
  isAtEnd: boolean = false; // 是否为整条的终点

  constructor(left: number, width: number, isConsumed: boolean = false, isAtStart: boolean = false, isAtEnd: boolean = false) {
    this.left = left;
    this.width = width;
    this.isConsumed = isConsumed;
    this.isAtStart = isAtStart;
    this.isAtEnd = isAtEnd;
  }
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct CalendarView {
  private syncSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private logoutSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @State currentYear: number = new Date().getFullYear();
  @State currentMonth: number = new Date().getMonth(); // 0-11
  @State selectedDate: Date = new Date();
  @State subscriptions: SubscriptionModel[] = [];
  @State calendarDays: Date[] = [];
  @State showDetailSheet: boolean = false;
  @State gridHeight: number = 300; // Default height
  @State @Watch('onViewModeChange') viewMode: number = 0; // 0: Month, 1: Timeline
  @State timelineScrollX: number = 0;
  private timelineScroller: Scroller = new Scroller();
  // 缓存当月每一天的订阅列表，key为日期(1-31)
  @State dailySubscriptions: Map<number, SubscriptionModel[]> = new Map();
  // Cache for Group Buy Segments to avoid heavy regex parsing on scroll
  private groupBuySegmentsCache: Map<string, GroupBuySegment[]> = new Map();

  // @StorageLink('topRectHeight') topRectHeight: number = 0;
  
  @State showHelpPopup: boolean = false;
  @State isHelpPressed: boolean = false;
  @State helpLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @StorageLink('isPointLightEnabled') @Watch('onAnimationConfigChange') isPointLightEnabled: boolean = true;
  @StorageLink('isAnimationEnabled') @Watch('onAnimationConfigChange') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6

  // Interaction States
  @State isPrevMonthPressed: boolean = false;
  @State isNextMonthPressed: boolean = false;
  @State isDatePickerPressed: boolean = false;
  @State isViewModePressed: number = -1; // -1: none, 0: month, 1: timeline
  @State pressedGridDate: string = ''; // Format: YYYY-MM-DD
  @State pressedTimelineDate: string = '';
  @State pressedListId: number = -1;

  @Builder
  InfoPopup() {
    Column() {
      Text("关于团购券样式")
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })
      Text("团购券时间轴显示规则：\n1. 显示范围：取“有效期”与“可用时段”（如周一至周五）的交集。\n   (例如：若周三启用且仅工作日可用，则时间条从周三开始)\n2. 分段样式：非连续时间段（如跨越周末）会自动断开，出现直角开合情况，是正常现象。")
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(20)
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .width(300)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: 4 })
  }

  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @State currentTime: Date = new Date();
  private timeTickSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  // Animation States
  @Prop @Watch('onVisibleChange') isVisible: boolean = false;
  @State animStep1: boolean = false; // Header
  @State animStep2: boolean = false; // Grid
  @State animStep3: boolean = false; // List
  @State hasAnimated: boolean = false;

  onAnimationConfigChange() {
    // Force refresh when animation config changes
    this.generateCalendar(); // Re-trigger calendar generation to apply visual effects if needed
  }

  onViewModeChange() {
    if (this.viewMode === 1) {
      setTimeout(() => {
        let targetDay = 1;

        // Priority 1: Selected Date (if in current view month)
        if (this.selectedDate.getFullYear() === this.currentYear &&
          this.selectedDate.getMonth() === this.currentMonth) {
          targetDay = this.selectedDate.getDate();
        }
        // Priority 2: Today (if in current view month)
        else {
          const today = new Date();
          if (today.getFullYear() === this.currentYear &&
            today.getMonth() === this.currentMonth) {
            targetDay = today.getDate();
          }
        }

        // Calculate offset (Day 1 is at 0, Day 2 at 48...)
        // Center alignment: Offset = (Day - 1) * 48
        // Let's scroll to center slightly? No, left align to date is standard.
        // Actually, to make the date visible, left align is safest.
        const xOffset = (targetDay - 1) * 48;

        this.timelineScroller.scrollTo({ xOffset: xOffset, yOffset: 0, animation: this.isAnimationEnabled });
      }, 50); // Small delay to allow layout to build
    }
  }

  onVisibleChange() {
    if (this.isVisible) {
      if (this.isAnimationEnabled) {
        const interval = this.animationDuration * 0.15;
        const springCurve: ICurve = curves.springMotion(this.animationResponse, this.animationDamping);

        // 第一梯队: 标题栏与日历主体同时入场
        animateTo({ curve: springCurve }, () => {
          this.animStep1 = true
          this.animStep2 = true
        });

        // 第二梯队: 底部列表跟随
        setTimeout(() => {
          animateTo({ curve: springCurve }, () => {
            this.animStep3 = true
          })
        });
      } else {
        this.animStep1 = true;
        this.animStep2 = true;
        this.animStep3 = true;
      }

      // Also trigger scroll sync if entering in Timeline mode directly
      if (this.viewMode === 1) {
        this.onViewModeChange();
      }
    } else {
      // Reset on exit
      this.animStep1 = false;
      this.animStep2 = false;
      this.animStep3 = false;
    }
  }

  aboutToAppear() {
    this.refreshData();
    this.generateCalendar();
    this.onVisibleChange();

    // 监听数据同步事件
    GlobalBus.subscribe(EVENT_SYNC_COMPLETED, () => {
      this.refreshData();
    }).then(s => this.syncSubscriber = s);

    // 监听数据变更事件 (如手动标记使用)
    GlobalBus.subscribe(EVENT_DATA_CHANGED, () => {
      this.refreshData();
    });

    // 监听 Help Button 点击事件
    getContext(this).eventHub.on('openCalendarHelp', () => {
      this.showHelpPopup = !this.showHelpPopup;
    });



    // 监听登出事件
    GlobalBus.subscribe(EVENT_LOGOUT, () => {
      this.subscriptions = [];
      this.dailySubscriptions = new Map();
      this.generateCalendar();
    }).then(s => this.logoutSubscriber = s);

    // 监听系统每分钟的时间跳变 (取代 setInterval)
    commonEventManager.createSubscriber({
      events: [commonEventManager.Support.COMMON_EVENT_TIME_TICK]
    }).then(sub => {
      this.timeTickSubscriber = sub;
      commonEventManager.subscribe(sub, () => {
        this.currentTime = new Date();
      });
    });
  }

  aboutToDisappear() {
    if (this.timeTickSubscriber) {
      commonEventManager.unsubscribe(this.timeTickSubscriber);
    }
  }

  async refreshData() {
    this.groupBuySegmentsCache.clear(); // Clear cache on refresh
    const data = await SubscriptionRepository.getInstance().queryAll();
    this.subscriptions = [...data];
    this.calculateMonthlyEvents();
  }

  // 计算当月每一天的事件
  calculateMonthlyEvents() {
    const map = new Map<number, SubscriptionModel[]>();

    // 获取当前视图月的起始和结束时间戳
    const viewStart = new Date(this.currentYear, this.currentMonth, 1).getTime();
    const viewEnd = new Date(this.currentYear, this.currentMonth + 1, 0, 23, 59, 59, 999).getTime();

    this.subscriptions.forEach(sub => {
      if (sub.isDeleted) return;

      let billingDate = new Date(sub.nextBillingDate);
      // Group Buy: checking usage time first
      if (sub.recordType === 'groupBuy' && sub.usageStatus === 'used' && sub.realUsageTime) {
         billingDate = new Date(sub.realUsageTime);
      }
      const billingDay = billingDate.getDate();

      // 基础边界检查
      if (sub.startDate && sub.startDate > viewEnd) return; // 还没开始

      let isMatch = false;

      // Group Buy Logic: Only dot on Usage Date (if used) or Expiration Date (nextBillingDate)
      if (sub.recordType === 'groupBuy') {
        let targetDate: Date;
        if (sub.usageStatus === 'used' && sub.realUsageTime) {
             targetDate = new Date(sub.realUsageTime);
        } else {
             targetDate = new Date(sub.nextBillingDate);
        }
        
        if (targetDate.getFullYear() === this.currentYear && 
            targetDate.getMonth() === this.currentMonth && 
            targetDate.getDate() === billingDay) {
           isMatch = true; 
        }
      } else if (sub.recordType === 'warranty' || sub.recordType === 'card') {
        if (billingDate.getFullYear() === this.currentYear && billingDate.getMonth() === this.currentMonth) {
          isMatch = true;
        }
      } else if (sub.billingCycle === 'Monthly') {
        const daysInMonth = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
        if (billingDay <= daysInMonth) {
          // 月付：逻辑是"每个月的 billingDay"
          // 但需要满足：
          // 1. 在 startDate 之后 (已在上方判断)
          // 2. 在 nextBillingDate 之前或等于 (即当前处于有效期内)
          // 补充：Repository 会在查询时自动推算 nextBillingDate 为"未来的下一个扣款日"
          // 所以如果 viewStart 已经超过了 sub.nextBillingDate，说明该项目可能已停付且未自动续期
          if (viewStart > sub.nextBillingDate) {
            isMatch = false;
          } else {
            isMatch = true;
          }
        }
      } else if (sub.billingCycle === 'Quarterly') {
        // 季付：检查当前月份是否是扣款月
        const billingMonth = billingDate.getMonth();
        const monthDiff = (this.currentMonth - billingMonth + 12) % 12;
        if (monthDiff % 3 === 0) {
          const daysInMonth = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
          if (billingDay <= daysInMonth) {
            // 同样需要满足有效期校验
            if (viewStart <= (sub.nextBillingDate || Infinity)) {
              isMatch = true;
            }
          }
        }
      } else if (sub.billingCycle === 'Yearly') {
        if (billingDate.getMonth() === this.currentMonth) {
          // 年付：仅在对应的月份显示
          // 且当前视图年份必须满足 (viewStart <= nextBillingDate)
          if (viewStart <= sub.nextBillingDate) {
            isMatch = true;
          }
        }
      } else if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite') {
        // 永久/不定：在购买日显示标记。如果是永久/不定订阅，后续月份虽然不扣费，但仍视为 active 状态。
        // 这里逻辑：如果是购买月，显示 Match。如果是后续月，我们也显示一个淡色标记（可选），或者保持 Match 以便列表显示。
        // 为了和列表对齐，我们让它在后续月份也 Match 到 1 号，或者干脆只在购买日显示，但 Timeline 逻辑独立。
        if (billingDate.getMonth() === this.currentMonth && billingDate.getFullYear() === this.currentYear) {
          isMatch = true;
        } else if (billingDate.getTime() < viewStart) {
           // 如果是以前购买的永久/不定项目，我们默认不给它在日历 grid 里打点（避免每月 1 号都冒出点来），
           // 但 Timeline 逻辑会独立处理其展示。
           isMatch = false; 
        }
      }

      if (isMatch) {
        if (!map.has(billingDay)) {
          map.set(billingDay, []);
        }
        map.get(billingDay)?.push(sub);
      }
    });

    this.dailySubscriptions = map;
  }

  generateCalendar() {
    const firstDay = new Date(this.currentYear, this.currentMonth, 1);
    const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0);
    const daysInMonth = lastDay.getDate();
    const startWeekday = firstDay.getDay(); // 0 (Sun) - 6 (Sat)

    const days: Date[] = [];

    for (let i = 0; i < startWeekday; i++) {
      days.push(new Date(0));
    }

    for (let i = 1; i <= daysInMonth; i++) {
      days.push(new Date(this.currentYear, this.currentMonth, i));
    }

    this.calendarDays = days;

    // Calculate grid height: rows * 48vp
    const rows = Math.ceil(days.length / 7);
    this.gridHeight = rows * 48;
  }

  prevMonth(jumpToEnd: boolean = false) {
    const changeAction = () => {
      let oldDay = this.selectedDate.getDate();
      if (this.currentMonth === 0) {
        this.currentMonth = 11;
        this.currentYear--;
      } else {
        this.currentMonth--;
      }
      
      // 同步更新选中日期，处理月份天数溢出（如3月31日切到2月）
      const daysInNewMonth = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
      const newDay = Math.min(oldDay, daysInNewMonth);
      this.selectedDate = new Date(this.currentYear, this.currentMonth, newDay);

      this.refreshData();
      this.generateCalendar();
    };

    if (this.isAnimationEnabled) {
      animateTo({ curve: curves.springMotion(this.animationResponse, this.animationDamping) }, changeAction);
    } else {
      changeAction();
    }

    if (this.viewMode === 1) {
      if (jumpToEnd) {
        // Calculate days in the new previous month
        const daysInMonth = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
        setTimeout(() => {
          this.timelineScroller.scrollTo({ xOffset: daysInMonth * 48, yOffset: 0, animation: false });
        }, 50);
      } else {
        setTimeout(() => {
          this.timelineScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
        }, 50);
      }
    }
  }

  nextMonth() {
    const changeAction = () => {
      let oldDay = this.selectedDate.getDate();
      if (this.currentMonth === 11) {
        this.currentMonth = 0;
        this.currentYear++;
      } else {
        this.currentMonth++;
      }

      // 同步更新选中日期
      const daysInNewMonth = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
      const newDay = Math.min(oldDay, daysInNewMonth);
      this.selectedDate = new Date(this.currentYear, this.currentMonth, newDay);

      this.refreshData();
      this.generateCalendar();
    };

    if (this.isAnimationEnabled) {
      animateTo({ curve: curves.springMotion(this.animationResponse, this.animationDamping) }, changeAction);
    } else {
      changeAction();
    }

    if (this.viewMode === 1) {
      setTimeout(() => {
        this.timelineScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      }, 50);
    }
  }

  handleDateClick(date: Date) {
    if (date.getTime() === 0) return;
    
    const changeAction = () => {
      this.selectedDate = date;
    }

    if (this.isAnimationEnabled) {
      animateTo({ curve: curves.springMotion(this.animationResponse, this.animationDamping) }, changeAction);
    } else {
      changeAction();
    }

    // 如果在时间轴模式，点击头部日期自动滚动对齐
    if (this.viewMode === 1) {
      const targetDay = date.getDate();
      const contextDays = 1.5;
      const xOffset = Math.max(0, (targetDay - 1 - contextDays) * 48);
      this.timelineScroller.scrollTo({ xOffset: xOffset, yOffset: 0, animation: this.isAnimationEnabled });
    }
  }

  getItemPriceInfo(item: SubscriptionModel): string {
    if (item.recordType === 'warranty') {
      const days = DateUtil.getDaysUntil(item.nextBillingDate);
      return days < 0 ? '已过保' : '在保中';
    }
    if (item.recordType === 'card') {
      let info = item.cardType || '卡证';
      if (item.cardBalance !== undefined && item.cardBalance !== null && item.cardBalance !== 0) {
        info += ` · 余额: ${item.cardBalance}`;
      }
      return info;
    }
    let info = `¥${item.price.toFixed(2)}`;
    if (item.recordType === 'groupBuy') {
      // 如果项目名存在且与标题（商家名）不同，则在副标题显示项目名
      if (item.name && item.name !== item.merchantName) {
        info += ` · ${item.name}`;
      } else if (item.subCategory) {
        info += ` · ${item.subCategory}`;
      }
    } else if (item.subCategory) {
      info += ` · ${item.subCategory}`;
    }
    return info;
  }

  getItemCycleTag(item: SubscriptionModel): string {
    if (item.recordType === 'groupBuy') {
      return '团购';
    } else if (item.recordType === 'warranty') {
      const days = DateUtil.getDaysUntil(item.nextBillingDate);
      return days < 0 ? '过保' : '在保';
    } else if (item.recordType === 'card') {
      return '卡证';
    }
    switch (item.billingCycle) {
      case 'Monthly':
        return '月付';
      case 'Quarterly':
        return '季付';
      case 'Yearly':
        return '年付';
      case 'Lifetime':
        return '永久';
      case 'Indefinite':
        return '不定';
      default:
        return '月付';
    }
  }

  @Builder
  SubscriptionList() {
    Column() {
      Divider()
        .color($r('app.color.divider_color'))
        .width('100%')
        .strokeWidth(1)
        .margin({ top: 12, bottom: 12 })

      Text(`${this.selectedDate.getMonth() + 1}月${this.selectedDate.getDate()}日 扣款详情`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      List() {
        if ((this.dailySubscriptions.get(this.selectedDate.getDate())?.length ?? 0) === 0) {
          ListItem() {
            Column() {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(40)
                .fontColor([$r('app.color.text_secondary')])
                .margin({ bottom: 12 })
              Text("今日无扣款")
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 40 })
            .justifyContent(FlexAlign.Start)
          }
        } else {
          ForEach(this.dailySubscriptions.get(this.selectedDate.getDate()) || [], (item: SubscriptionModel) => {
            ListItem() {
              Row() {
                SubscriptionIcon({
                  icon: item.recordType === 'groupBuy' ? this.getGroupBuyIcon(item) : item.icon,
                  name: item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name,
                  iconSize: 44,
                  iconRadius: 12,
                  showGroupBadge: item.recordType === 'groupBuy',
                  showWarrantyBadge: item.recordType === 'warranty',
                  showCardBadge: item.recordType === 'card',
                  showServiceBadge: item.recordType !== 'groupBuy' && item.recordType !== 'warranty' && item.recordType !== 'card'
                })

                Column() {
                  Text(item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.getItemPriceInfo(item))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 16 })
                .layoutWeight(1)

                Text(this.getItemCycleTag(item))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(6)
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.card_background')) // Explicit background for interaction
              .borderRadius(16)
              .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedListId === (item.id ?? -1)) ? 0.96 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedListId === (item.id ?? -1)) ? 0.96 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                sourceType: (this.isPointLightEnabled && this.pressedListId === (item.id ?? -1)) ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              }).buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) { this.pressedListId = item.id ?? -1; }
                else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressedListId = -1; }
              })
              .margin({ bottom: 8 })
            }
          })
        }
        // 底部安全留白，确保 FAB 不遮挡列表
        ListItem() {
          Column().height(100)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring) // 独立垂直回弹
      .scrollBar(BarState.Off)
      .opacity(this.animStep3 ? 1 : 0)
      .translate({ y: this.animStep3 ? 0 : 20 })
      .animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
    }
    .width('100%')
    .layoutWeight(1) // 占据剩余空间
    .padding({ left: 16, right: 16 })
    .id(`list-${this.currentYear}-${this.currentMonth}-${this.selectedDate.getDate()}`) // 关键：ID 变化触发过渡
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 40 })).animation({ duration: this.isAnimationEnabled ? 300 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) }), // 入场
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -40 })).animation({ duration: this.isAnimationEnabled ? 300 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) }) // 出场
    ))
  }

  getDayGradient(date: Date): LinearGradientValue {
    if (DateUtil.isSameDay(date, this.selectedDate)) {
      if (this.isNewYearTheme) {
        return {
          angle: 135,
          colors: [[$r('app.color.new_year_red_start'), 0.0],
            [$r('app.color.new_year_red_end'), 1.0]] as [ResourceColor, number][]
        };
      } else if (this.showVipTheme) {
        return {
          angle: 135,
          colors: [[$r('app.color.vip_gold_start'), 0.0],
            [$r('app.color.vip_gold_end'), 1.0]] as [ResourceColor, number][]
        };
      } else {
        return {
          angle: 0,
          colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]] as [ResourceColor, number][]
        };
      }
    }
    return {
      angle: 0,
      colors: [[Color.Transparent, 0.0], [Color.Transparent, 1.0]] as [ResourceColor, number][]
    };
  }

  getDayFontColor(date: Date): ResourceColor {
    if (DateUtil.isSameDay(date, this.selectedDate)) {
      if (this.isNewYearTheme) return $r('app.color.new_year_text_on_red');
      if (this.showVipTheme) return $r('app.color.vip_text_on_gold');
      return Color.White;
    }
    if (DateUtil.isSameDay(date, new Date())) {
      return this.getTodayThemeColor();
    }
    return $r('app.color.text_primary');
  }

  getDayDotFill(date: Date): ResourceColor {
    if (DateUtil.isSameDay(date, this.selectedDate)) {
      if (this.isNewYearTheme) return $r('app.color.new_year_text_on_red');
      if (this.showVipTheme) return $r('app.color.vip_text_on_gold');
      return Color.White;
    }
    if (this.isNewYearTheme) return $r('app.color.new_year_red_start');
    if (this.showVipTheme) return $r('app.color.vip_gold');
    return $r('app.color.brand_color');
  }

  @Builder
  CalendarGridBuilder() {
    Column() {
      Grid() {
        ForEach(this.calendarDays, (date: Date, index: number) => {
          GridItem() {
            if (date.getTime() !== 0) {
              Column() {
                Text(date.getDate().toString())
                  .fontSize(16)
                  .fontWeight(DateUtil.isSameDay(date, this.selectedDate) ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.getDayFontColor(date))

                // Dots for subscriptions
                Row({ space: 2 }) {
                  ForEach(this.dailySubscriptions.get(date.getDate()) || [], (sub: SubscriptionModel, idx: number) => {
                    if (idx < 3) {
                      Circle().width(4).height(4).fill(this.getDayDotFill(date))
                    }
                  })
                }
                .margin({ top: 4 })
                .height(4)
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .borderRadius(12)
              .linearGradient(this.getDayGradient(date))
              .backgroundColor(Color.Transparent)
              .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedGridDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? 0.9 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedGridDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? 0.9 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                sourceType: (this.isPointLightEnabled && this.pressedGridDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? hdsEffect.PointLightSourceType.SOFT  : hdsEffect.PointLightSourceType.NONE,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              }).buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedGridDate = `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedGridDate = '';
                }
              })
              .onClick(() => this.handleDateClick(date))
            }
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .width('100%')
      .height(this.gridHeight)
      .padding({ left: 16, right: 16 })
      .id(`grid-${this.currentYear}-${this.currentMonth}`) // 关键：ID变化触发过渡
      .transition(TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 40 })).animation({ duration: this.isAnimationEnabled ? 300 : 0 }), // 入场：轻微右滑淡入
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -40 })).animation({ duration: this.isAnimationEnabled ? 300 : 0 }) // 出场：向左淡出
      ))
    }
  }

  // 逻辑：基于剩余天数反推当前周期的起始日
  getSubscriptionRange(sub: SubscriptionModel): SubscriptionRange | null {
      // Group Buy: Forward to calculateRangeFromStartDate to show full validity even if used
      // But in Monthly/Status logic, we still respect usage status for markers.
      // Here we want the BAR to be visible for the whole validity.
      if (sub.recordType === 'groupBuy' || sub.recordType === 'warranty' || sub.recordType === 'card') {
           return this.calculateRangeFromStartDate(sub);
      }

      // 特殊处理：永久会员
      if (sub.billingCycle === 'Lifetime') {
        if (!sub.nextBillingDate) return null;

        const purchaseDate = new Date(sub.nextBillingDate);
        purchaseDate.setHours(0, 0, 0, 0);

        const viewStart = new Date(this.currentYear, this.currentMonth, 1);
        const viewEnd = new Date(this.currentYear, this.currentMonth + 1, 0);

        // 如果购买日期在当前视图月之后，不显示
        if (purchaseDate > viewEnd) return null;

        // 起点计算：如果是购买月，起于具体日期；否则起于月初
        const start = purchaseDate < viewStart ? 1 : purchaseDate.getDate();

        return {
          start: start,
          end: viewEnd.getDate(), // 永久项目终点始终为月末（表示持续）
          isCurrentMonth: true
        };
      }

      // 特殊处理：不定周期
      // 逻辑：严格遵循 startDate 到 nextBillingDate 的区间，仅在这个区间内画条
      if (sub.billingCycle === 'Indefinite') {
        if (!sub.startDate || !sub.nextBillingDate) return null;

        const startFull = new Date(sub.startDate);
        const endFull = new Date(sub.nextBillingDate);
        startFull.setHours(0, 0, 0, 0);
        endFull.setHours(23, 59, 59, 999);

        const viewStart = new Date(this.currentYear, this.currentMonth, 1);
        const viewEnd = new Date(this.currentYear, this.currentMonth + 1, 0, 23, 59, 59, 999);

        // 如果区间完全不在当前月内
        if (startFull > viewEnd || endFull < viewStart) return null;

        // 计算交集并转为当日日期
        const intersectStart = startFull > viewStart ? startFull : viewStart;
        const intersectEnd = endFull < viewEnd ? endFull : viewEnd;

        return {
          start: intersectStart.getDate(),
          end: intersectEnd.getDate(),
          isCurrentMonth: true
        };
      }

    // [Refactor] Use startDate for forward projection if available
    if (sub.startDate) {
      return this.calculateRangeFromStartDate(sub);
    }

    // --- Fallback: Backward inference (Old Logic) ---
    // 逻辑：基于剩余天数反推当前周期的起始日
    // 规则：Start = NextBilling - ceil(Remaining / CycleDays) * CycleDays

    if (!sub.nextBillingDate) return null;

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const viewYear = this.currentYear;
    const viewMonth = this.currentMonth;

    // 视图起止
    const viewStart = new Date(viewYear, viewMonth, 1);
    const viewEnd = new Date(viewYear, viewMonth + 1, 0);

    // 计算 NextBillingDate (End)
    const validEnd = new Date(sub.nextBillingDate);
    validEnd.setHours(23, 59, 59, 999);

    // 计算剩余天数 (End - Today)
    const diffTime = validEnd.getTime() - today.getTime();
    const remainingDays = Math.ceil(diffTime / (1000 * 3600 * 24));

    // 确定周期天数
    const cycleDays = this.getCycleDays(sub);

    // 计算需要回溯的周期数
    // 如果剩余天数 <= 0 (已过期)，至少回溯1个周期显示历史
    const cyclesNeeded = remainingDays > 0 ? Math.ceil(remainingDays / cycleDays) : 1;

    // 计算起始日期 (ValidStart)
    const validStart = new Date(validEnd);
    validStart.setDate(validStart.getDate() - (cyclesNeeded * cycleDays));
    validStart.setHours(0, 0, 0, 0);

    // 交集计算
    let intersectStart = validStart > viewStart ? validStart : viewStart;
    let intersectEnd = validEnd < viewEnd ? validEnd : viewEnd;

    if (intersectStart > intersectEnd) {
      return null;
    }

    return {
      start: intersectStart.getDate(),
      end: intersectEnd.getDate(),
      isCurrentMonth: true
    };
  }

  /**
   * New Logic: Calculate range based on fixed startDate
   * Projects cycles forward: startDate + n * cycleDays
   * Now respects nextBillingDate as the expiration boundary
   */
  calculateRangeFromStartDate(sub: SubscriptionModel): SubscriptionRange | null {
    if (!sub.startDate) return null;

    const startDate = new Date(sub.startDate);
    startDate.setHours(0, 0, 0, 0);

    const viewStart = new Date(this.currentYear, this.currentMonth, 1);
    const viewEnd = new Date(this.currentYear, this.currentMonth + 1, 0);
    viewEnd.setHours(23, 59, 59, 999);

    if (startDate > viewEnd) return null; // Subscription hasn't started yet

    // Determine expiration date
    let expirationDate: Date | null = null;
    if (sub.nextBillingDate) {
      expirationDate = new Date(sub.nextBillingDate);
      expirationDate.setHours(23, 59, 59, 999);
      if (viewStart > expirationDate) {
        return null;
      }
    }

    // Determine semantic cycle arithmetic
    let addPeriod: (d: Date, n: number) => Date;
    if (sub.billingCycle === 'Quarterly') {
      addPeriod = (d, n) => DateUtil.safeAddMonth(d, n * 3);
    } else if (sub.billingCycle === 'Yearly') {
      addPeriod = (d, n) => DateUtil.safeAddYear(d, n);
    } else {
      addPeriod = (d, n) => DateUtil.safeAddMonth(d, n);
    }

    // Algorithm: Find ALL cycles that intersect with [viewStart, viewEnd] and Union them.
    // Since cycles are contiguous, the union will be [MinStart, MaxEnd] clamped to view.

    let minIntersectStart: Date | null = null;
    let maxIntersectEnd: Date | null = null;

    // 1. Where to start searching?
    // Estimate cycles relative to ViewStart
    let cyclesEstimate = 0;
    if (sub.billingCycle === 'Yearly') {
       cyclesEstimate = Math.floor((viewStart.getFullYear() - startDate.getFullYear()));
    } else {
       const monthsDiff = (viewStart.getFullYear() - startDate.getFullYear()) * 12 + (viewStart.getMonth() - startDate.getMonth());
       if (sub.billingCycle === 'Quarterly') {
          cyclesEstimate = Math.floor(monthsDiff / 3);
       } else {
          cyclesEstimate = monthsDiff;
       }
    }
    
    // Start a bit earlier to catch straddling cycles
    let n = Math.max(0, cyclesEstimate - 1);

    // Iteration limit to prevent infinite loops (e.g. if cycle is super short or something wrong)
    // 5 iterations should cover any month view (max 2-3 cycles per month usually)
    for (let i = 0; i < 12; i++) {
        const cycleStart = addPeriod(startDate, n);
        const nextCycleStart = addPeriod(startDate, n + 1);
        
        // Cycle End is (NextStart - 1 ms or 1 day). Visual range is inclusive.
        // Let's take (NextStart - 1 day) for date inclusive.
        const cycleEnd = new Date(nextCycleStart);
        cycleEnd.setDate(cycleEnd.getDate() - 1);
        cycleEnd.setHours(23, 59, 59, 999);

        // Check intersection with View
        if (cycleEnd >= viewStart && cycleStart <= viewEnd) {
            // Apply Expiration to this specific cycle
             let actualCycleEnd = cycleEnd;
             if (expirationDate && actualCycleEnd > expirationDate) {
                 actualCycleEnd = expirationDate;
             }

             // Re-check valid (in case expiration killed it)
             if (cycleStart <= actualCycleEnd) {
                 // Update Union Bounds
                 if (!minIntersectStart || cycleStart < minIntersectStart) {
                     minIntersectStart = cycleStart;
                 }
                 if (!maxIntersectEnd || actualCycleEnd > maxIntersectEnd) {
                     maxIntersectEnd = actualCycleEnd;
                 }
             }
        }
        
        // Break if we've passed the view
        if (cycleStart > viewEnd) {
            break;
        }
        n++;
    }

    if (!minIntersectStart || !maxIntersectEnd) {
        return null;
    }

    // Clamp Union to View
    const finalStart = minIntersectStart > viewStart ? minIntersectStart : viewStart;
    const finalEnd = maxIntersectEnd < viewEnd ? maxIntersectEnd : viewEnd;

    if (finalStart > finalEnd) return null;

    return {
      start: finalStart.getDate(),
      end: finalEnd.getDate(),
      isCurrentMonth: true
    };
  }

  getCycleDays(sub: SubscriptionModel): number {
    switch (sub.billingCycle) {
      case 'Quarterly':
        return 90;
      case 'Yearly':
        return 365;
      case 'Lifetime':
        return 36500;
      default:
        return 30; // Monthly or others
    }
  }

  // 获取"今天"在时间轴上的 X 轴偏移量
  getTodayOffset(): number | null {
    const today = this.currentTime;
    if (today.getFullYear() !== this.currentYear || today.getMonth() !== this.currentMonth) {
      return null;
    }
    const day = today.getDate();
    // Use filtered days to match visual layout
    const validDays = this.calendarDays.filter(d => d.getTime() !== 0);
    const index = validDays.findIndex(d =>
    d.getDate() === day &&
      d.getMonth() === this.currentMonth &&
      d.getFullYear() === this.currentYear
    );

    if (index !== -1) {
      const hours = today.getHours();
      const minutes = today.getMinutes();
      const seconds = today.getSeconds();
      // Ultra-Precision Algorithm: (hour + min/60 + sec/3600) * (ColumnWidth / 24)
      // ColumnWidth = 48vp
      const totalSecondsInDay = 86400;
      const currentSeconds = hours * 3600 + minutes * 60 + seconds;
      // 这里的 48 必须和 Header 的单项总宽度严格一致
      const timeOffset = (currentSeconds / totalSecondsInDay) * 48;
      // 补偿 1vp 的线宽，使其物理中心对齐
      // 12:00 = 24vp, 正好是 48vp 的几何中心
      return index * 48 + timeOffset;
    }
    return null;
  }

  // 丰富多彩的渐变色板 (24色)
  private barColors: [string, string][] = [
    ['#3B82F6', '#60A5FA'], // Blue
    ['#10B981', '#34D399'], // Green
    ['#8B5CF6', '#A78BFA'], // Purple
    ['#F59E0B', '#FBBF24'], // Amber
    ['#EC4899', '#F472B6'], // Pink
    ['#EF4444', '#F87171'], // Red
    ['#059669', '#10B981'], // Emerald
    ['#6366F1', '#818CF8'], // Indigo
    ['#F97316', '#FDBA74'], // Orange
    ['#14B8A6', '#5EEAD4'], // Teal
    ['#06B6D4', '#67E8F9'], // Cyan
    ['#64748B', '#94A3B8'], // Slate
    ['#D946EF', '#E879F9'], // Fuchsia
    ['#84CC16', '#A3E635'], // Lime
    ['#FBBF24', '#FDE68A'], // Amber Light
    ['#A855F7', '#C084FC'], // Purple Light
    ['#22C55E', '#86EFAC'], // Green Light
    ['#0EA5E9', '#7DD3FC'], // Sky
    ['#EAB308', '#FDE047'], // Yellow
    ['#F43F5E', '#FDA4AF'], // Rose
    ['#4F46E5', '#818CF8'], // Indigo Dark
    ['#DB2777', '#F472B6'], // Pink Dark
    ['#0D9488', '#5EEAD4'], // Teal Dark
    ['#7C3AED', '#A78BFA']// Violet
  ];

  getBarGradient(sub: SubscriptionModel): LinearGradientValue {
    // 确定性哈希算法：确保同一个 App 名字总是对应同一个颜色
    let hash = 0;
    const str = sub.name || '';
    for (let i = 0; i < str.length; i++) {
      hash = str.charCodeAt(i) + ((hash << 5) - hash);
    }

    const index = Math.abs(hash) % this.barColors.length;
    const colors = this.barColors[index];
    return {
      angle: 90,
      colors: [[colors[0], 0.0], [colors[1], 1.0]]
    };
  }

  getTodayThemeColor(): ResourceColor {
    if (this.isNewYearTheme) return $r('app.color.new_year_red_start');
    if (this.showVipTheme) return $r('app.color.vip_gold');
    return $r('app.color.brand_color');
  }

  getGroupBuyIcon(sub: SubscriptionModel): string {
    if (sub.platform === 'meituan') return 'resource:meituan_logo';
    if (sub.platform === 'douyin') return 'resource:douyin_logo';
    if (sub.platform === 'dianping') return 'resource:dianping_logo';
    return sub.icon ?? '';
  }

  getTodayThemeBgColor(): ResourceColor {
    if (this.isNewYearTheme) return 'rgba(217, 48, 37, 0.1)';
    if (this.showVipTheme) return 'rgba(230, 192, 123, 0.15)';
    // Use brand color with alpha for default background
    return 'rgba(64, 128, 255, 0.1)';
  }

  @Builder
  TimelineViewBuilder() {
    // 外层：横向滚动 (Timeline Scroller)
    Scroll(this.timelineScroller) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          // Spacer for Header (Removed)

          // 1. 日期刻度 Header (固定在顶部)
          Row({ space: 0 }) {
            // Filter invalid dates first to ensure index matches visual layout
            ForEach(this.calendarDays.filter((d: Date) => d.getTime() !== 0), (date: Date, index: number) => {
              Column() {
                Text(date.getDate().toString())
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getDayFontColor(date))

                Text(['日', '一', '二', '三', '四', '五', '六'][date.getDay()])
                  .fontSize(10)
                  .fontColor(DateUtil.isSameDay(date, this.selectedDate) ? this.getDayFontColor(date) :
                    $r('app.color.text_secondary'))
                  .margin({ top: 2 })
              }
              .width(48) // Fixed 48vp to match math
              .height(48)
              .justifyContent(FlexAlign.Center)
              .borderRadius(12)
              .linearGradient(this.getDayGradient(date))
              .backgroundColor(DateUtil.isSameDay(date, new Date()) && !DateUtil.isSameDay(date, this.selectedDate) ?
                this.getTodayThemeBgColor() : Color.Transparent)
              .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedTimelineDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? 0.9 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedTimelineDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? 0.9 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                sourceType: (this.isPointLightEnabled && this.pressedTimelineDate === `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`) ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              }).buildEffect())
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) { this.pressedTimelineDate = `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`; }
                else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressedTimelineDate = ''; }
              })
              .onClick(() => this.handleDateClick(date))
            })
          }
          .height(56)
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .shadow({ radius: 4, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
          .margin({ bottom: 8 })
          .width(this.calendarDays.filter(d => d.getTime() !== 0).length * 48)

          // 2. 纵向滚动列表 (订阅内容)
          // 使用 List 替代 Column 以支持内部纵向滚动
          List() {
            ForEach(this.subscriptions, (sub: SubscriptionModel) => {
              if (this.getSubscriptionRange(sub)) {
                ListItem() {
                  Stack({ alignContent: Alignment.TopStart }) {
                    // 1. 背景条 (Background Bar)
                    if (sub.recordType === 'groupBuy') {
                      // Group Buy: 连续底条（不可用区间用淡色）+ 可用区间用亮色叠加
                      // 1.1 底层：完整的连续淡色条（表示整个有效期）
                      Row()
                        .width(this.getBarWidth(sub))
                        .height(40)
                        .backgroundColor(this.isNewYearTheme ? 'rgba(200,100,100,0.3)' : (this.showVipTheme ? 'rgba(180,150,80,0.3)' : 'rgba(100,100,100,0.4)'))
                        .borderRadius(8)
                        .position({ x: this.getBarMarginLeft(sub), y: 0 })

                      // 1.2 上层：可用区间用亮色叠加
                      ForEach(this.getGroupBuySegments(sub), (seg: GroupBuySegment) => {
                         Row()
                          .width(seg.width)
                          .height(40) // 统一高度
                          .backgroundColor(seg.isConsumed ? Color.Transparent : (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))))
                          .opacity(seg.isConsumed ? 0.3 : 0.9)
                          .borderRadius(8)
                          .border(seg.isConsumed ? { 
                             width: 1.5, 
                             color: (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))), 
                             style: BorderStyle.Dashed,
                             radius: 8
                          } : undefined)
                          .shadow(seg.isConsumed ? undefined : { radius: 4, color: 'rgba(0,0,0,0.1)', offsetY: 1 })
                          .clip(true) // 强制裁剪，确保圆角生效
                          .position({ x: seg.left, y: 0 }) // 统一 y 坐标为 0
                      })
                    } else {
                      // Standard Subscription: Continuous Bar
                      Row()
                        .width(this.getBarWidth(sub))
                        .height(40)
                        .linearGradient(this.getBarGradient(sub))
                        .borderRadius(8)
                        .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetY: 2 })
                        .position({ x: this.getBarMarginLeft(sub), y: 0 })
                    }

                    // 2. 内容层 (Content Layer)
                    Row() {
                      SubscriptionIcon({
                        icon: sub.recordType === 'groupBuy' ? this.getGroupBuyIcon(sub) : sub.icon,
                        name: sub.recordType === 'groupBuy' ? (sub.merchantName || sub.name) : sub.name,
                        iconSize: 28,
                        showGroupBadge: sub.recordType === 'groupBuy',
                        showWarrantyBadge: sub.recordType === 'warranty',
                        showCardBadge: sub.recordType === 'card',
                        showServiceBadge: sub.recordType !== 'groupBuy' && sub.recordType !== 'warranty' && sub.recordType !== 'card'
                      })
                        .margin({ right: 8 })

                      if (this.shouldShowText(sub)) {
                        Column() {
                          Text(sub.recordType === 'groupBuy' ? (sub.merchantName || sub.name) : sub.name)
                            .fontSize(14)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(Color.White)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })

                          Text(this.getItemPriceInfo(sub))
                            .fontSize(11)
                            .fontWeight(FontWeight.Normal)
                            .fontColor('rgba(255,255,255,0.9)')
                            .margin({ top: 2 })
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                      }
                    }
                    .alignItems(VerticalAlign.Center)
                    .padding({
                      left: 12,
                      right: 12,
                      top: 6,
                      bottom: 6
                    })
                    .height(40)
                    .margin({ left: this.getSafeStickyPadding(sub) })
                    .width(this.getSafeStickyWidth(sub))
                    .clip(true)
                    .hitTestBehavior(HitTestMode.None)
                    // 关键：不设置宽度，让它自然撑开
                  }
                  .height(52) // Item container height (includes spacing)
                  .width(this.calendarDays.filter(d => d.getTime() !== 0).length * 48) // 强制撑满横向对应的总天数宽度
                }
              }
            })
            // 底部留白
            ListItem().height(100)
          }
          .width(this.calendarDays.filter(d => d.getTime() !== 0).length * 48) // List 宽度 = 总天数宽度
          .layoutWeight(1) // 占据剩余纵向空间
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .padding(0)
        .height('100%') // 关键：撑满 ScrollView 的高度
        .width(this.calendarDays.filter(d => d.getTime() !== 0).length * 48) // Column 宽度
        .opacity(this.animStep2 ? 1 : 0)
        .translate({ y: this.animStep2 ? 0 : 20 })
        .animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })

        // 3. "Today" Indicator Line Overlay
        if (this.getTodayOffset() !== null) {
          Stack() {
            Column()
              .width(2)
              .height('100%')
              .backgroundColor(this.getTodayThemeColor())
              .opacity(0.8)
          }
          .width(2)
          .height('100%')
          .position({ x: (this.getTodayOffset() ?? 0) - 1, y: 0 })
          .zIndex(10)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .id(`timeline-${this.currentYear}-${this.currentMonth}`) // 关键：ID变化触发过渡
      .transition(TransitionEffect.OPACITY.animation({ duration: this.isAnimationEnabled ? 300 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear }))
    }
    .scrollable(ScrollDirection.Horizontal)
    .edgeEffect(EdgeEffect.Spring)
    .onScroll((xOffset: number, yOffset: number) => {
      this.timelineScrollX = this.timelineScroller.currentOffset().xOffset;
    })
    .onScrollEdge((side: Edge) => {
      if (side === Edge.End || side === Edge.Bottom) {
        this.nextMonth();
        promptAction.showToast({ message: '已切换至下个月', duration: 1500 });
      } else if (side === Edge.Start || side === Edge.Top) {
        this.prevMonth(true); // Jump to end of previous month
      }
    })
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({ duration: this.isAnimationEnabled ? 300 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear }))
  }

  getSafeStickyPadding(sub: SubscriptionModel): number {
    const barMarginLeft: number = this.getBarMarginLeft(sub);
    const barWidth: number = this.getBarWidth(sub);
    const scrollX: number = this.timelineScrollX;

    // 统一逻辑：团购券和普通订阅使用相同的悬浮计算
    if (barWidth < 120) {
      return barMarginLeft;
    }

    if (scrollX > barMarginLeft) {
      const offset: number = scrollX - barMarginLeft;
      // 保留至少100vp给文字显示
      return barMarginLeft + Math.min(offset, Math.max(0, barWidth - 100));
    }

    return barMarginLeft;
  }

  getSafeStickyWidth(sub: SubscriptionModel): number {
    const barMarginLeft: number = this.getBarMarginLeft(sub);
    const barWidth: number = this.getBarWidth(sub);
    const absolutePadding: number = this.getSafeStickyPadding(sub);

    // 统一逻辑：团购券和普通订阅使用相同的宽度计算
    const innerOffset: number = absolutePadding - barMarginLeft;
    return Math.max(0, barWidth - innerOffset);
  }

  getGroupBuyStickyPadding(sub: SubscriptionModel): number {
      const scrollX: number = this.timelineScrollX;
      const segments: GroupBuySegment[] = this.getGroupBuySegments(sub);
      const itemStart: number = this.getBarMarginLeft(sub);
      const textMinNeeded: number = 100; // 文字最小显示宽度

      for (const seg of segments) {
          const segLeft: number = itemStart + seg.left;
          const segWidth: number = seg.width;
          const segRight: number = segLeft + segWidth;

          // 跳过已经完全滚出视口的segment
          if (segRight <= scrollX) {
              continue;
          }

          // 找到第一个未滚出的segment
          // 关键逻辑：只有当scrollX真正进入segment内部才开始吸附
          if (scrollX <= segLeft) {
              // 视口左边界还在segment左边 -> 文字固定在segment起始位置
              return seg.left;
          } else {
              // 视口左边界已进入segment内部 -> 开始吸附
              const stickyOffset: number = scrollX - segLeft;
              const maxOffset: number = Math.max(0, segWidth - textMinNeeded);
              const finalOffset: number = Math.min(stickyOffset, maxOffset);
              return seg.left + finalOffset;
          }
      }
      
      return 0;
  }

  getBarMarginLeft(sub: SubscriptionModel): number {
    const range = this.getSubscriptionRange(sub);
    if (!range) return 0;
    // 强制基于裁剪后的 start 日期进行 48vp 步进对齐
    return (range.start - 1) * 48;
  }

  getBarWidth(sub: SubscriptionModel): number {
    const range = this.getSubscriptionRange(sub);
    if (!range) return 0;
    const durationDays = range.end - range.start + 1;
    return durationDays * 48;
  }

  getBarColor(sub: SubscriptionModel): ResourceColor {
    return $r('app.color.brand_color');
  }

  shouldShowText(sub: SubscriptionModel): boolean {
    const range = this.getSubscriptionRange(sub);
    if (!range) return false;

    // 获取当月最后一天
    const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
    
    // 判断是否在时间轴边缘 (最后一天)
    const isEdge = range.end === lastDay;
    const duration = range.end - range.start + 1;

    // 如果在边缘且时长极短 (只有1天)，则隐藏文字，避免显示不全
    // 2天及以上 (>=96vp) 允许显示跑马灯
    if (isEdge && duration < 2) {
      return false;
    }
    return true;
  }

  getTextMaxWidth(sub: SubscriptionModel): number | undefined {
    const range = this.getSubscriptionRange(sub);
    if (!range) return undefined;

    const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0).getDate();
    const isEdge = range.end === lastDay;
    
    if (isEdge) {
      // 边缘项强制限制宽度，触发 Marquee
      // 宽度 = Bar总宽 - (PaddingLeft 12 + PaddingRight 12 + Icon 28 + MarginRight 8) = Bar - 60
      const barWidth = (range.end - range.start + 1) * 48;
      // 至少保留 20vp，防止算出来负数
      return Math.max(20, barWidth - 60);
    }
    return undefined; // 中间项允许自然溢出
  }

  showDatePicker() {
    // 限制只能选择从当前月开始
    const now = new Date();
    const minDate = new Date(now.getFullYear(), now.getMonth(), 1);

    DatePickerDialog.show({
      // start: minDate,
      end: new Date("2099-12-31"),
      selected: new Date(this.currentYear, this.currentMonth, 1),
      onAccept: (value: DatePickerResult) => {
        // value.month is 0-indexed (0-11)
        if (value.year !== undefined) this.currentYear = value.year;
        if (value.month !== undefined) this.currentMonth = value.month;
        const targetDay = value.day ?? 1;

        // Update selectedDate so Grid View highlights it
        this.selectedDate = new Date(this.currentYear, this.currentMonth, targetDay);

        this.generateCalendar();
        this.refreshData();

        // 选中日期后，自动滚动到该日期位置
        if (this.viewMode === 1) {
          // 目标 X 坐标：(日期-1) * 48
          // 为了视觉体验，往回退 1-2 天作为缓冲，让选中日期不要顶格显示
          const contextDays = 1.5;
          const xOffset = Math.max(0, (targetDay - 1 - contextDays) * 48);

          // 使用 setTimeout 确保 UI 渲染完成后再滚动
          setTimeout(() => {
            this.timelineScroller.scrollTo({ xOffset: xOffset, yOffset: 0, animation: this.isAnimationEnabled });
          }, 50);
        }
      }
    })
  }

  @Builder
  CalendarHeader() {
    Column() {
      // Row 1: Date Nav & Date Picker Trigger
      Row() {
        // Date Display & Picker Trigger
        Row() {
           Text(`${this.currentYear}年${this.currentMonth + 1}月`)
             .fontSize(18)
             .fontWeight(FontWeight.Bold)
             .fontColor($r('app.color.text_primary'))
           
           SymbolGlyph($r('sys.symbol.chevron_down'))
             .fontSize(14)
             .fontColor([$r('app.color.text_secondary')])
             .margin({ left: 4 })
        }
        .padding({ left: 12, right: 8, top: 6, bottom: 6 })
        .backgroundColor('rgba(0,0,0,0.05)')
        .borderRadius(16)
        .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.isDatePickerPressed) ? 0.95 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.isDatePickerPressed) ? 0.95 : 1 })
        .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
        .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
          sourceType: (this.isPointLightEnabled && this.isDatePickerPressed) ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        }).buildEffect())
        .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent) => {
          return GestureJudgeResult.CONTINUE;
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isDatePickerPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isDatePickerPressed = false;
          }
        })
        .onClick(() => this.showDatePicker())

        Blank()

        // Navigation Arrows
        Row({ space: 12 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.isPrevMonthPressed) ? 0.9 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.isPrevMonthPressed) ? 0.9 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.isPrevMonthPressed = true; }
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.isPrevMonthPressed = false; }
          })
          .onClick(() => this.prevMonth())
          
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(24)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.isNextMonthPressed) ? 0.9 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.isNextMonthPressed) ? 0.9 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.isNextMonthPressed = true; }
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.isNextMonthPressed = false; }
          })
          .onClick(() => this.nextMonth())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 12 })
      .opacity(this.animStep1 ? 1 : 0)
      .translate({ y: this.animStep1 ? 0 : -10 })
      .animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })

      // Row 2: View Mode Switcher
      Row() {
        ForEach(["月视图", "时间轴"], (label: string, index: number) => {
          Button() {
            Text(label)
              .fontSize(14)
              .fontWeight(this.viewMode === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.viewMode === index ?
                (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                $r('app.color.text_secondary'))
          }
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height('100%')
          .linearGradient(this.viewMode === index ?
            (this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
            (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } : undefined)) : undefined)
          .backgroundColor(this.viewMode === index ?
            (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
            Color.Transparent)
          .borderRadius(14)
          .scale({ x: (this.isAnimationEnabled && this.isPointLightEnabled && this.isViewModePressed === index) ? 0.96 : 1, y: (this.isAnimationEnabled && this.isPointLightEnabled && this.isViewModePressed === index) ? 0.96 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 200 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
          .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
            sourceType: (this.isPointLightEnabled && this.isViewModePressed === index) ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          }).buildEffect())
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) { this.isViewModePressed = index; }
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.isViewModePressed = -1; }
          })
          .onClick(() => {
            if (this.isAnimationEnabled) {
              const springCurve: ICurve = curves.springMotion(this.animationResponse, this.animationDamping);
              animateTo({ duration: this.animationDuration, curve: springCurve }, () => {
                this.viewMode = index;
              })
            } else {
              this.viewMode = index;
            }
            if (index === 1) {
              this.timelineScrollX = 0;
              this.timelineScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
            }
          })
        })
      }
      .width('100%')
      .height(36)
      .backgroundColor('rgba(118, 118, 128, 0.12)')
      .borderRadius(16)
      .padding(2)
      .opacity(this.animStep1 ? 1 : 0)
      .translate({ y: this.animStep1 ? 0 : 10 })
      .animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  MonthViewLayout() {
    Column() {
      // 1. 日历主体部分（含毛玻璃蒙版）
      Column() {
        // 星期表头
        Row() {
          ForEach(['日', '一', '二', '三', '四', '五', '六'], (day: string) => {
            Text(day)
              .width('14.2%')
              .textAlign(TextAlign.Center)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 16, bottom: 12 })

        // 日历网格
        this.CalendarGridBuilder()
      }
      .width('100%')
      .backgroundBlurStyle(BlurStyle.Thick, { colorMode: ThemeColorMode.SYSTEM, adaptiveColor: AdaptiveColor.DEFAULT, scale: 0.1 })
      .backgroundColor(Color.Transparent) // 完全透明，仅保留毛玻璃
      .borderRadius(24) // 全圆角
      .shadow({ radius: 12, color: 'rgba(0,0,0,0.05)', offsetY: 4 })
      .margin({ top: 4, left: 16, right: 16 }) // 调整间距，向上延伸感通过层级体现
      .padding({ bottom: 12 })

      // 2. 独立滚动的订阅列表（无毛玻璃）
      this.SubscriptionList()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .opacity(this.animStep2 ? 1 : 0)
    .translate({ y: this.animStep2 ? 0 : 20 })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({ duration: this.isAnimationEnabled ? 300 : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear }))
    .animation({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear })
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder CalendarBuilder(){
    Column() {
      // 1. Persistent Header (Date Nav + View Switcher)
      this.CalendarHeader()

      // 2. Content Area
      Stack() {
        if (this.viewMode === 0) {
          this.MonthViewLayout()
        } else {
          this.TimelineViewBuilder()
        }
      }
      .layoutWeight(1)
      .width('100%')

      // Help Popup Anchor (Invisible)
      Text("")
        .bindPopup(this.showHelpPopup, {
          builder: this.InfoPopup,
          placement: Placement.BottomRight, // Show from top right
          mask: false,
          onStateChange: (event: PopupEvent) => {
            if (!event.isVisible) {
              this.showHelpPopup = false;
            }
          }
        })
        .position({ x: '100%', y: 0 }) // Top Right below Title Bar
    }
    .width('100%')
    .height('100%')
    .padding({ top: TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight) })
    .backgroundColor(Color.Transparent)
  }
  build() {

      HdsNavDestination() {
          this.CalendarBuilder()
      }
      .hideBackButton(true)
      .hideTitleBar(false)
      .backgroundColor(Color.Transparent)
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: { mainTitle: '订阅日历' },
          menu: {
            value: [
              {
                content: {
                  label: '提醒管理',
                  icon: $r('sys.symbol.questionmark_circle'),
                  action: (): void => {
                    this.showHelpPopup = !this.showHelpPopup
                  }
                }
              } as HdsNavigationMenuItemOptions,
            ]
          }
        },
        style:(deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
          },
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(20)
          }
        }:undefined
      })

  }
  // Helper: Parse usage time text to day indices (0=Sun, 1=Mon...6=Sat)
  parseUsageDays(usageTime: string): number[] {
    const days: Set<number> = new Set();
    if (!usageTime) return [];

    const str = usageTime.trim();
    
    // Keywords
    if (str.includes('每天') || str.includes('每日') || str.includes('全周')) {
       return [0, 1, 2, 3, 4, 5, 6];
    }
    if (str.includes('工作日')) {
       [1, 2, 3, 4, 5].forEach(d => days.add(d));
    }
    if (str.includes('周末')) {
       days.add(0); days.add(6);
    }
    
    // Day Mappings
    const map: Record<string, number> = {
      '周日': 0, '周一': 1, '周二': 2, '周三': 3, '周四': 4, '周五': 5, '周六': 6,
      '星期日': 0, '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4, '星期五': 5, '星期六': 6
    };

    // Regex to find "周X" or "星期X"
    // Handle "至" range: e.g. "周一至周五"
    const rangeRegex = /(周|星期)([一二三四五六日])\s*至\s*(周|星期)([一二三四五六日])/g;
    let match: RegExpExecArray | null;
    
    // Replace ranges with explicit days for simpler parsing or handle ranges directly
    // Let's handle ranges first
    while ((match = rangeRegex.exec(str)) !== null) {
       const startKey = match[1] + match[2];
       const endKey = match[3] + match[4];
       const start = map[startKey];
       const end = map[endKey];
       
       if (start !== undefined && end !== undefined) {
          if (start <= end) {
             for (let i = start; i <= end; i++) days.add(i);
          } else {
             // Wrap around? e.g. Fri to Mon. Assume valid range usually.
             // If Fri(5) to Mon(1), assume 5,6,0,1? Or just 5..6, 0..1?
             // Simple loop
             for (let i = start; i <= 6; i++) days.add(i);
             for (let i = 0; i <= end; i++) days.add(i);
          }
       }
    }
    
    // Handle single days (check all keys)
    Object.keys(map).forEach(key => {
       if (str.includes(key) && !str.match(new RegExp(key + '\\s*至'))) { // primitive negative lookahead simulation or just add all
          // Issue: "周一至周五" contains "周一" and "周五". 
          // If we already added range, adding doubles is fine (Set handles it).
          // But strict regex logic is better.
          // Using Set, so adding duplicates is safe.
          if (str.includes(key)) {
             days.add(map[key]);
          }
       }
    });

    return Array.from(days).sort();
  }



  // Helper: Calculate visual segments for Group Buy Timeline
  getGroupBuySegments(sub: SubscriptionModel): GroupBuySegment[] {
     // Append _v4 to force cache invalidation for new rounded logic
     const cacheKey = `${sub.id}_${sub.uuid}_${this.currentYear}_${this.currentMonth}_${sub.usageStatus}_${sub.realUsageTime || 0}_v4`;
     if (this.groupBuySegmentsCache.has(cacheKey)) {
        return this.groupBuySegmentsCache.get(cacheKey)!;
     }
 
     const range = this.getSubscriptionRange(sub);
     if (!range) return [];
     
     const validDays = this.parseUsageDays(sub.usageTime || '');
     const usageDate = (sub.usageStatus === 'used' && sub.realUsageTime) ? new Date(sub.realUsageTime) : null;
     const usageDay = usageDate ? usageDate.getDate() : -1;
 
     const segments: GroupBuySegment[] = [];
     let currentSegStart = -1;
     let isCurrentSegConsumed = false;
 
     // Collect raw segment data first (without rounding info)
     interface RawSeg { left: number; width: number; isConsumed: boolean; }
     const rawSegs: RawSeg[] = [];
 
     // Step 1: Divide into raw segments based on validity and consumption
     for (let d = range.start; d <= range.end; d++) {
        const date = new Date(this.currentYear, this.currentMonth, d);
        const dayOfWeek = date.getDay();
        const isValidDay = validDays.length === 0 || validDays.includes(dayOfWeek);
        const isDayConsumed = usageDay !== -1 && d > usageDay;
 
        if (isValidDay) {
           if (currentSegStart === -1 || isCurrentSegConsumed !== isDayConsumed) {
              if (currentSegStart !== -1) {
                 rawSegs.push({
                    left: (currentSegStart - 1) * 48,
                    width: (d - currentSegStart) * 48,
                    isConsumed: isCurrentSegConsumed
                 });
              }
              currentSegStart = d;
              isCurrentSegConsumed = isDayConsumed;
           }
        } else {
           if (currentSegStart !== -1) {
              rawSegs.push({
                 left: (currentSegStart - 1) * 48,
                 width: (d - currentSegStart) * 48,
                 isConsumed: isCurrentSegConsumed
              });
              currentSegStart = -1;
           }
        }
     }
     
     if (currentSegStart !== -1) {
        rawSegs.push({
           left: (currentSegStart - 1) * 48,
           width: (range.end - currentSegStart + 1) * 48,
           isConsumed: isCurrentSegConsumed
        });
     }
 
     // Step 2: Create final segments with correct rounding flags
     // Logic: ALL segments are rounded capsules. No more straight edges.
     rawSegs.forEach((raw, index) => {
        // Simplify: Always round both ends.
        const isAtStart = true;
        const isAtEnd = true;
        segments.push(new GroupBuySegment(raw.left, raw.width, raw.isConsumed, isAtStart, isAtEnd));
     });
 
     this.groupBuySegmentsCache.set(cacheKey, segments);
     return segments;
  }
}
