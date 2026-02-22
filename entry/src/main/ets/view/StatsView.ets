import { SubscriptionModel } from '../model/SubscriptionModel';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { DateUtil } from '../utils/DateUtil';
import { promptAction, curves, LengthMetrics } from '@kit.ArkUI';
import { commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
import { GlobalBus, EVENT_SYNC_COMPLETED, EVENT_DATA_CHANGED } from '../utils/GlobalBus';

import { ExpenseChart } from './ExpenseChart';
import { resolveIcon } from '../utils/MemberServiceConfig';
import { LoginSheet } from './LoginSheet';
import { MonthlyReportSheet } from './MonthlyReportSheet';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hdsEffect,   HdsNavDestination, ScrollEffectType, HdsNavigationTitleBarOptions, HdsNavigationTitleBarStyle } from '@kit.UIDesignKit';

interface RankingItem {
  sub: SubscriptionModel;
  displayPrice: number;
}

class MonthLabel {
  text: string;
  offset: number;

  constructor(text: string, offset: number) {
    this.text = text;
    this.offset = offset;
  }
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

interface GeneratedObjectLiteralInterface_2 {
  enableScrollEffect: boolean;
  scrollEffectType: ScrollEffectType;
  blurEffectiveStartOffset: LengthMetrics;
  blurEffectiveEndOffset: LengthMetrics;
}

@Component
export struct StatsView {
  @Consume('pageStack') pageStack: NavPathStack;
  private syncSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @State subscriptions: SubscriptionModel[] = [];
  @StorageProp('isInitialSyncDone') isInitialSyncDone: boolean = false;
  @StorageProp('isWide') isWide: boolean = false;
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('isSplitViewEnabled') isSplitViewEnabled: boolean = true;

  @State isLoading: boolean = false;
  @State showReport: boolean = false;
  @State showLoginSheet: boolean = false;
  @State rotateAngle: number = 0;
  @State isRotating: boolean = false;
  
  // 图表数据
  @State chartData: number[] = [];
  @State chartLabels: string[] = [];
  @State quarterlyChartData: number[] = [];
  @State quarterlyChartLabels: string[] = [];
  @State chartViewMode: number = 0; // 0: 月度, 1: 季度

  // Unified Animation System
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  // @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @Prop @Watch('onVisibleChange') isVisible: boolean = false;

  // Interaction States
  @State isReportPressed: boolean = false;
  @State reportLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isSummaryPressed: boolean = false;
  @State summaryLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isTrendPressed: boolean = false;
  @State trendLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isRankingCardPressed: boolean = false;
  @State rankingCardLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isHeatmapPressed: boolean = false;
  @State heatmapLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isLoginPressed: boolean = false;
  @State loginLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State pressedFilterIndex: number = -1;
  @State pressedChartFilterIndex: number = -1;
  @State isRefreshPressed: boolean = false;
  @State refreshLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Heatmap Data
  @State heatmapData: number[] = new Array(366).fill(0);
  @State maxDailyCost: number = 1; 
  @State monthLabels: MonthLabel[] = [];

  // Animation Sequence States
  @State animStep1: boolean = false; // Summary Card
  @State animStep2: boolean = false; // Chart Card
  @State animStepHeatmap: boolean = false; // Heatmap Card
  @State animStep3: boolean = false; // Report Card
  @State animStep4: boolean = false; // Ranking Card
  @State animHeader: boolean = false; // Title Header

  aboutToAppear() {
     this.loadData();
     // Subscribe to data changes
     GlobalBus.subscribe(EVENT_DATA_CHANGED, () => {
        this.loadData();
     });
     GlobalBus.subscribe(EVENT_SYNC_COMPLETED, () => {
        this.loadData();
        this.rotateAngle = 0;
     }).then(s => this.syncSubscriber = s);
     
     this.onVisibleChange();
    
     if (!this.isInitialSyncDone) {
       this.rotateAngle = -720; 
     }
  }

  onVisibleChange() {
    if (this.isVisible) {
      const interval = this.animationDuration * 0.15; // 缩减步进间距为 15%
      const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);
      
      if (this.isAnimationEnabled) {
        // 第一梯队: 头部 + 概览
        setTimeout(() => {
          if (!this.isVisible) return;
          animateTo({ curve: springCurve }, () => {
            this.animHeader = true;
            this.animStep1 = true;
          });
        }, 50);
        
        // 第二梯队: 趋势图 + 热力图
        setTimeout(() => {
          if (!this.isVisible) return;
          animateTo({ curve: springCurve }, () => {
            this.animStep2 = true;
            this.animStepHeatmap = true;
          })
        }, 50 + interval);
        
        // 第三梯队: 报告 + 排行
        setTimeout(() => {
          if (!this.isVisible) return;
          animateTo({ curve: springCurve }, () => {
            this.animStep3 = true;
            this.animStep4 = true;
          })
        }, 50 + interval * 2);
      } else {
        this.animHeader = true;
        this.animStep1 = true;
        this.animStep2 = true;
        this.animStepHeatmap = true;
        this.animStep3 = true;
        this.animStep4 = true;
      }
    } else {
      // 离开时重置状态，确保下次进入时是从初始态（不可见）平滑过渡
      this.animHeader = false;
      this.animStep1 = false;
      this.animStep2 = false;
      this.animStepHeatmap = false;
      this.animStep3 = false;
      this.animStep4 = false;
    }
  }
  
  // 排行筛选 (0:当月支出, 1:未来一年, 2:平均月支)
  @State rankingFilter: number = 0;
  
  // 报告弹窗
  // @State showLoginSheet: boolean = false; // This line was removed as it's now declared above

  async loadData() {
    // 强制登录才能查看数据
    if (!this.isLoggedIn) {
      this.subscriptions = [];
      this.calculateChartData();
      return;
    }
    // 即使初始同步未完成，也尝试加载本地已有数据，以实现“秒开”体验
    const data = await SubscriptionRepository.getInstance().queryAll();
    // 创建新数组引用
    this.subscriptions = [...data];
    this.calculateChartData();
    this.calculateQuarterlyChartData();
    this.calculateHeatmapData();
  }

  calculateHeatmapData() {
    // Reset data
    let maxCost = 0;
    const now = new Date();
    const currentYear = now.getFullYear();
    const startOfYear = new Date(currentYear, 0, 1);
    
    // Calculate padding for the first week (Align with Sunday start)
    // 0 = Sunday, 1 = Monday...
    const startDayOfWeek = startOfYear.getDay(); 
    const paddingCount = startDayOfWeek;
    
    // Calculate Month Labels
    const labels: MonthLabel[] = [];
    let currentMonth = -1;
    // Iterate through weeks (approx 53)
    // Each column is 1 week. We check the month of the first day of that week (or majority)
    // Actually, simpler strategy: iterate through days, find the index where month changes.
    // The grid is column-based, 7 rows. Index / 7 = column index.
    
    // Total cells = 366 + padding
    for (let i = 0; i < 366 + paddingCount; i+=7) {
        // Checking the date at the start of this column (Sunday of that week)
        // i corresponds to the index in heatmapData
        // real day index = i - paddingCount
        
        // We want to label the month approx where it starts.
        // Let's check the date of the first cell in this column
        const dayOfYearIndex = i - paddingCount;
        let dateOfColumnStart: Date;
        
        if (dayOfYearIndex < 0) {
            // This column contains some padding from prev year, and some from Jan
            dateOfColumnStart = new Date(currentYear, 0, 1); // Approximation
        } else {
             dateOfColumnStart = new Date(currentYear, 0, dayOfYearIndex + 1);
        }
        
        if (dateOfColumnStart.getMonth() !== currentMonth) {
            currentMonth = dateOfColumnStart.getMonth();
            // grid column width = 10 + gap 4 = 14
            // offset by column index
            labels.push(new MonthLabel(
                (currentMonth + 1) + '月', 
                (i / 7) * 14
            ));
        }
    }
    this.monthLabels = labels;
    
    // Initialize array with padding (-1 indicates empty/padding)
    // Size = 366 + padding
    // Initialize array with padding (-1 indicates empty/padding)
    // Size = 366 + padding
    const data: number[] = new Array(366 + paddingCount).fill(0);
    // Fill padding with -1
    for (let i = 0; i < paddingCount; i++) {
        data[i] = -1;
    }

    this.subscriptions.forEach(sub => {
       const price = Number(sub.price);
       if (isNaN(price) || price <= 0) return;
       
       let billingDate = new Date(sub.nextBillingDate);
       if (isNaN(billingDate.getTime())) return;

       // 1. 回溯到今年年初之前，确保捕获今年所有的扣款点
       while (billingDate.getFullYear() > currentYear || (billingDate.getFullYear() === currentYear && billingDate >= startOfYear)) {
           let prevDate = new Date(billingDate);
           if (sub.billingCycle === 'Monthly') prevDate.setMonth(prevDate.getMonth() - 1);
           else if (sub.billingCycle === 'Quarterly') prevDate.setMonth(prevDate.getMonth() - 3);
           else if (sub.billingCycle === 'Yearly') prevDate.setFullYear(prevDate.getFullYear() - 1);
           else break; // Lifetime and Indefinite only has one specific date
           
           if (prevDate.getTime() < startOfYear.getTime()) {
               break; 
           }
           billingDate = prevDate;
       }
       
          // Lifetime & Indefinite & GroupBuy 特殊处理：锚定特定日期计入
          // GroupBuy: Use realUsageTime or nextBillingDate (Expiration)
          // Lifetime/Indefinite: Use startDate (Purchase) or nextBillingDate as fallback
          if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
               // 处理团购退款逻辑
               if (sub.recordType === 'groupBuy') {
                  const days = DateUtil.getDaysUntil(sub.nextBillingDate);
                  if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
                      return;
                  }
               }
              
              let targetDate: Date;
              if (sub.recordType === 'groupBuy') {
                 targetDate = sub.realUsageTime ? new Date(sub.realUsageTime) : new Date(sub.nextBillingDate);
              } else {
                 targetDate = new Date(sub.startDate || sub.nextBillingDate);
              }

              if (targetDate.getFullYear() === currentYear) {
                  const dayOfYear = DateUtil.getDayOfYear(targetDate);
                  if (dayOfYear >= 0 && dayOfYear < 366) {
                      const index = dayOfYear + paddingCount;
                      data[index] += price;
                      if (data[index] > maxCost) maxCost = data[index];
                  }
              }
              return;
          }

       // 2. 向前推演今年内的所有扣款
       while (billingDate < startOfYear) {
           if (sub.billingCycle === 'Monthly') billingDate.setMonth(billingDate.getMonth() + 1);
           else if (sub.billingCycle === 'Quarterly') billingDate.setMonth(billingDate.getMonth() + 3);
           else if (sub.billingCycle === 'Yearly') billingDate.setFullYear(billingDate.getFullYear() + 1);
       }

       // 现在 billingDate >= startOfYear。开始遍历今年
       while (billingDate.getFullYear() === currentYear) {
           const dayOfYear = DateUtil.getDayOfYear(billingDate);
           if (dayOfYear >= 0 && dayOfYear < 366) {
               const index = dayOfYear + paddingCount;
               data[index] += price;
               if (data[index] > maxCost) maxCost = data[index];
           }
           
           // Next cycle
           if (sub.billingCycle === 'Monthly') billingDate.setMonth(billingDate.getMonth() + 1);
           else if (sub.billingCycle === 'Quarterly') billingDate.setMonth(billingDate.getMonth() + 3);
           else if (sub.billingCycle === 'Yearly') billingDate.setFullYear(billingDate.getFullYear() + 1);
           else break;
       }
    });

    this.heatmapData = data;
    this.maxDailyCost = maxCost > 0 ? maxCost : 1;
  }
  
  // 计算未来12个月的支出
  calculateChartData() {
    const labels: string[] = [];
    const data: number[] = [];
    const now = new Date();
    // 归一化到当前月的第一天 00:00:00
    const startOfCurrentMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    // 预测结束时间：12个月后的第一天
    const endOfProjection = new Date(now.getFullYear(), now.getMonth() + 12, 1);
    
    // 初始化12个月的空数据
    for (let i = 0; i < 12; i++) {
        const d = new Date(startOfCurrentMonth.getFullYear(), startOfCurrentMonth.getMonth() + i, 1);
        labels.push(`${d.getMonth() + 1}月`);
        data.push(0);
    }
    
    // 计算每个订阅在未来12个月的支出
    this.subscriptions.forEach(sub => {
        const price = Number(sub.price);
        if (isNaN(price) || price <= 0) return;
        
        // 从下个账单日开始推算
        let billingDate = new Date(sub.nextBillingDate);
        
        // 防止死循环：如果日期无效，跳过
        if (isNaN(billingDate.getTime())) return;

        // [Fix] 回溯逻辑：如果 nextBillingDate 已经在未来（例如下个月），但实际上是本月刚过期的（本月已付），
        // 或者是年付刚过期的，我们需要把它拉回本月来统计，确保"当前月"的数据不为0。
        while (true) {
             let prevDate = new Date(billingDate);
             if (sub.billingCycle === 'Monthly') {
                 prevDate.setMonth(prevDate.getMonth() - 1);
             } else if (sub.billingCycle === 'Quarterly') {
                 prevDate.setMonth(prevDate.getMonth() - 3);
             } else if (sub.billingCycle === 'Yearly') {
                 prevDate.setFullYear(prevDate.getFullYear() - 1);
             } else {
                 break;
             }
             
             // 只要回退后依然落在统计窗口内（>= 本月1号），就采纳回退后的日期
             if (prevDate >= startOfCurrentMonth) {
                 billingDate = prevDate;
             } else {
                 break; // 再退就出去了，停止
             }
        }

        if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
            // 处理团购退款逻辑
            if (sub.recordType === 'groupBuy') {
                const days = DateUtil.getDaysUntil(sub.nextBillingDate);
                if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
                    return;
                }
            }
            
            let targetDate: Date;
            if (sub.recordType === 'groupBuy') {
                 targetDate = sub.realUsageTime ? new Date(sub.realUsageTime) : new Date(sub.nextBillingDate);
            } else {
                 targetDate = new Date(sub.startDate || sub.nextBillingDate);
            }

            const diffMonths = (targetDate.getFullYear() - startOfCurrentMonth.getFullYear()) * 12 + 
                               (targetDate.getMonth() - startOfCurrentMonth.getMonth());
            if (diffMonths >= 0 && diffMonths < 12) {
                data[diffMonths] += price;
            }
            return;
        }

        // 如果下个账单日已经是过去的时间（数据异常），这里不做回溯，只计算未来
        while (billingDate < startOfCurrentMonth) {
             if (sub.billingCycle === 'Monthly') {
                billingDate.setMonth(billingDate.getMonth() + 1);
            } else if (sub.billingCycle === 'Quarterly') {
                billingDate.setMonth(billingDate.getMonth() + 3);
            } else if (sub.billingCycle === 'Yearly') {
                billingDate.setFullYear(billingDate.getFullYear() + 1);
            } else {
                return; // 不支持的周期
            }
        }

        // 模拟未来的扣费时间点
        let safetyCount = 0;
        while (billingDate < endOfProjection && safetyCount < 20) {
            safetyCount++;
            
            const diffMonths = (billingDate.getFullYear() - startOfCurrentMonth.getFullYear()) * 12 + 
                               (billingDate.getMonth() - startOfCurrentMonth.getMonth());
            
            if (diffMonths >= 0 && diffMonths < 12) {
                data[diffMonths] += price;
            }

            // 步进到下一个账单日
            if (sub.billingCycle === 'Monthly') {
                const currentMonth = billingDate.getMonth();
                billingDate.setMonth(currentMonth + 1);
            } else if (sub.billingCycle === 'Quarterly') {
                const currentMonth = billingDate.getMonth();
                billingDate.setMonth(currentMonth + 3);
            } else if (sub.billingCycle === 'Yearly') {
                billingDate.setFullYear(billingDate.getFullYear() + 1);
            } else {
                break;
            }
        }
    });
    
    this.chartLabels = labels;
    this.chartData = data;
  }

  // 计算未来4个季度的支出（基于月度数据汇总）
  calculateQuarterlyChartData() {
    // 确保月度数据已计算
    if (this.chartData.length === 0) {
      this.calculateChartData();
    }

    const labels: string[] = [];
    const data: number[] = [];
    const now = new Date();
    const currentQuarter = Math.floor(now.getMonth() / 3);

    // 初始化4个季度
    for (let i = 0; i < 4; i++) {
      const q = (currentQuarter + i) % 4;
      labels.push(`Q${q + 1}`);
      data.push(0);
    }

    // 将月度数据汇总到季度
    // chartData 是从当前月开始的12个月数据
    const currentMonth = now.getMonth();
    
    for (let monthIndex = 0; monthIndex < 12 && monthIndex < this.chartData.length; monthIndex++) {
      // 计算这个月属于哪个季度（相对于当前季度的偏移）
      const absoluteMonth = currentMonth + monthIndex;
      const absoluteQuarter = Math.floor(absoluteMonth / 3);
      const quarterOffset = absoluteQuarter - currentQuarter;
      
      if (quarterOffset >= 0 && quarterOffset < 4) {
        data[quarterOffset] += this.chartData[monthIndex];
      }
    }

    this.quarterlyChartLabels = labels;
    this.quarterlyChartData = data;
  }
  


  // ========== 统计计算方法 ==========
  
  getSubscriptionCount(): number {
    return this.subscriptions.length;
  }

  getMonthlyCount(): number {
    return this.subscriptions.filter(s => s.billingCycle === 'Monthly').length;
  }

  getYearlyCount(): number {
    return this.subscriptions.filter(s => s.billingCycle === 'Yearly').length;
  }

  getQuarterlyCount(): number {
    return this.subscriptions.filter(s => s.billingCycle === 'Quarterly').length;
  }

  getLifetimeCount(): number {
    return this.subscriptions.filter(s => s.billingCycle === 'Lifetime' || s.billingCycle === 'Indefinite').length;
  }

  getTotalMonthly(): number {
    let total = 0;
    const now = new Date();
    this.subscriptions.forEach(sub => {
      // 永久/不定/团购 项目仅在购买当月计入支出（全额）
      if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
         // 处理团购退款逻辑
         if (sub.recordType === 'groupBuy') {
            const days = DateUtil.getDaysUntil(sub.nextBillingDate);
            if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
                return;
            }
         }

         let targetDate: Date;
         if (sub.recordType === 'groupBuy') {
             targetDate = sub.realUsageTime ? new Date(sub.realUsageTime) : new Date(sub.nextBillingDate);
         } else {
             targetDate = new Date(sub.nextBillingDate); 
         }

         if (DateUtil.isSameMonth(targetDate, now)) {
            total += sub.price;
         }
         return;
      }
      let price = sub.price;
      if (sub.billingCycle === 'Yearly') {
        price = price / 12;
      } else if (sub.billingCycle === 'Quarterly') {
        price = price / 3;
      }
      total += price;
    });
    return total;
  }

  getAnnualProjection(): number {
    let total = 0;
    const now = new Date();
    this.subscriptions.forEach(sub => {
      // 永久/不定/团购：只有今年发生的才计入，且只算一次
      if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
         // GroupBuy: Use realUsageTime or nextBillingDate (Expiration)
         if (sub.recordType === 'groupBuy') {
             const days = DateUtil.getDaysUntil(sub.nextBillingDate);
             if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
                 return;
             }
         }
         
         const targetDate = sub.recordType === 'groupBuy' ? 
            (sub.realUsageTime ? new Date(sub.realUsageTime) : new Date(sub.nextBillingDate)) : 
            new Date(sub.nextBillingDate);
         
         if (targetDate.getFullYear() === now.getFullYear()) {
            total += sub.price;
         }
         return;
      }
      // 月付 × 12, 季付 × 4, 年付 × 1
      if (sub.billingCycle === 'Monthly') {
        total += sub.price * 12;
      } else if (sub.billingCycle === 'Quarterly') {
        total += sub.price * 4;
      } else if (sub.billingCycle === 'Yearly') {
        total += sub.price;
      }
    });
    return total;
  }

  getAverageMonthly(): number {
    if (this.subscriptions.length === 0) return 0;
    return this.getTotalMonthly() / this.subscriptions.length;
  }

  getGroupBuyIcon(sub: SubscriptionModel): string {
    if (sub.platform === 'meituan') return 'resource:meituan_logo';
    if (sub.platform === 'douyin') return 'resource:douyin_logo';
    if (sub.platform === 'dianping') return 'resource:dianping_logo';
    return sub.icon ?? '';
  }

  @Builder
  ReportSheetBuilder() {
    MonthlyReportSheet({
      subscriptions: this.subscriptions,
      showCloseButton: false, // Sheet mode doesn't need its own close button if bindSheet.showClose is true
      onClose: () => { this.showReport = false }
    })
  }

  @Builder
  LoginSheetBuilder() {
    LoginSheet({ 
      isShow: this.showLoginSheet, 
      onSuccess: () => { this.showLoginSheet = false },
      onClose: () => { this.showLoginSheet = false }
    })
  }

  async refreshData() {
    if (this.isRotating) return;
    this.isRotating = true;
    
    const duration = this.animationDuration;
    const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);
    
    if (this.isAnimationEnabled) {
      animateTo({ duration: duration, curve: springCurve }, () => {
        this.rotateAngle += 360;
      });
    } else {
      this.rotateAngle += 360;
    }
    
    await this.loadData();
    
    setTimeout(() => {
      this.isRotating = false;
    }, duration);
  }

  getRankingList(): RankingItem[] {
    let result: RankingItem[] = [];

    this.subscriptions.forEach(sub => {
      let calcPrice = 0;
      const price = Number(sub.price);

      if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
        // 处理团购退款逻辑
        if (sub.recordType === 'groupBuy') {
            const days = DateUtil.getDaysUntil(sub.nextBillingDate);
            if (sub.usageStatus === 'expired' || (sub.usageStatus !== 'used' && days < 0)) {
                return; // 类似 continue，在 forEach 中直接跳过 return
            }
        }
        
        let billingDate: Date;
        if (sub.recordType === 'groupBuy') {
            billingDate = sub.realUsageTime ? new Date(sub.realUsageTime) : new Date(sub.nextBillingDate);
        } else {
            billingDate = new Date(sub.startDate || sub.nextBillingDate);
        }
        
        const now = new Date();
        
        if (this.rankingFilter === 0) {
           // 月度: 如果是本月过期/购买，计入全额
           if (billingDate.getFullYear() === now.getFullYear() && billingDate.getMonth() === now.getMonth()) {
               calcPrice = price;
           }
        } else if (this.rankingFilter === 1) {
           // 季度: 如果是本季度过期/购买，计入全额
           const currentQuarter = Math.floor(now.getMonth() / 3);
           const billingQuarter = Math.floor(billingDate.getMonth() / 3);
           if (billingDate.getFullYear() === now.getFullYear() && currentQuarter === billingQuarter) {
               calcPrice = price;
           }
        } else {
           // 年度: 如果是今年过期/购买，计入全额
           if (billingDate.getFullYear() === now.getFullYear()) {
               calcPrice = price;
           }
        }
      } else {
          if (this.rankingFilter === 0) {
            // 月度预估：换算成月均
            if (sub.billingCycle === 'Yearly') {
              calcPrice = price / 12;
            } else if (sub.billingCycle === 'Quarterly') {
              calcPrice = price / 3;
            } else {
              calcPrice = price; // Monthly
            }
          } else if (this.rankingFilter === 1) {
            // 季度预估：换算成季度总支出
            if (sub.billingCycle === 'Yearly') {
              calcPrice = price / 4;
            } else if (sub.billingCycle === 'Quarterly') {
              calcPrice = price;
            } else {
              calcPrice = price * 3; // Monthly
            }
          } else {
            // 年度预估：换算成年度总支出
            if (sub.billingCycle === 'Yearly') {
              calcPrice = price;
            } else if (sub.billingCycle === 'Quarterly') {
              calcPrice = price * 4;
            } else {
              calcPrice = price * 12; // Monthly
            }
          }
      }

      if (calcPrice > 0) {
        result.push({ sub: sub, displayPrice: calcPrice } as RankingItem);
      }
    });

    return result.sort((a, b) => b.displayPrice - a.displayPrice);
  }

  getUpcomingSoon(): SubscriptionModel[] {
    return this.subscriptions.filter(sub => {
      // warranty 类型虽然 billingCycle 为 Lifetime，但也需要显示即将到期
      if (sub.billingCycle === 'Lifetime' && sub.recordType !== 'warranty') return false;
      const days = DateUtil.getDaysUntil(sub.nextBillingDate);
      return days >= 0 && days <= 7;
    }).sort((a, b) => a.nextBillingDate - b.nextBillingDate);
  }

  getExpiringThisMonth(): SubscriptionModel[] {
    return this.subscriptions.filter(sub => {
      // warranty 类型虽然 billingCycle 为 Lifetime，但也需要显示即将到期
      if (sub.billingCycle === 'Lifetime' && sub.recordType !== 'warranty') return false;
      const days = DateUtil.getDaysUntil(sub.nextBillingDate);
      return days >= 0 && days <= 30;
    });
  }

  getRankingItemInfo(sub: SubscriptionModel): string {
    let cycleText = '';
    if (sub.recordType === 'groupBuy') {
      cycleText = '团购';
    } else if (sub.recordType === 'warranty') {
      cycleText = '保修';
    } else {
      switch (sub.billingCycle) {
      case 'Monthly':
        cycleText = '月付';
        break;
      case 'Quarterly':
        cycleText = '季付';
        break;
      case 'Yearly':
        cycleText = '年付';
        break;
      case 'Lifetime':
        cycleText = '永久';
        break;
      case 'Indefinite':
        cycleText = '不定';
        break;
      }
    }
    
    if (sub.recordType === 'warranty' && sub.brand) {
      return `${cycleText} · ${sub.brand}`;
    }
    if (sub.subCategory) {
      return `${cycleText} · ${sub.subCategory}`;
    }
    return cycleText;
  }

  getRankingSubtitle(sub: SubscriptionModel): string {
    if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy' || sub.recordType === 'warranty') {
        if (this.rankingFilter === 0) return '本月支出';
        if (this.rankingFilter === 1) return '本季支出';
        return '年度支出';
    }
    if (this.rankingFilter === 0) return '平均月支';
    if (this.rankingFilter === 1) return '季度累计';
    return '年度累计';
  }




  @Builder
  SummaryCardBuilder() {
    Column() {
      Row() {
        Column() {
          Text("¥" + this.getTotalMonthly().toFixed(2))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text("月度平均支出 (均摊)")
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider()
          .vertical(true)
          .height(40)
          .color($r('app.color.divider_color'))
          .margin({ left: 12, right: 12 })

        Column() {
          Text("¥" + this.getAnnualProjection().toFixed(2))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text("年度总支出预估")
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')

      Divider()
        .color($r('app.color.divider_color'))
        .margin({ top: 16, bottom: 16 })

      Row() {
        Column() {
          Text(this.getSubscriptionCount().toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text("订阅总数")
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)

        Column() {
          Text("¥" + this.getAverageMonthly().toFixed(2))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text("月均单项")
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        this.CycleBadgeBuilder('#5B8FF9', `月付 ${this.getMonthlyCount()}`)
        this.CycleBadgeBuilder('#5AD8A6', `季付 ${this.getQuarterlyCount()}`)
        this.CycleBadgeBuilder('#F6BD16', `年付 ${this.getYearlyCount()}`)
        this.CycleBadgeBuilder('#E8684A', `永久 ${this.getLifetimeCount()}`)
      }
      .width('100%')
      .margin({ top: 16 })
      .justifyContent(FlexAlign.Center)
    }
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.summaryLightSource,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.isSummaryPressed ? 0.98 : 1, y: this.isSummaryPressed ? 0.98 : 1 })
    .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isSummaryPressed = true;
          this.summaryLightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isSummaryPressed = false;
        this.summaryLightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
  }

  @Builder
  CycleBadgeBuilder(color: string | Color, text: string) {
    Row({ space: 4 }) {
      Circle().width(8).height(8).fill(color)
      Text(text).fontSize(12).fontColor($r('app.color.text_secondary'))
    }
    .padding({ left: 8, right: 10, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(12)
  }

  @Builder
  TrendChartBuilder() {
    Column() {
      Row() {
        Text("未来扣费趋势").fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Row() {
          ForEach(["月度", "季度"], (label: string, index: number) => {
            Button() {
              Text(label)
                .fontSize(12)
                .fontWeight(this.chartViewMode === index ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.chartViewMode === index ?
                  (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                  $r('app.color.text_secondary'))
            }
            .type(ButtonType.Normal).layoutWeight(1).height('100%')
            .linearGradient(this.chartViewMode === index ?
              (this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
              (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } : undefined)) : undefined)
            .backgroundColor(this.chartViewMode === index ?
              (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
              Color.Transparent)
            .borderRadius(12)
            .scale({ x: this.pressedChartFilterIndex === index ? 0.95 : 1, y: this.pressedChartFilterIndex === index ? 0.95 : 1 })
            .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressedChartFilterIndex = index;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedChartFilterIndex = -1;
              }
            })
            .onClick(() => {
              if (this.isAnimationEnabled) {
                animateTo({ curve: curves.springMotion(this.animationResponse, this.animationDamping) }, () => { this.chartViewMode = index; })
              } else {
                this.chartViewMode = index;
              }
            })
          })
        }
        .backgroundColor($r('app.color.page_background')).borderRadius(14).width(132).height(32).padding(2)
      }
      .width('100%').margin({ bottom: 12 })

      Stack() {
        if (this.chartViewMode === 0) {
          ExpenseChart({
            monthlyData: this.chartData,
            labels: this.chartLabels,
            isVip: this.isVip,
            showVipTheme: this.showVipTheme,
            isNewYearTheme: this.isNewYearTheme
          })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 20 })),
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -20 }))
          ))
        } else {
          ExpenseChart({
            monthlyData: this.quarterlyChartData,
            labels: this.quarterlyChartLabels,
            isVip: this.isVip,
            showVipTheme: this.showVipTheme,
            isNewYearTheme: this.isNewYearTheme
          })
          .transition(TransitionEffect.asymmetric(
             TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 20 })),
             TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -20 }))
          ))
        }
      }
      .width('100%')
    }
    .padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({ sourceType: this.trendLightSource, illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER }).buildEffect())
    .scale({ x: this.isTrendPressed ? 0.98 : 1, y: this.isTrendPressed ? 0.98 : 1 })
    .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isTrendPressed = true;
          this.trendLightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isTrendPressed = false;
        this.trendLightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
  }

  @Builder
  HeatmapBuilder() {
    Column() {
      Row() {
        Column() {
          Text(`订阅热力图 (${new Date().getFullYear()})`).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text("横轴:周  纵轴:星期").fontSize(10).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
        }
        Blank()
        Row({ space: 4 }) {
          Text("少").fontSize(10).fontColor($r('app.color.text_secondary'))
          Rect().width(8).height(8).radius(2).fill(this.isNewYearTheme ? '#FFEBEE' : (this.showVipTheme ? '#FDF1D0' : '#85a5ff'))
          Rect().width(8).height(8).radius(2).fill(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : '#2f54eb'))
          Rect().width(8).height(8).radius(2).fill(this.isNewYearTheme ? $r('app.color.new_year_red_end') : (this.showVipTheme ? '#DFAA18' : '#1d39c4'))
          Text("多").fontSize(10).fontColor($r('app.color.text_secondary'))
        }
      }.width('100%').margin({ bottom: 12 })

      Row() {
        Column({ space: 4 }) {
          Text("").height(12).margin({ bottom: 4 })
          ForEach(['日', '一', '二', '三', '四', '五', '六'], (day: string) => {
            Text(day).fontSize(9).fontColor($r('app.color.text_secondary')).height(10).width(12).textAlign(TextAlign.Center)
          })
        }.padding({ top: 2, right: 4 })

        Scroll() {
          Column() {
            Row() {
              ForEach(this.monthLabels, (label: MonthLabel) => {
                Text(label.text).fontSize(9).fontColor($r('app.color.text_secondary')).position({ x: label.offset, y: 0 })
              })
            }.height(12).width('100%').margin({ bottom: 4 })
            Grid() {
              ForEach(this.heatmapData, (cost: number) => {
                GridItem() {
                  Rect().width(10).height(10).radius(2)
                    .fill(cost === -1 ? Color.Transparent : cost === 0 ? $r('app.color.page_background') :
                      cost / this.maxDailyCost < 0.3 ? (this.isNewYearTheme ? '#FFEBEE' : (this.showVipTheme ? '#FDF1D0' : '#85a5ff')) :
                      cost / this.maxDailyCost < 0.7 ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : '#2f54eb')) :
                        (this.isNewYearTheme ? $r('app.color.new_year_red_end') : (this.showVipTheme ? '#DFAA18' : '#1d39c4')))
                }
              })
            }.rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').columnsGap(4).rowsGap(4).height(10 * 7 + 4 * 6)
          }.alignItems(HorizontalAlign.Start)
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      }.width('100%')
    }
    .padding(16).backgroundColor($r('app.color.card_background')).borderRadius(16)
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({ sourceType: this.heatmapLight, illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER }).buildEffect())
    .scale({ x: this.isHeatmapPressed ? 0.98 : 1, y: this.isHeatmapPressed ? 0.98 : 1 })
    .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isHeatmapPressed = true;
          this.heatmapLight = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isHeatmapPressed = false;
        this.heatmapLight = hdsEffect.PointLightSourceType.NONE;
      }
    })
  }

  @Builder
  MonthlyReportCardBuilder() {
    Row() {
      Column() {
        Text("月度预估报告").fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
        Text("查看详细的订阅支出分析与建议").fontSize(12).fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)).margin({ top: 4 })
      }.alignItems(HorizontalAlign.Start)
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(20).fontColor([this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
    }
    .width('100%').padding(16).borderRadius(16)
    .linearGradient(this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
      (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } :
      { angle: 135, colors: [[$r('app.color.brand_gradient_start'), 0.0], [$r('app.color.brand_gradient_end'), 1.0]] }))
    .opacity(this.subscriptions.length > 0 ? 1.0 : 0.8)
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({ sourceType: this.reportLightSource, illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER }).buildEffect())
    .scale({ x: this.isReportPressed ? 0.98 : 1, y: this.isReportPressed ? 0.98 : 1 })
    .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isReportPressed = true;
          this.reportLightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isReportPressed = false;
        this.reportLightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
    .onClick(() => {
      if (this.subscriptions.length > 0) {
        if (this.isWide && this.isSplitViewEnabled) { this.pageStack.removeByName('MonthlyReport'); this.pageStack.pushPathByName('MonthlyReport', this.subscriptions); }
        else this.showReport = true;
      } else promptAction.showToast({ message: '请先添加订阅项目' });
    })
  }

  @Builder
  RankingCardBuilder() {
    Column() {
      Row() {
        Text("支出排行").fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Row() {
          ForEach(["月度预估", "季度预估", "年度预估"], (label: string, index: number) => {
            Button() {
              Text(label).fontSize(12).fontWeight(this.rankingFilter === index ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.rankingFilter === index ? (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) : $r('app.color.text_secondary'))
            }
            .type(ButtonType.Normal).layoutWeight(1).height('100%')
            .linearGradient(this.rankingFilter === index ?
              (this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
              (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } : undefined)) : undefined)
            .backgroundColor(this.rankingFilter === index ? (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) : Color.Transparent)
            .borderRadius(12).scale({ x: this.pressedFilterIndex === index ? 0.95 : 1, y: this.pressedFilterIndex === index ? 0.95 : 1 })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressedFilterIndex = index;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedFilterIndex = -1;
              }
            })
            .onClick(() => { 
                if (this.isAnimationEnabled) {
                  animateTo({ curve: curves.springMotion(this.animationResponse, this.animationDamping) }, () => { this.rankingFilter = index; }) 
                } else {
                  this.rankingFilter = index;
                }
            })
          })
        }.backgroundColor($r('app.color.page_background')).borderRadius(14).width(210).height(32).padding(2)
      }.width('100%').margin({ bottom: 16 })

      if (this.getRankingList().length === 0) Text("暂无数据").fontSize(14).fontColor($r('app.color.text_secondary')).margin({ top: 20, bottom: 20 })

      ForEach(this.getRankingList(), (item: RankingItem, index: number) => {
        this.RankingItemAnimated(item, index)
      }, (item: RankingItem) => `${item.sub.uuid}_${this.rankingFilter}_${item.sub.icon}`)
    }
    .padding(16).backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({ sourceType: this.rankingCardLight, illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER }).buildEffect())
    .scale({ x: this.isRankingCardPressed ? 0.98 : 1, y: this.isRankingCardPressed ? 0.98 : 1 })
    .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isRankingCardPressed = true;
          this.rankingCardLight = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isRankingCardPressed = false;
        this.rankingCardLight = hdsEffect.PointLightSourceType.NONE;
      }
    })
  }

  @Builder
  RankingItemAnimated(item: RankingItem, index: number) {
    Row() {
      Text((index + 1).toString()).fontSize(16).fontWeight(FontWeight.Bold).fontColor(index === 0 ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary')).width(24)
      SubscriptionIcon({
        icon: item.sub.recordType === 'groupBuy' ? this.getGroupBuyIcon(item.sub) : item.sub.icon,
        name: item.sub.recordType === 'groupBuy' ? (item.sub.merchantName || item.sub.name) : item.sub.name,
        iconSize: 48, iconRadius: 12, showGroupBadge: item.sub.recordType === 'groupBuy'
      }).margin({ left: 8 })
      Column() {
        Text(item.sub.name).fontSize(15).fontColor($r('app.color.text_primary'))
        Text(this.getRankingItemInfo(item.sub)).fontSize(12).fontColor($r('app.color.text_secondary')).margin({ top: 2 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 12 })
      Column() {
        Text(`¥${item.displayPrice.toFixed(2)}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).alignSelf(ItemAlign.End)
        Text(this.getRankingSubtitle(item.sub)).fontSize(10).fontColor($r('app.color.text_secondary')).margin({ top: 2 }).alignSelf(ItemAlign.End)
      }
    }
    .width('100%').padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: index < this.getRankingList().length - 1 ? 1 : 0 }, color: $r('app.color.divider_color') })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 30 })).combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
      .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0, delay: this.isAnimationEnabled ? index * 50 : 0 }))
  }
@Builder StatsBuilder(){
  Stack({ alignContent: Alignment.Top }) {
    if (!this.isLoggedIn) {
      this.LoginPlaceholderBuilder()
    } else {
      List() {
        ListItem() {
          Column().height(56 + this.getUIContext().px2vp(this.topRectHeight))
        }

        ListItem() {
          this.SummaryCardBuilder()
        }
        .padding({ left: 24, right: 24, bottom: 16 })
        .opacity(this.animStep1 ? 1 : 0)
        .translate({ y: this.animStep1 ? 0 : 50 })

        ListItem() {
          this.TrendChartBuilder()
        }
        .padding({ left: 24, right: 24, bottom: 16 })
        .opacity(this.animStep2 ? 1 : 0)
        .translate({ y: this.animStep2 ? 0 : 50 })

        ListItem() {
          this.HeatmapBuilder()
        }
        .padding({ left: 24, right: 24, bottom: 16 })
        .opacity(this.animStepHeatmap ? 1 : 0)
        .translate({ y: this.animStepHeatmap ? 0 : 50 })

        ListItem() {
          this.MonthlyReportCardBuilder()
        }
        .padding({ left: 24, right: 24, bottom: 16 })
        .opacity(this.animStep3 ? 1 : 0)
        .translate({ y: this.animStep3 ? 0 : 50 })

        ListItem() {
          this.RankingCardBuilder()
        }
        .padding({ left: 24, right: 24, bottom: 16 })
        .opacity(this.animStep4 ? 1 : 0)
        .translate({ y: this.animStep4 ? 0 : 50 })

        ListItem() {
          Row().height(120)
        }
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
  }
  .width('100%').height('100%').backgroundColor(Color.Transparent)
}
  build() {
    HdsNavDestination() {
      this.StatsBuilder()

      Column()
        .bindSheet($$this.showReport, this.ReportSheetBuilder(), {
          height: SheetSize.LARGE,
          backgroundColor: $r('app.color.page_background'),
          dragBar: true,
          showClose: true,
          onDisappear: () => {
            this.showReport = false
          },
          preferType: SheetType.BOTTOM
        })
      Column()
        .bindSheet($$this.showLoginSheet, this.LoginSheetBuilder(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          preferType: SheetType.BOTTOM,
          title: { title: '登录', subtitle: '使用华为账号登录' },
          onDisappear: () => {
            this.showLoginSheet = false
          }
        })
    }
    .hideBackButton(true).hideTitleBar(false).backgroundColor(Color.Transparent)
    .titleBar({
      avoidLayoutSafeArea: true,
      // style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
      //   systemMaterialEffect: {
      //     materialType: hdsMaterial.MaterialType.IMMERSIVE,
      //     materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      //   },
      //   scrollEffectOpts: {
      //     enableScrollEffect: true,
      //     scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      //     blurEffectiveStartOffset: LengthMetrics.vp(0),
      //     blurEffectiveEndOffset: LengthMetrics.vp(20)
      //   }
      // }: undefined,
      content: {
        title: { mainTitle: '统计分析' },
      }
    } as HdsNavigationTitleBarOptions)



  }

  @Builder
  LoginPlaceholderBuilder() {
    Column() {
      SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(60).fontColor([$r('app.color.text_secondary')]).margin({ bottom: 20 })
      Text("请先登录").fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).margin({ bottom: 8 })
      Text("登录后可查看详细统计分析").fontSize(14).fontColor($r('app.color.text_secondary')).margin({ bottom: 32 })
      Button("立即登录").fontSize(16).fontWeight(FontWeight.Bold)
        .fontColor(this.isNewYearTheme ? $r('app.color.new_year_text_on_red') : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
        .linearGradient(this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
          (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } :
          { angle: 0, colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]] }))
        .backgroundColor(Color.Transparent).width(200).height(48).borderRadius(24)
        .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({ sourceType: this.loginLightSource, illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER }).buildEffect())
        .scale({ x: this.isLoginPressed ? 0.95 : 1, y: this.isLoginPressed ? 0.95 : 1 })
        .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            if (this.isAnimationEnabled && this.isPointLightEnabled) {
              this.isLoginPressed = true;
              this.loginLightSource = hdsEffect.PointLightSourceType.BRIGHT;
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isLoginPressed = false;
            this.loginLightSource = hdsEffect.PointLightSourceType.NONE;
          }
        })
        .onClick(() => {
          if (this.isWide && this.isSplitViewEnabled) { this.pageStack.removeByName('Login'); this.pageStack.pushPathByName('Login', null); }
          else this.showLoginSheet = true;
        })
    }
    .onClick(() => { if (this.isWide && this.isSplitViewEnabled) { this.pageStack.removeByName('Login'); this.pageStack.pushPathByName('Login', null); } else this.showLoginSheet = true; })
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
