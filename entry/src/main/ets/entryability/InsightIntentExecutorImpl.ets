import { common, insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { LocalIconManager } from '../utils/LocalIconManager';
import { matchMemberService } from '../utils/MemberServiceConfig';
import { util } from '@kit.ArkTS';

const TAG = 'InsightIntentExecutorImpl';

interface AgentRecordItem {
  title: string;
  content: string;
  price: number;
}

class Constants {
  public static INTENT_ADD_RECORD = "AddRecord";
  public static INTENT_QUERY_RECORD = "QueryRecord";
  public static INTENT_GET_ALL_RECORDS = "GetAllRecords";
  public static INTENT_QUERY_SUBSCRIPTION = "QuerySubscription";
  public static INTENT_QUERY_VOUCHER = "QueryVoucher";
  public static INTENT_QUERY_WARRANTY = "QueryWarranty";
}

export default class InsightIntentExecutorImpl extends InsightIntentExecutor {

  /**
   * override 执行前台UIAbility意图
   *
   * @param name 意图名称
   * @param param 意图参数
   * @param pageLoader WindowStage实例
   * @returns 意图调用结果
   */
  async onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>, pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityForegroundMode [Cold/Warm Start] called: name=${name}`);

    // 1. 快速初始化基础配置
    try {
      const context = (this.context as Object) as common.UIAbilityContext;
      // 这里的初始化主要为了 AppStorage 能在页面加载前注入数据，但不能阻塞太久
      await PreferenceUtil.getInstance().loadPreference(context);
      await SubscriptionRepository.getInstance().init(context);
      // 补全图标库初始化，确保查询结果中的图标路径能正确生成
      await LocalIconManager.getInstance().init(context);
    } catch (e) {
      hilog.error(0x0001, TAG, `Quick Initialize failed during foreground execute: ${e}`);
    }

    // 2. 构造即时反馈文案 (针对所有查询意图统一引导)
    let fastResultText = "已找到记录，详情已呈现在屏幕上。";
    if (name === Constants.INTENT_QUERY_WARRANTY) {
      fastResultText = "正在为您查询保修详情，请看屏幕。";
    } else if (name === Constants.INTENT_QUERY_VOUCHER) {
      fastResultText = "正在为您查找相关的代金券，请看屏幕。";
    }

    // 3. 异步触发重度逻辑以更新 AppStorage (不等待，防止冷启动超时)
    if (name === Constants.INTENT_GET_ALL_RECORDS) {
      this.handleGetAllRecords();
    } else if (name === Constants.INTENT_QUERY_VOUCHER) {
      this.handleQueryVoucher(param);
    } else if (name === Constants.INTENT_QUERY_WARRANTY) {
      this.handleQueryWarranty(param);
    } else if (name === Constants.INTENT_QUERY_SUBSCRIPTION) {
      // 显式注入订阅过滤器，确保不混入代金券或保修记录
      param['recordTypeFilter'] = 'subscription';
      this.handleQueryRecord(param);
    } else {
      // 兜底逻辑：处理通用 QueryRecord 意图。
      // 若用户未明确指定过滤器，默认为 'subscription'，解决用户反馈的“查订阅却带出代金券”问题。
      if (!param['recordTypeFilter'] && !param['record_type_filter']) {
        param['recordTypeFilter'] = 'subscription';
      }
      this.handleQueryRecord(param);
    }

    // 4. 立即返回，满足小艺的 2s/冷启动 响应要求
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityForegroundMode returning fast response.`);
    return {
      code: 0,
      result: {
        'resultText': fastResultText,
        'result': 'success'
      }
    };
  }

  /**
   * override 执行后台UIAbility意图
   *
   * @param name 意图名称
   * @param param 意图参数
   * @returns 意图调用结果
   */
  async onExecuteInUIAbilityBackgroundMode(name: string, param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityBackgroundMode [AddRecord] called: name=${name}`);

    try {
      const context = (this.context as Object) as common.UIAbilityContext;
      await PreferenceUtil.getInstance().loadPreference(context);
      await SubscriptionRepository.getInstance().init(context);
      await LocalIconManager.getInstance().init(context);
    } catch (e) {
      hilog.error(0x0001, TAG, `Initialization failed: ${e}`);
    }

    switch (name) {
      case Constants.INTENT_ADD_RECORD:
        return this.handleAddRecord(param);
      default:
        hilog.warn(0xFEED, TAG, `Unknown background intent: ${name}`);
        return {
          code: -1,
          result: {
            message: 'Unknown background intent',
            resultText: '抱歉，暂时无法处理该后台请求。'
          }
        };
    }
  }

  private async handleGetAllRecords(): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[GetAllRecords] Executing full dump intent.`);
      const allSubs = await SubscriptionRepository.getInstance().queryAll();
      const activeSubs = allSubs.filter(s => !s.isDeleted);

      const totalCount = activeSubs.length;
      const recordsListText = activeSubs.slice(0, 5).map((s, index) =>
        `${index + 1}. ${s.name} - ${s.currency === 'USD' ? '$' : '¥'}${s.price}`
      ).join("; ");

      // 简化返回给 Agent 的文案，详情通过 UI 卡片展示
      const resultText = totalCount > 0 
        ? "查询成功，所有记录已在屏幕上为您列出。" 
        : "您目前没有任何订阅或消费记录。";

      const resultData: Record<string, Object> = {
        'resultText': resultText,
        'result': resultText,
        'answer': resultText,
        'text': resultText,
        'count': totalCount,
        'records': JSON.stringify(activeSubs) // Keep for UI or debug
      };

      hilog.info(0xFEED, TAG, `[RETURN] GetAllRecords Final Result: ${JSON.stringify(resultData)}`);

      // Push to UI via AppStorage
      AppStorage.setOrCreate('queryResultData', resultData);
      AppStorage.setOrCreate('isQueryResultsVisible', true);

      return {
        code: 0,
        result: resultData
      };
    } catch (e) {
      hilog.error(0x0001, TAG, `GetAllRecords failed: ${e}`);
      return {
        code: 0, // Still return 0 so user sees the error message in resultText instead of "Execution Failed"
        result: {
          'resultText': "查询全部数据时出错。",
          'errorMessage': `${e}`
        }
      };
    }
  }

  private async handleQueryVoucher(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    param['queryType'] = 'expiration';
    param['recordTypeFilter'] = 'groupBuy';
    return this.handleQueryRecord(param);
  }

  private async handleQueryWarranty(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    param['queryType'] = 'expiration';
    param['recordTypeFilter'] = 'warranty';
    // 如果有 productName 参数，可以在这里做额外过滤 logic
    return this.handleQueryRecord(param);
  }

  private async handleQueryRecord(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[QueryRecord] Executing query logic. Param: ${JSON.stringify(param)}`);
      const recordTypeFilter = (param['recordTypeFilter'] as string) || ''; 
      const allSubs = await SubscriptionRepository.getInstance().queryAll();
      
      const queryType = (param['queryType'] as string) || (param['query_type'] as string) || 'expiration';
      const timeRange = (param['timeRange'] as string) || (param['time_range'] as string) || 'next_30_days';

      const now = new Date();
      let startDate = 0;
      let endDate = 0;
      let dateDescription = "";
      let specificMonthQuery = false;
      let useRangeSummation = false; 

      const isExpenseQuery = queryType === 'expense';
      const isExpirationQuery = queryType === 'expiration';

      if (timeRange === 'this_year' || timeRange === 'year') {
         const currentYear = now.getFullYear();
         startDate = isExpirationQuery ? now.getTime() : new Date(currentYear, 0, 1, 0, 0, 0, 0).getTime();
         const endOfYear = new Date(currentYear, 11, 31, 23, 59, 59, 999);
         endDate = endOfYear.getTime();
         dateDescription = "今年";
         useRangeSummation = isExpenseQuery;
      } else if (timeRange === 'next_year') {
         const nextYear = now.getFullYear() + 1;
         startDate = new Date(nextYear, 0, 1, 0, 0, 0, 0).getTime();
         const endOfYear = new Date(nextYear, 11, 31, 23, 59, 59, 999);
         endDate = endOfYear.getTime();
         dateDescription = "明年";
         useRangeSummation = isExpenseQuery;
      } else if (timeRange === 'this_quarter') {
         const currMonth = now.getMonth();
         const quarterStartMonth = Math.floor(currMonth / 3) * 3;
         startDate = isExpirationQuery ? now.getTime() : new Date(now.getFullYear(), quarterStartMonth, 1, 0, 0, 0, 0).getTime();
         endDate = new Date(now.getFullYear(), quarterStartMonth + 3, 0, 23, 59, 59, 999).getTime();
         dateDescription = "本季度";
         useRangeSummation = isExpenseQuery;
      } else if (timeRange === 'next_quarter') {
         const currMonth = now.getMonth();
         const quarterStartMonth = Math.floor(currMonth / 3) * 3 + 3; 
         startDate = new Date(now.getFullYear(), quarterStartMonth, 1, 0, 0, 0, 0).getTime();
         endDate = new Date(now.getFullYear(), quarterStartMonth + 3, 0, 23, 59, 59, 999).getTime();
         dateDescription = "下季度";
         useRangeSummation = isExpenseQuery;
      } else if (timeRange === 'this_month') {
        const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
        startDate = isExpirationQuery ? now.getTime() : new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0).getTime();
        endDate = endOfMonth.getTime();
        dateDescription = "本月";
        useRangeSummation = isExpenseQuery;
      } else if (timeRange === 'next_month') {
        const startOfNextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0, 0);
        const endOfNextMonth = new Date(now.getFullYear(), now.getMonth() + 2, 0, 23, 59, 59, 999);
        startDate = startOfNextMonth.getTime();
        endDate = endOfNextMonth.getTime();
        dateDescription = "下月";
        useRangeSummation = isExpenseQuery;
        specificMonthQuery = true;
      } else {
        const yearMatch = timeRange.match(/^\d{4}$/);
        const quarterMatch = timeRange.match(/^(\d{4})[-/][qQ]([1-4])$/);

        if (yearMatch) {
             const y = parseInt(yearMatch[0]);
             startDate = new Date(y, 0, 1, 0, 0, 0, 0).getTime();
             endDate = new Date(y, 11, 31, 23, 59, 59, 999).getTime();
             dateDescription = `${y}年`;
             useRangeSummation = true;
        } else if (quarterMatch) {
             const y = parseInt(quarterMatch[1]);
             const q = parseInt(quarterMatch[2]); 
             const qStartMonth = (q - 1) * 3;
             startDate = new Date(y, qStartMonth, 1, 0, 0, 0, 0).getTime();
             endDate = new Date(y, qStartMonth + 3, 0, 23, 59, 59, 999).getTime();
             dateDescription = `${y}年${q}季度`;
             useRangeSummation = true;
        } else {
            const specificDate = new Date(timeRange);
            if (!isNaN(specificDate.getTime())) {
                 startDate = new Date(specificDate.getFullYear(), specificDate.getMonth(), 1, 0, 0, 0, 0).getTime();
                 const endOfMonth = new Date(specificDate.getFullYear(), specificDate.getMonth() + 1, 0, 23, 59, 59, 999);
                 endDate = endOfMonth.getTime();
                 dateDescription = `${specificDate.getFullYear()}年${specificDate.getMonth() + 1}月`;
                 useRangeSummation = isExpenseQuery;
                 specificMonthQuery = true;
            } else {
                 startDate = now.getTime();
                 endDate = now.getTime() + 30 * 24 * 60 * 60 * 1000;
                 dateDescription = "未来30天";
            }
        }
      }

      let activeSubs = allSubs.filter(s => {
        if (s.isDeleted) return false;
        
        // 增加类型过滤逻辑
        if (recordTypeFilter && s.recordType !== recordTypeFilter) {
          return false;
        }
        
        if (useRangeSummation) {
            // (Note: useRangeSummation is mostly true for Expense queries or multi-month ranges)
            if (s.billingCycle === 'Lifetime' || s.billingCycle === 'Indefinite' || s.recordType === 'groupBuy') {
                 if (s.recordType === 'groupBuy') {
                     const days = DateUtil.getDaysUntil(s.nextBillingDate);
                     if (s.usageStatus === 'expired' || (s.usageStatus !== 'used' && days < 0)) return false;
                 }
                 let targetDate: Date;
                 if (s.recordType === 'groupBuy') {
                    targetDate = s.realUsageTime ? new Date(s.realUsageTime) : new Date(s.nextBillingDate);
                 } else {
                    targetDate = new Date(s.startDate || s.nextBillingDate);
                 }
                 const tTime = targetDate.getTime();
                 return tTime >= startDate && tTime <= endDate;
            }

            let tempDate = s.nextBillingDate;
            if (tempDate >= startDate && tempDate <= endDate) return true;
            
            if (s.billingCycle === 'Monthly' || s.billingCycle === 'Quarterly' || s.billingCycle === 'Yearly') {
                 // Forward (Only project forward if it's an Expense query AND item auto-renews)
                 if (tempDate < startDate && s.isAutoRenewal) {
                     let d = new Date(tempDate);
                     let safety = 0;
                     while (d.getTime() < startDate && safety < 120) {
                         if (s.billingCycle === 'Monthly') d.setMonth(d.getMonth() + 1);
                         else if (s.billingCycle === 'Quarterly') d.setMonth(d.getMonth() + 3);
                         else if (s.billingCycle === 'Yearly') d.setFullYear(d.getFullYear() + 1);
                         safety++;
                     }
                     if (d.getTime() >= startDate && d.getTime() <= endDate) return true;
                 }
                 // Backward
                 if (tempDate > endDate) {
                     let d = new Date(tempDate);
                     let safety = 0;
                     while (d.getTime() > endDate && safety < 120) {
                         if (s.billingCycle === 'Monthly') d.setMonth(d.getMonth() - 1);
                         else if (s.billingCycle === 'Quarterly') d.setMonth(d.getMonth() - 3);
                         else if (s.billingCycle === 'Yearly') d.setFullYear(d.getFullYear() - 1);
                         safety++;
                     }
                     if (d.getTime() >= startDate && d.getTime() <= endDate) return true;
                 }
            }
            return false;
        }

        // Standard Expiration/Range Logic (No projection for certain future months)
        if (s.billingCycle === 'Lifetime' && s.recordType !== 'warranty') return false; 
        
        let targetRealDate = s.nextBillingDate;
        if (targetRealDate >= startDate && targetRealDate <= endDate) return true;
        
        // ONLY project for immediate rolling window (next_30_days) or CURRENT month
        const isRollingWindow = timeRange === 'next_30_days' || timeRange === 'this_month';
        if (isRollingWindow && targetRealDate < startDate && (s.billingCycle === 'Monthly' || s.billingCycle === 'Quarterly' || s.billingCycle === 'Yearly')) {
             if (!s.isAutoRenewal) return false; 
             let d = new Date(targetRealDate);
             let safety = 0;
             while (d.getTime() < startDate && safety < 120) {
                 if (s.billingCycle === 'Monthly') d.setMonth(d.getMonth() + 1);
                 else if (s.billingCycle === 'Quarterly') d.setMonth(d.getMonth() + 3);
                 else if (s.billingCycle === 'Yearly') d.setFullYear(d.getFullYear() + 1);
                 safety++;
             }
             if (d.getTime() >= startDate && d.getTime() <= endDate) return true;
        }
        return false;
      });

      // Update dates for display projection ONLY FOR EXPENSE QUERIES
      if (isExpenseQuery && activeSubs.length > 0) {
         activeSubs = activeSubs.map(s => {
             if (!s.isAutoRenewal) return s; 
             let projectedDate = s.nextBillingDate;
             if (projectedDate < startDate && (s.billingCycle === 'Monthly' || s.billingCycle === 'Quarterly' || s.billingCycle === 'Yearly')) {
                 let d = new Date(projectedDate);
                 let safety = 0;
                 while (d.getTime() < startDate && safety < 120) {
                     if (s.billingCycle === 'Monthly') d.setMonth(d.getMonth() + 1);
                     else if (s.billingCycle === 'Quarterly') d.setMonth(d.getMonth() + 3);
                     else if (s.billingCycle === 'Yearly') d.setFullYear(d.getFullYear() + 1);
                     safety++;
                 }
                 if (d.getTime() >= startDate && d.getTime() <= endDate) {
                     projectedDate = d.getTime();
                 }
             }
             if (projectedDate !== s.nextBillingDate) {
                 const newItem = JSON.parse(JSON.stringify(s)) as SubscriptionModel;
                 newItem.nextBillingDate = projectedDate;
                 return newItem;
             }
             return s;
         });
      }

      let summaryText = "";
      let resultText = "";
      const totalCount = activeSubs.length;

      let totalAmount = 0;
      
      if (useRangeSummation) {
         // Strict Range Calculation (Generalization of Year Logic)
         activeSubs.forEach(sub => {
            const price = Number(sub.price);
            if (isNaN(price) || price <= 0) return;

            // 1. One-time subscriptions
            if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite' || sub.recordType === 'groupBuy') {
                 // GroupBuy logic
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
                 
                 const tTime = targetDate.getTime();
                 if (tTime >= startDate && tTime <= endDate) {
                     totalAmount += price;
                 }
                 return;
            }

            // 2. Recurring subscriptions
            let billingDate = new Date(sub.nextBillingDate);
            if (isNaN(billingDate.getTime())) return;

            // Backtrack to find the first occurrence before or at start of range
            while (billingDate.getTime() > startDate) {
                let prevDate = new Date(billingDate);
                if (sub.billingCycle === 'Monthly') prevDate.setMonth(prevDate.getMonth() - 1);
                else if (sub.billingCycle === 'Quarterly') prevDate.setMonth(prevDate.getMonth() - 3);
                else if (sub.billingCycle === 'Yearly') prevDate.setFullYear(prevDate.getFullYear() - 1);
                else break; 
                
                // Safety break for infinite loops
                if (prevDate.getTime() < startDate - 400 * 24 * 3600 * 1000) { 
                    break;
                }
                
                if (prevDate.getTime() <= startDate) {
                    billingDate = prevDate;
                    break; 
                }
                billingDate = prevDate;
            }

            // Forward track to sum up expenses within range
            while (billingDate.getTime() <= endDate) {
                 const bTime = billingDate.getTime();
                if (bTime >= startDate && bTime <= endDate) {
                    totalAmount += price;
                }

                if (sub.billingCycle === 'Monthly') billingDate.setMonth(billingDate.getMonth() + 1);
                else if (sub.billingCycle === 'Quarterly') billingDate.setMonth(billingDate.getMonth() + 3);
                else if (sub.billingCycle === 'Yearly') billingDate.setFullYear(billingDate.getFullYear() + 1);
                else break;

                // If NOT auto-renewing, it only happens once at the recorded nextBillingDate
                if (!sub.isAutoRenewal) break; 
            }
         });
      } else {
          totalAmount = activeSubs.reduce((sum, s) => {
              if (s.recordType === 'warranty') return sum;
              return sum + s.price;
          }, 0);
      }

      if (activeSubs.length > 0) {
        if (isExpenseQuery) {
             resultText = `已为您生成${dateDescription}支出预估：总计约 ¥${totalAmount.toFixed(2)}。`;
        } else if (recordTypeFilter === 'groupBuy') {
             resultText = `已为您找到${dateDescription}即将过期的团购券共 ${totalCount} 张，请看屏幕。`;
        } else if (recordTypeFilter === 'warranty') {
             resultText = `已为您找到${dateDescription}保修记录共 ${totalCount} 条，请看屏幕。`;
        } else {
             resultText = `已为您找到${dateDescription}即将到期的订阅共 ${totalCount} 条，请看屏幕。`;
        }
      } else {
         if (recordTypeFilter === 'groupBuy') {
           resultText = `在${dateDescription}没有找到任何团购券记录。`;
         } else if (recordTypeFilter === 'warranty') {
           resultText = `在${dateDescription}没有找到相关的保修记录。`;
         } else {
           resultText = `在${dateDescription}没有找到符合要求的记录。`;
         }
      }


      if (!resultText && totalCount > 0) {
         resultText = `查询成功，共找到 ${totalCount} 条记录，请查看结果详情。`;
      } else if (!resultText && totalCount === 0) {
         resultText = `在${dateDescription}没有找到任何订阅记录。`;
      }

      const resultData: Record<string, Object> = {
        'resultText': resultText,
        'result': resultText,
        'answer': resultText,
        'text': resultText,
        'count': totalCount,
        'totalAmount': totalAmount.toFixed(2),
        'records': JSON.stringify(activeSubs), 
        'errorMessage': ""
      };

      hilog.info(0xFEED, TAG, `[RETURN] QueryRecord Result: ${JSON.stringify(resultData)}`);

      AppStorage.setOrCreate('queryResultData', resultData);
      AppStorage.setOrCreate('isQueryResultsVisible', true);

      return { code: 0, result: resultData };

    } catch (e) {
      hilog.error(0x0001, TAG, `QueryRecord failed: ${e}`);
      return {
        code: 0,
        result: {
          'resultText': "查询出错。",
          'errorMessage': `${e}`
        }
      };
    }
  }

  private async handleAddRecord(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[AddRecord] Params received: ${JSON.stringify(param)}`);
      
      const name = (param['name'] as string) || "未命名订阅";
      const priceStr = (param['price'] as string) || "0";
      // 提取数字：移除所有非数字和小数点的字符 (如 "CNY", "¥", "$")
      const cleanedPriceStr = priceStr.replace(/[^0-9.]/g, '');
      const price = parseFloat(cleanedPriceStr);
      
      // 兼容性识别：优先 billingCycle，备选 cycle
      let cycle = (param['billingCycle'] as string) || (param['cycle'] as string) || "Monthly";
      
      // 周期归一化：支持“循环”、“每月”、“年付”等口语
      const cycleLower = cycle.toLowerCase();
      if (cycleLower.includes('year') || cycleLower.includes('年')) {
        cycle = 'Yearly';
      } else if (cycleLower.includes('quarter') || cycleLower.includes('季')) {
        cycle = 'Quarterly';
      } else if (cycleLower.includes('month') || cycleLower.includes('月')) {
        cycle = 'Monthly';
      } else if (cycleLower.includes('life') || cycleLower.includes('终身') || cycleLower.includes('买断')) {
        cycle = 'Lifetime';
      } else if (cycleLower.includes('indefinite') || cycleLower.includes('不定') || cycleLower.includes('随机')) {
        cycle = 'Indefinite';
      }

      // 提取提醒天数 (默认为1天)
      let reminderDaysBefore = 1;
      if (param['reminderDaysBefore'] !== undefined) {
        reminderDaysBefore = parseInt(param['reminderDaysBefore'] as string);
      } else if (param['reminder'] !== undefined) {
        // 兼容口语化参数名
        const reminderStr = param['reminder'] as string;
        const match = reminderStr.match(/(\d+)/);
        if (match) {
          reminderDaysBefore = parseInt(match[1]);
        }
      }

      // 自动尝试匹配图标
      let iconPath = '';
      try {
        // 1. 尝试从本地图标库匹配 (LocalIconManager)
        let appInfo = await LocalIconManager.getInstance().getAppInfo(name);
        
        // 2. 如果没匹配到，尝试去掉常见后缀再次匹配 (如：腾讯视频会员 -> 腾讯视频)
        if (!appInfo) {
          const cleanName = name.replace(/(会员|VIP|订阅|套餐|卷|代金券|服务|卡|Premium|Member)$/i, '').trim();
          if (cleanName && cleanName !== name) {
            hilog.info(0xFEED, TAG, `[AddRecord] Retry icon match with cleaned name: ${cleanName}`);
            appInfo = await LocalIconManager.getInstance().getAppInfo(cleanName);
          }
        }

        if (appInfo && appInfo.icon) {
          iconPath = appInfo.icon;
          hilog.info(0xFEED, TAG, `[AddRecord] Auto-detected local app icon: ${iconPath}`);
        } else {
          // 3. 尝试从服务配置库匹配 (MemberServiceConfig)
          const service = matchMemberService(name);
          if (service && service.icon) {
            iconPath = service.icon;
            hilog.info(0xFEED, TAG, `[AddRecord] Auto-detected service config icon: ${iconPath}`);
          }
        }
      } catch (iconErr) {
        hilog.warn(0xFEED, TAG, `[AddRecord] Failed to detect icon: ${iconErr}`);
      }

      // 提取日期 (YYYY-MM-DD)
      const expireDateStr = (param['expireDate'] as string);
      const purchaseDateStr = (param['purchaseDate'] as string);
      
      let nextBillingDate = new Date().getTime();
      let startDate = new Date().getTime();

      if (expireDateStr) {
        const date = new Date(expireDateStr);
        if (!isNaN(date.getTime())) {
          nextBillingDate = date.getTime();
        }
      }
      
      if (purchaseDateStr) {
        const date = new Date(purchaseDateStr);
        if (!isNaN(date.getTime())) {
          startDate = date.getTime();
        }
      }

      // 智能推算到期日：如果用户未提供到期日，但提供了开始日期或使用了默认开始日期(今)，
      // 且周期为 Monthly/Yearly/Quarterly，则自动往后推算。
      if (!expireDateStr && cycle !== 'Lifetime' && cycle !== 'Indefinite') {
        const d = new Date(startDate);
        if (cycle === 'Monthly') {
          d.setMonth(d.getMonth() + 1);
        } else if (cycle === 'Quarterly') {
          d.setMonth(d.getMonth() + 3);
        } else if (cycle === 'Yearly') {
          d.setFullYear(d.getFullYear() + 1);
        }
        nextBillingDate = d.getTime();
        hilog.info(0xFEED, TAG, `[AddRecord] Auto-calculated nextBillingDate: ${d.toISOString()} based on cycle ${cycle}`);
      }

      // SubscriptionModel 是接口，使用对象字面量初始化
      const newSub: SubscriptionModel = {
        uuid: util.generateRandomUUID(true), 
        name: name,
        price: isNaN(price) ? 0 : price,
        billingCycle: cycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
        nextBillingDate: nextBillingDate,
        startDate: startDate,
        currency: 'CNY',
        icon: iconPath, 
        lastModified: new Date().getTime(),
        isDeleted: false,
        isAutoRenewal: true,
        reminderDaysBefore: reminderDaysBefore,
        reminderTime: "09:00"
      };

      await SubscriptionRepository.getInstance().insert(newSub);

      const resultText = `已为您添加${cycle === 'Yearly' ? '年付' : '订阅'}：${name}，金额 ¥${price}。将在到期前 ${reminderDaysBefore} 天提醒您。`;
      
      const resultData: Record<string, Object> = {
        'resultText': resultText
      };

      hilog.info(0xFEED, TAG, `[RETURN] AddRecord Result: ${JSON.stringify(resultData)}`);
      return { code: 0, result: resultData };

    } catch (e) {
      hilog.error(0x0001, TAG, `AddRecord failed: ${e}`);
      return {
        code: 0,
        result: {
          'resultText': "添加订阅失败。",
          'errorMessage': `${e}`
        }
      };
    }
  }
}
