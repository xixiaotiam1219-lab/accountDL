import { common, insightIntent, InsightIntentExecutor } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionModel, ExtendedWarrantyItem } from '../model/SubscriptionModel';
import { LocalIconManager } from '../utils/LocalIconManager';
import { matchMemberService } from '../utils/MemberServiceConfig';
import { util } from '@kit.ArkTS';

const TAG = 'InsightIntentExecutorImpl';

interface AgentRecordItem {
  title: string;
  content: string;
  price: number;
}

interface LeanRecord {
  name: string;
  price: number;
  cycle: string;
  date: string;
  type: string;
  brand: string;
  status: string;
}

interface HotTopicItem {
  title: string;
  subtitle?: string;
  footer?: string;
}

interface DataPackageItem {
  title: string;
}

class Constants {
  public static INTENT_CHECK_LOGIN = "CheckLogin";
  public static INTENT_ADD_RECORD = "AddRecord";
  public static INTENT_ADD_SUBSCRIPTION = "AddSubscription";
  public static INTENT_ADD_VOUCHER = "AddVoucher";
  public static INTENT_ADD_WARRANTY = "AddWarranty";
  public static INTENT_QUERY_RECORD = "QueryRecord";
  public static INTENT_GET_ALL_RECORDS = "GetAllRecords";
  public static INTENT_QUERY_SUBSCRIPTION = "QuerySubscription";
  public static INTENT_QUERY_VOUCHER = "QueryVoucher";
  public static INTENT_QUERY_WARRANTY = "QueryWarranty";
  public static INTENT_ADD_CARD = "AddCard";
  public static INTENT_QUERY_CARD = "QueryCard";
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
      await PreferenceUtil.getInstance().loadPreference(context);
      // 关键：冷启动环境下 AppStorage 为空，必须重新从持久化库加载登录态
      const session = await PreferenceUtil.getInstance().loadSession();
      if (session && session['isLoggedIn'] !== undefined) {
        AppStorage.setOrCreate('isLoggedIn', session['isLoggedIn'] as boolean);
        hilog.info(0xFEED, TAG, `Restored login status during foreground cold start: ${session['isLoggedIn']}`);
      }
      await SubscriptionRepository.getInstance().init(context);
      await LocalIconManager.getInstance().init(context);
    } catch (e) {
      hilog.error(0x0001, TAG, `Quick Initialize failed during foreground execute: ${e}`);
    }

    if (name === Constants.INTENT_CHECK_LOGIN) {
      return this.executeCheckLogin();
    }

    const loginCheck = this.checkLoginStatus();
    if (loginCheck) {
      return loginCheck;
    }

    // 2. 如果是查询类意图，直接分发数据逻辑
    if (this.isQueryIntent(name)) {
      const res = await this.handleQueryDispatch(name, param);
      // 前台模式通常返回包装好的 resultData
      return {
        code: 0,
        result: res.result as Record<string, Object>
      };
    }

    // 3. 非查询类意图 (目前主要意图已迁移至后台，这里作为 fallback)
    return {
      code: 0,
      result: { 'result': 'success' }
    };
  }

  private checkLoginStatus(): insightIntent.ExecuteResult | null {
    const isLoggedIn = AppStorage.get<boolean>('isLoggedIn');
    if (!isLoggedIn) {
      hilog.warn(0xFEED, TAG, `Intent Execution blocked: User not logged in.`);
      return {
        code: 0,
        result: {
          'resultText': "抱歉，您需要先长按桌面图标打开记得订阅APP进行登录，才能让我帮您记录或查询。",
          'errorMessage': "User not logged in",
          'showPackage': 'false',
          'dataPackage': []
        }
      };
    }
    return null;
  }

  private executeCheckLogin(): insightIntent.ExecuteResult {
    const isLoggedIn = AppStorage.get<boolean>('isLoggedIn') || false;

    return {
      code: 0,
      result: {
        'resultCode': isLoggedIn
      }
    };
  }

  private isQueryIntent(name: string): boolean {
    return name === Constants.INTENT_GET_ALL_RECORDS ||
      name === Constants.INTENT_QUERY_VOUCHER ||
      name === Constants.INTENT_QUERY_WARRANTY ||
      name === Constants.INTENT_QUERY_SUBSCRIPTION ||
      name === Constants.INTENT_QUERY_CARD ||
      name === Constants.INTENT_QUERY_RECORD;
  }

  private async handleQueryDispatch(name: string, param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `[QueryDispatch] Dispatching intent: ${name}`);
    if (name === Constants.INTENT_GET_ALL_RECORDS) {
      return this.handleGetAllRecords(param);
    } else if (name === Constants.INTENT_QUERY_VOUCHER) {
      return this.handleQueryVoucher(param);
    } else if (name === Constants.INTENT_QUERY_WARRANTY) {
      return this.handleQueryWarranty(param);
    } else if (name === Constants.INTENT_QUERY_CARD) {
      param['recordTypeFilter'] = 'card';
      return this.executeQueryCore(param);
    } else if (name === Constants.INTENT_QUERY_SUBSCRIPTION) {
      param['recordTypeFilter'] = 'subscription';
      return this.executeQueryCore(param);
    } else {
      // QueryRecord 或其他未知查询，执行动态推断逻辑
      let queryTypeStr = ((param['queryType'] as string) || "").toLowerCase();
      let timeRangeStr = ((param['timeRange'] as string) || "").toLowerCase();
      let combinedParam = queryTypeStr + " " + timeRangeStr;
      let inferredType = '';
      const nameStr = ((param['name'] as string) || "").toLowerCase();
      const rawQuery = (combinedParam + " " + nameStr);

      if (rawQuery.includes('保修') || rawQuery.includes('保质期') || rawQuery.includes('延保') || rawQuery.includes('售后') || rawQuery.includes('保险') || rawQuery.includes('warranty')) {
        inferredType = 'warranty';
      } else if (rawQuery.includes('团购') || rawQuery.includes('券') || rawQuery.includes('次卡') || rawQuery.includes('返利') || rawQuery.includes('礼品') || rawQuery.includes('voucher') || rawQuery.includes('groupbuy')) {
        inferredType = 'groupBuy';
      } else if (rawQuery.includes('卡') || rawQuery.includes('证') || rawQuery.includes('card')) {
        inferredType = 'card';
      }

      if (inferredType) {
        param['recordTypeFilter'] = inferredType;
      }
      return this.executeQueryCore(param);
    }
  }

  /**
   * override 执行后台UIAbility意图
   *
   * @param name 意图名称
   * @param param 意图参数
   * @returns 意图调用结果
   */
  async onExecuteInUIAbilityBackgroundMode(name: string, param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityBackgroundMode calling intent: name=${name}`);

    try {
      const context = (this.context as Object) as common.UIAbilityContext;
      await PreferenceUtil.getInstance().loadPreference(context);
      // 关键：冷启动环境下 AppStorage 为空，必须重新从持久化库加载登录态
      const session = await PreferenceUtil.getInstance().loadSession();
      if (session && session['isLoggedIn'] !== undefined) {
        AppStorage.setOrCreate('isLoggedIn', session['isLoggedIn'] as boolean);
        hilog.info(0xFEED, TAG, `Restored login status during background cold start: ${session['isLoggedIn']}`);
      }
      await SubscriptionRepository.getInstance().init(context);
      await LocalIconManager.getInstance().init(context);
    } catch (e) {
      hilog.error(0x0001, TAG, `Initialization failed: ${e}`);
    }

    if (name === Constants.INTENT_CHECK_LOGIN) {
      return this.executeCheckLogin();
    }

    const loginCheck = this.checkLoginStatus();
    if (loginCheck) {
      return loginCheck;
    }

    // 处理查询意图 (已在 insight_intent.json 配置为 background)
    if (this.isQueryIntent(name)) {
      return this.handleQueryDispatch(name, param);
    }

    switch (name) {
      case Constants.INTENT_ADD_RECORD:
        return this.executeAddCore(param);
      case Constants.INTENT_ADD_SUBSCRIPTION:
        param['recordType'] = 'subscription';
        return this.executeAddCore(param);
      case Constants.INTENT_ADD_VOUCHER:
        param['recordType'] = 'groupBuy';
        return this.executeAddCore(param);
      case Constants.INTENT_ADD_WARRANTY:
        param['recordType'] = 'warranty';
        return this.executeAddCore(param);
      case Constants.INTENT_ADD_CARD:
        param['recordType'] = 'card';
        return this.executeAddCore(param);
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

  private async handleGetAllRecords(param?: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[GetAllRecords] Executing full dump intent. Param: ${JSON.stringify(param)}`);

      // 如果传入了时间范围，则复用 QueryCore 的过滤和动态计算逻辑
      if (param && (param['timeRange'] || param['time_range'])) {
        return this.executeQueryCore(param);
      }

      const allSubs = await SubscriptionRepository.getInstance().queryAll();
      const activeSubs = allSubs.filter(s => !s.isDeleted);

      const totalCount = activeSubs.length;
      // 热点条目格式：带有序号的名称、日期与价格三分离 (title & subtitle & footer)
      const dataPackage = activeSubs.map((s: SubscriptionModel, index: number): HotTopicItem => {
        const dateStr = DateUtil.formatDate(s.nextBillingDate);
        const actionStr = s.recordType === 'warranty' ? (s.nextBillingDate < new Date().getTime() ? '已过保' : '在保') : '到期';
        const cycleText = s.recordType === 'subscription' ? this.getCycleText(s.billingCycle as string) : '';
        const priceStr = s.recordType === 'warranty' ? '' : `${s.currency === 'USD' ? '$' : '¥'}${s.price.toFixed(2)}`;

        return {
          title: `${index + 1}. ${s.name}${s.brand ? ` (${s.brand})` : ''}`,
          subtitle: '', // 置空，所有信息聚合到 footer
          footer: `${dateStr} ${actionStr}${priceStr ? ` ${priceStr}` : ''}${cycleText ? ` ${cycleText}` : ''}`
        };
      });

      const resultText = totalCount > 0
        ? `查询成功，为您找到 ${totalCount} 条记录。`
        : "您目前没有任何订阅或消费记录。";

      const resultData: Record<string, Object> = {
        'resultText': resultText,
        'showPackage': totalCount > 0 ? "true" : "false", // 修改为字符串，符合项目内布尔参数习惯
        'dataPackage': dataPackage // 直接返回对象数组
      };

      hilog.info(0xFEED, TAG, `[RETURN] GetAllRecords Final Result (Ultra Lean): ${JSON.stringify(resultData)}`);

      // 移除原有的 UI 触发逻辑，数据全量透明传递
      return {
        code: 0,
        result: resultData
      };
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0001, TAG, `GetAllRecords failed: ${err.message}`);
      const errRes: Record<string, Object> = {
        'resultText': "查询全部数据时出错。",
        'errorMessage': `${err.message}`
      };
      return {
        code: 0,
        result: errRes
      };
    }
  }

  private async handleQueryVoucher(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    param['queryType'] = 'expiration';
    param['recordTypeFilter'] = 'groupBuy';
    return this.executeQueryCore(param);
  }

  private async handleQueryWarranty(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    param['queryType'] = 'expiration';
    param['recordTypeFilter'] = 'warranty';
    if (param['productName']) {
      param['name'] = param['productName'];
    }
    return this.executeQueryCore(param);
  }

  private async executeQueryCore(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[QueryCore] Executing query logic. Param: ${JSON.stringify(param)}`);
      let recordTypeFilter = (param['recordTypeFilter'] as string) || '';
      const allSubs = await SubscriptionRepository.getInstance().queryAll();

      // 展开延保数据为独立条目，支持 "主商品·延保名称" 格式显示
      const expandedSubs: SubscriptionModel[] = [];
      allSubs.forEach(s => {
        expandedSubs.push(s);
        if (s.extendedWarranties) {
          try {
            const warranties = JSON.parse(s.extendedWarranties) as ExtendedWarrantyItem[];
            if (warranties && warranties.length > 0) {
              warranties.forEach(w => {
                // 构造虚拟条目
                const virtualSub: SubscriptionModel = {
                  uuid: s.uuid + '_ext_' + w.id,
                  name: `${s.name}·${w.name}`,
                  price: parseFloat(w.price) || 0,
                  currency: s.currency,
                  billingCycle: 'Lifetime',
                  nextBillingDate: w.date,
                  startDate: s.startDate, // 沿用主条目购买时间
                  icon: s.icon,
                  category: s.category,
                  lastModified: s.lastModified,
                  isDeleted: s.isDeleted,
                  recordType: 'warranty',
                  brand: s.brand,
                  purchaseChannel: s.purchaseChannel,
                  isAutoRenewal: false
                };
                expandedSubs.push(virtualSub);
              });
            }
          } catch (e) {
            hilog.warn(0xFEED, TAG, `Failed to parse extended warranties for ${s.name}: ${e}`);
          }
        }
      });

      // 动态推断 recordTypeFilter
      // 场景：用户说“查一下今年的保修”，小艺触发了 QueryRecord，但没传 recordTypeFilter，且 timeRange="this_year" 或 name="保修"
      if (!recordTypeFilter) {
        const timeRangeStr = (param['timeRange'] as string) || '';
        const nameStr = (param['name'] as string) || '';
        const rawQuery = JSON.stringify(param); // 作为 fallback，检查整个参数里有没有关键字

        if (nameStr.includes('保修') || nameStr.includes('保质期') || timeRangeStr.includes('保修') || rawQuery.includes('保修') || timeRangeStr.includes('险') || nameStr.includes('险')) {
          recordTypeFilter = 'warranty';
        } else if (nameStr.includes('团购') || nameStr.includes('券') || timeRangeStr.includes('券') || rawQuery.includes('团购')) {
          recordTypeFilter = 'groupBuy';
        }
      }

      const queryType = (param['queryType'] as string) || (param['query_type'] as string) || 'expiration';
      const timeRange = (param['timeRange'] as string) || (param['time_range'] as string) || '';
      const filterBrand = (param['brand'] as string)?.toLowerCase();
      const filterName = (param['name'] as string)?.toLowerCase();

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
      } else if (timeRange === 'this_week') {
        const currDay = now.getDay(); // 0 (Sun) - 6 (Sat)
        // Assume Monday is the start of the week
        const diffToMon = currDay === 0 ? 6 : currDay - 1;
        const startOfWeek = new Date(now.getFullYear(), now.getMonth(), now.getDate() - diffToMon, 0, 0, 0, 0);
         const endOfWeek = new Date(startOfWeek.getTime() + 7 * 24 * 60 * 60 * 1000 - 1);
         
         startDate = isExpirationQuery ? now.getTime() : startOfWeek.getTime();
        endDate = endOfWeek.getTime();
        dateDescription = "本周";
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
      } else if (timeRange === 'this_half_year' || timeRange === 'half_year' || timeRange === 'last_6_months') {
        // [修复] 支持半年内查询。兼容小艺传来的 last_6_months 参数，统一识别为“半年内”双向窗口
        const startOfHalfYear = isExpirationQuery ? now.getTime() : new Date(now.getFullYear(), now.getMonth() - 6, 1, 0, 0, 0, 0).getTime();
        const endOfHalfYear = new Date(now.getFullYear(), now.getMonth() + 6, now.getDate(), 23, 59, 59, 999);
        startDate = startOfHalfYear;
        endDate = endOfHalfYear.getTime();
        dateDescription = "半年内";
        useRangeSummation = isExpenseQuery;
      } else {
        const yearMatch = timeRange.match(/^\d{4}$/);
        const quarterMatch = timeRange.match(/^(\d{4})[-/][qQ]([1-4])$/);
        // 新增：识别 "未来 X 天/月/年" 或 "过去 X 天/月/年" 等动态天数
        const dynamicMatch = timeRange.match(/^(next|last|past|in|within)_(\d+)_?(days?|months?|years?|weeks?)$/i);

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
        } else if (dynamicMatch) {
          const direction = dynamicMatch[1].toLowerCase();
          const amount = parseInt(dynamicMatch[2]);
          const unit = dynamicMatch[3].toLowerCase();

          const isFuture = direction === 'next' || direction === 'in' || direction === 'within';

          let targetDate = new Date(now.getTime());

          if (unit.startsWith('day')) {
            targetDate.setDate(targetDate.getDate() + (isFuture ? amount : -amount));
            dateDescription = isFuture ? `未来 ${amount} 天` : `过去 ${amount} 天`;
          } else if (unit.startsWith('week')) {
            targetDate.setDate(targetDate.getDate() + (isFuture ? amount * 7 : -amount * 7));
            dateDescription = isFuture ? `未来 ${amount} 周` : `过去 ${amount} 周`;
          } else if (unit.startsWith('month')) {
            targetDate.setMonth(targetDate.getMonth() + (isFuture ? amount : -amount));
            dateDescription = isFuture ? `未来 ${amount} 个月` : `过去 ${amount} 个月`;
          } else if (unit.startsWith('year')) {
            targetDate.setFullYear(targetDate.getFullYear() + (isFuture ? amount : -amount));
            dateDescription = isFuture ? `未来 ${amount} 年` : `过去 ${amount} 年`;
          }

          if (isFuture) {
            startDate = now.getTime();
            endDate = targetDate.getTime();
          } else {
            // [优化] 如果不是支出查询（即查询记录、到期、卡证等），
            // 即使传入的是 last_ (过去)，也应该自动扩展到未来窗口，
            // 否则用户查“去年的卡证”会漏掉还没过期的。
            if (!isExpenseQuery) {
              // 构造对称的未来日期
              let futureTarget = new Date(now.getTime());
              if (unit.startsWith('day')) futureTarget.setDate(futureTarget.getDate() + amount);
              else if (unit.startsWith('week')) futureTarget.setDate(futureTarget.getDate() + amount * 7);
              else if (unit.startsWith('month')) futureTarget.setMonth(futureTarget.getMonth() + amount);
              else if (unit.startsWith('year')) futureTarget.setFullYear(futureTarget.getFullYear() + amount);
              
              startDate = targetDate.getTime(); // 过去 X 
              endDate = futureTarget.getTime();  // 未来 X
              dateDescription = `${dateDescription.replace('过去 ', '')}内`;
            } else {
              startDate = targetDate.getTime();
              endDate = now.getTime();
            }
          }
          useRangeSummation = isExpenseQuery;

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
            const isWarrantyQuery = recordTypeFilter === 'warranty';
            if (isWarrantyQuery) {
              // 保修查询默认覆盖：过去30天(兼容刚过保) 到 未来2年
              startDate = now.getTime() - 30 * 24 * 60 * 60 * 1000;
              endDate = now.getTime() + 730 * 24 * 60 * 60 * 1000;
              dateDescription = "所有";
            } else if (recordTypeFilter === 'card') {
              // [修复] 卡证查询默认窗口放大，避免被 30 天限制过滤
              startDate = now.getTime() - 365 * 24 * 60 * 60 * 1000;
              endDate = now.getTime() + 365 * 24 * 60 * 60 * 1000;
              dateDescription = "所有";
            } else {
              startDate = now.getTime();
              endDate = now.getTime() + 30 * 24 * 60 * 60 * 1000;
              dateDescription = "未来30天";
            }
          }
        }
      }

      let activeSubs = expandedSubs.filter(s => {
        if (s.isDeleted) return false;

        // 增加类型过滤逻辑
        if (recordTypeFilter && s.recordType !== recordTypeFilter) {
          return false;
        }

        // 新增：名称/品牌精确过滤 (主要针对保修和券)
        if (filterBrand || (filterName && filterName !== '保修' && filterName !== '延保' && filterName !== '团购券' && !filterName.includes('保质期'))) {
          let matched = false;
          const sName = s.name.toLowerCase();
          const sBrand = s.brand?.toLowerCase() || '';

          if (filterBrand && (sBrand.includes(filterBrand) || sName.includes(filterBrand))) {
            matched = true;
          } else if (filterName && (sName.includes(filterName) || sBrand.includes(filterName))) {
            matched = true;
          }

          if (!matched) return false;
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

        // Standard Expiration/Range Logic
        // 修正：允许卡证(Indefinite)和保修(Lifetime)参与到期过滤
        if (s.billingCycle === 'Lifetime' || s.billingCycle === 'Indefinite' || s.recordType === 'groupBuy') {
           // 对于这些类型，直接判断其 nextBillingDate (即到期日) 是否在范围内
           if (s.nextBillingDate >= startDate && s.nextBillingDate <= endDate) return true;
           return false;
        }

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
          resultText = `已为您找到${dateDescription}即将过期的团购券共 ${totalCount} 张。`;
        } else if (recordTypeFilter === 'warranty') {
          resultText = `已为您找到${dateDescription}保修记录共 ${totalCount} 条。`;
        } else if (recordTypeFilter === 'card') {
          resultText = `已为您找到${dateDescription}卡证记录共 ${totalCount} 条。`;
        } else {
          resultText = `已为您找到${dateDescription}即将到期的订阅共 ${totalCount} 条。`;
        }
      } else {
        if (recordTypeFilter === 'groupBuy') {
          resultText = `在${dateDescription}没有找到任何团购券记录。`;
        } else if (recordTypeFilter === 'warranty') {
          resultText = `在${dateDescription}没有找到相关的保修记录。`;
        } else if (recordTypeFilter === 'card') {
          resultText = `在${dateDescription}没有找到相关的卡证记录。`;
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
        'totalAmount': totalAmount.toFixed(2),
        'resultText': resultText,
        'errorMessage': ""
      };

      // 聚合全量精简数据供 LLM 理解 (保留作为底层数据参考)
      if (activeSubs.length > 0) {
        const leanRecords = activeSubs.map((s): LeanRecord => {
          return {
            name: s.name,
            price: s.price,
            cycle: s.billingCycle,
            date: DateUtil.formatDate(s.nextBillingDate),
            type: s.recordType || 'subscription',
            brand: s.brand || '',
            status: s.usageStatus || (s.isAutoRenewal ? 'auto_renew' : 'manual')
          };
        });
        // 新增：生成适配“热点条目”格式的数据包 (带序号、三分离)
        const dataPackage = activeSubs.map((s: SubscriptionModel, index: number): HotTopicItem => {
          const dateStr = DateUtil.formatDate(s.nextBillingDate);
          const actionStr = s.recordType === 'warranty' ? (s.nextBillingDate < new Date().getTime() ? '已过保' : '在保') : '到期';
          const cycleText = s.recordType === 'subscription' ? this.getCycleText(s.billingCycle as string) : '';
          const priceStr = s.recordType === 'warranty' ? '' : `${s.currency === 'USD' ? '$' : '¥'}${s.price.toFixed(2)}`;

          return {
            title: `${index + 1}. ${s.name}${s.brand ? ` (${s.brand})` : ''}`,
            subtitle: '', // 置空，所有信息聚合到 footer
            footer: `${dateStr} ${actionStr}${priceStr ? ` ${priceStr}` : ''}${cycleText ? ` ${cycleText}` : ''}`
          };
        });
        resultData['dataPackage'] = dataPackage; // 直接返回对象数组
        resultData['showPackage'] = dataPackage.length > 0 ? "true" : "false"; // 修改为字符串，符合项目内布尔参数习惯

      } else {
        resultData['dataPackage'] = [];
        resultData['showPackage'] = "false"; // 修改为字符串
      }

      hilog.info(0xFEED, TAG, `[RETURN] QueryCore Result (Data Driven): ${JSON.stringify(resultData)}`);

      return { code: 0, result: resultData };

    } catch (e) {
      const err = e as Error;
      hilog.error(0x0001, TAG, `QueryCore failed: ${err.message}`);
      const errRes: Record<string, Object> = {
        'resultText': "查询出错。",
        'errorMessage': `${err.message}`
      };
      return {
        code: 0,
        result: errRes
      };
    }
  }

  private async executeAddCore(param: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    try {
      hilog.info(0xFEED, TAG, `[HandleAddCore] Params received: ${JSON.stringify(param)}`);

      const nameInput = (param['name'] as string) || "未命名订阅";
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
        cycle = 'Indefinite';
      } else if (cycleLower.includes('indefinite') || cycleLower.includes('不定') || cycleLower.includes('随机')) {
        cycle = 'Indefinite';
      }

      // ==== 1. 优先判定业务类型 (recordType) ====
      let recordType: 'subscription' | 'groupBuy' | 'warranty' | 'card' = 'subscription';
      const recordTypeParam = param['recordType'] as string;
      if (recordTypeParam === 'groupBuy' || recordTypeParam === 'groupbuy' || recordTypeParam === 'group_buy') {
        recordType = 'groupBuy';
      } else if (recordTypeParam === 'warranty') {
        recordType = 'warranty';
        cycle = 'Lifetime';
      } else if (recordTypeParam === 'subscription') {
        recordType = 'subscription';
      } else if (recordTypeParam === 'card') {
        recordType = 'card';
        cycle = 'Indefinite';
      } else if (nameInput.toLowerCase().match(/保修|延保|碎屏险|保质期|售后|care/)) {
        recordType = 'warranty';
        cycle = 'Lifetime';
      } else if (nameInput.toLowerCase().match(/卡$|证$/)) {
        recordType = 'card';
        cycle = 'Indefinite';
      }

      // ==== 2. 品牌与名称净化逻辑 (仅限保修) ====
      const brandInput = (param['brand'] as string) || (param['merchantName'] as string) || '';
      let brandParam = brandInput;
      let finalName = nameInput;

      if (!brandParam && nameInput && recordType === 'warranty') {
        // [扩充] 常见品牌列表
        const Brands = [
          '华为', '苹果', '小米', '荣耀', 'OPPO', 'VIVO', '魅族', '努比亚', '真我', 'realme', '中兴', 'ZTE', '锤子', '坚果', '一加', 'OnePlus', '联想', 'Lenovo', '小新', '拯救者',
          '戴尔', 'DELL', '惠普', 'HP', '华硕', 'ASUS', '微星', 'MSI', '宏碁', 'Acer', '雷神', '机械革命', '七彩虹', '影驰', '蓝宝石', '索泰', '芝奇', '海盗船',
          '三星', 'SAMSUNG', '索尼', 'SONY', '大疆', 'DJI', '罗技', 'Logitech', '雷蛇', 'Razer', '漫步者', '惠威', '山灵', '飞傲', 'Fiio', '极米', '当贝', '坚果投影', '海信', 'TCL', '创维', '康佳', '长虹',
          '海尔', 'Haier', '美的', 'Midea', '格力', 'Gree', '西门子', 'SIEMENS', '松下', 'Panasonic', '飞利浦', 'Philips', '戴森', 'Dyson', '石头', 'roborock', '科沃斯', 'ECOVACS', '九阳', 'Joyoung', '苏泊尔', 'SUPOR', '小熊', '米家', '云米', '智米', '方太', '老板',
          '微软', 'Microsoft', '任天堂', 'Nintendo', 'Switch', 'PlayStation', 'PS5', 'Xbox', '米哈游', 'Mihoyo', '原神', '网易游戏', '腾讯游戏',
          '比亚迪', 'BYD', '蔚来', 'NIO', '小鹏', 'Xpeng', '理想', 'Li', '问界', 'AITO', '极氪', 'ZEEKR', '小米汽车', '长安', '奇瑞', '吉利', '长城', '五菱',
          '爱奇艺', '腾讯', '优酷', '芒果TV', '哔哩哔哩', 'B站', '网易', '百度', '字节跳动', '抖音', '阿里', '淘宝', '闲鱼', '支付宝', '微信', 'QQ', '咪咕', '知乎', '小红书', '京东', '拼多多', '美团', '饿了么', '大众点评',
          'Apple', 'Huawei', 'Xiaomi', 'Google', 'Tesla', 'Meta', 'Amazon', 'Intel', 'AMD', 'NVIDIA'
        ];
        for (const b of Brands) {
          if (nameInput.startsWith(b)) {
            brandParam = b;
            const potentialName = nameInput.substring(b.length).trim();
            if (potentialName) {
              finalName = potentialName;
            }
            break;
          }
        }
      }

      const name = finalName;
      const platformRaw = param['platform'] as string;
      const couponCode = (param['couponCode'] as string) || '';
      const merchantName = (param['merchantName'] as string) || '';
      const usageTime = (param['usageTime'] as string) || '';
      const purchaseChannel = (param['purchaseChannel'] as string) || '';

      // 平台映射规范化
      let platformParam: 'meituan' | 'douyin' | 'dianping' | undefined = undefined;
      const lowerPlatform = (platformRaw || '').toLowerCase();
      if (lowerPlatform === 'meituan' || lowerPlatform.includes('美团')) {
        platformParam = 'meituan';
      } else if (lowerPlatform === 'douyin' || lowerPlatform.includes('抖音')) {
        platformParam = 'douyin';
      } else if (lowerPlatform === 'dianping' || lowerPlatform.includes('点评')) {
        platformParam = 'dianping';
      }

      // 团购券关键词补偿识别 (仅当 recordType 尚未通过参数显式确定为保修时)
      if (recordType === 'subscription') {
        const nameLower = name.toLowerCase();
        if (nameLower.includes('券') || nameLower.includes('团购') || nameLower.includes('次卡') || nameLower.includes('体验') ||
        nameLower.includes('代金') || nameLower.includes('抵用') || nameLower.includes('套餐') ||
        nameLower.includes('美团') || nameLower.includes('瑞幸') || nameLower.includes('星巴克') || nameLower.includes('大众点评') ||
        nameLower.includes('抖音') || nameLower.includes('快手')) {
          recordType = 'groupBuy';
        }
      }

      // 自动尝试匹配图标
      let iconPath = '';

      // 特殊逻辑：对于已识别平台的团购券，强制使用平台品牌图标
      if (recordType === 'groupBuy') {
        if (platformParam === 'meituan') iconPath = 'builtin://美团.png';
        else if (platformParam === 'douyin') iconPath = 'builtin://抖音.png';
        else if (platformParam === 'dianping') iconPath = 'builtin://大众点评.png';
      } else if (recordType === 'warranty' && (param['category'] as string)) {
        iconPath = 'warranty_icon:' + (param['category'] as string);
      } else if (recordType === 'card') {
        iconPath = 'builtin://卡证.png';
      }

      if (!iconPath) {
        try {
          const iconManager = LocalIconManager.getInstance();
          let appInfo = await iconManager.getAppInfo(name);

          // 校验匹配质量
          if (appInfo) {
            const matchedName = appInfo.name.toLowerCase();
            const inputName = name.toLowerCase();
            if (!inputName.includes(matchedName) && !matchedName.includes(inputName)) {
              hilog.info(0xFEED, TAG, `[AddCore] Discarding weak match: ${appInfo.name} for ${name}`);
              appInfo = null;
            }
          }

          let cleanName = name.replace(/^(订阅了|关注了|购买了|开通了)/g, '').trim();
          const noiseRegex = /(超级|至尊|黄金|白金|星钻|大会员|旗舰版|标准版|专业版|会员|VIP|会员卡|订阅|套餐|券|代金券|服务|卡|Premium|Member|PLUS)$/i;
          let lastCleanName = '';
          do {
            lastCleanName = cleanName;
            cleanName = cleanName.replace(noiseRegex, '').trim();
          } while (cleanName !== lastCleanName);

          if (!appInfo) {
            if (cleanName && cleanName !== name) {
              hilog.info(0xFEED, TAG, `[AddCore] Retry icon match with cleaned name: ${cleanName}`);
              appInfo = await iconManager.getAppInfo(cleanName);

              if (appInfo) {
                const matchedName = appInfo.name.toLowerCase();
                const inputCleanName = cleanName.toLowerCase();
                if (!inputCleanName.includes(matchedName) && !matchedName.includes(inputCleanName)) {
                  appInfo = null;
                }
              }
            }
          }

          if (appInfo && appInfo.icon) {
            iconPath = appInfo.icon;
            hilog.info(0xFEED, TAG, `[AddCore] Auto-detected local app icon: ${iconPath}`);
          } else {
            const service = matchMemberService(cleanName || name);
            if (service) {
              iconPath = `builtin://${service.name}.png`;
              hilog.info(0xFEED, TAG, `[AddCore] Auto-detected service config icon: ${iconPath}`);
            } else {
              const targetIconName = cleanName || name;
              iconPath = `builtin://${targetIconName}.png`;
              hilog.info(0xFEED, TAG, `[AddCore] Fallback to inferred builtin icon: ${iconPath}`);
            }
          }
        } catch (iconErr) {
          hilog.warn(0xFEED, TAG, `[AddCore] Failed to detect icon: ${iconErr}`);
        }
      }

      // 提取日期 (YYYY-MM-DD)
      const expireDateStr = (param['expireDate'] as string) || (param['expiredDate'] as string);
      const purchaseDateStr = (param['purchaseDate'] as string) || (param['purchasedDate'] as string);

      let nextBillingDate = new Date().getTime();
      let startDate = new Date().getTime();

      if (expireDateStr) {
        // 兼容性处理：部分环境不支持 YYYY-MM-DD，统一转为 YYYY/MM/DD
        const safeDateStr = expireDateStr.replace(/-/g, '/');
        const date = new Date(safeDateStr);
        if (!isNaN(date.getTime())) {
          nextBillingDate = date.getTime();
        }
      }

      if (purchaseDateStr) {
        const safeDateStr = purchaseDateStr.replace(/-/g, '/');
        const date = new Date(safeDateStr);
        if (!isNaN(date.getTime())) {
          startDate = date.getTime();
        }
      }

      let isReminderEnabled = false;
      let reminderDaysBefore = 1;
      const needReminderRaw = param['isReminderEnabled'];
      const needReminderStr = needReminderRaw !== undefined ? String(needReminderRaw).toLowerCase() : 'false';
      if (needReminderStr === 'true' || needReminderStr === '是' || needReminderStr === '开启') {
        isReminderEnabled = true;
      }

      if (param['reminderDaysBefore'] !== undefined) {
        reminderDaysBefore = parseInt(param['reminderDaysBefore'] as string);
      } else if (param['reminder'] !== undefined) {
        const reminderStr = param['reminder'] as string;
        const match = (reminderStr || '').match(/(\d+)/);
        if (match) {
          reminderDaysBefore = parseInt(match[1]);
        }
      }

      let reminderTime = '09:00';
      if (param['reminderTime'] !== undefined) {
        reminderTime = param['reminderTime'] as string;
      }

      // ==== 3. 处理延保 (Extended Warranty) ====
      let extendedWarranties: ExtendedWarrantyItem[] = [];
      try {
        const extWarrantyParam = param['extendedWarranty'];
        if (extWarrantyParam) {
          let extList: Record<string, Object>[] = [];
          if (Array.isArray(extWarrantyParam)) {
            extList = extWarrantyParam as Record<string, Object>[];
          } else if (typeof extWarrantyParam === 'string') {
             try {
               // 尝试解析JSON字符串
               const parsed = JSON.parse(extWarrantyParam) as Record<string, Object> | Record<string, Object>[];
               if (Array.isArray(parsed)) {
                 extList = parsed as Record<string, Object>[];
               } else {
                 extList = [parsed as Record<string, Object>];
               }
             } catch {
               // 并不是JSON，可能只是单个名称
                extList = [{ 'name': extWarrantyParam }];
             }
          } else if (typeof extWarrantyParam === 'object') {
            extList = [extWarrantyParam as Record<string, Object>];
          }

          extendedWarranties = extList.map(item => {
            const wName = (item['name'] as string) || (item['title'] as string) || "未命名延保";
            const wPrice = (item['price'] as string) || "0";
            let wDate = nextBillingDate; // 默认跟随主保修
            
            const wDateStr = (item['date'] as string) || (item['expireDate'] as string) || "";
            if (wDateStr) {
               const d = new Date(wDateStr);
               if (!isNaN(d.getTime())) {
                 wDate = d.getTime();
               }
            } else {
              // 尝试从 duration 解析 (e.g., "2年", "365天")
              const durationStr = (item['duration'] as string) || "";
              if (durationStr) {
                 const numMatch = durationStr.match(/(\d+)/);
                 const num = numMatch ? parseInt(numMatch[1]) : 0;
                 if (num > 0) {
                    const d = new Date(startDate); // 基于购买日期计算
                    if (durationStr.includes('年') || durationStr.includes('year')) {
                       d.setFullYear(d.getFullYear() + num);
                    } else if (durationStr.includes('月') || durationStr.includes('month')) {
                       d.setMonth(d.getMonth() + num);
                    } else {
                       // 默认按天
                       d.setDate(d.getDate() + num);
                    }
                    wDate = d.getTime();
                 }
              }
            }
            
            let subReminderEnabled = isReminderEnabled; // 默认跟随主项
            const itemReminderRaw = item['isReminderEnabled'];
            if (itemReminderRaw !== undefined) {
                const itemReminderStr = String(itemReminderRaw).toLowerCase();
                if (itemReminderStr === 'true' || itemReminderStr === '开启') {
                    subReminderEnabled = true;
                } else if (itemReminderStr === 'false' || itemReminderStr === '未开启') {
                    // 如果主项开启，即便子项参数是 false，根据需求也可能需要强制开启？
                    // 按照用户要求 "如果开启了一起设置为true"，这里强制跟随主项
                    subReminderEnabled = isReminderEnabled || false;
                }
            }
            
            return new ExtendedWarrantyItem(
              util.generateRandomUUID(true),
              wName,
              wPrice,
              wDate,
              subReminderEnabled
            );
          });
          hilog.info(0xFEED, TAG, `[AddCore] Parsed ${extendedWarranties.length} extended warranties.`);
        }
      } catch (e) {
        hilog.warn(0xFEED, TAG, `[AddCore] Failed to parse extended warranties: ${e}`);
      }


      if ((cycle === 'Lifetime' || cycle === 'Indefinite') && recordType !== 'warranty') {
        // 如果用户没给到期日，默认到期日设为 2099-12-31 (永久)
        if (!expireDateStr || expireDateStr === '2099-12-31') {
           nextBillingDate = new Date('2099/12/31').getTime();
           // 永久有效的记录不开启提醒
           isReminderEnabled = false;
        }
        // 如果也没给生效日期，则生效日期 = 到期日期 (针对纯记录类)
        if (!purchaseDateStr) {
           startDate = nextBillingDate;
        }
      }

      let quantity = 1;
      if (param['quantity'] !== undefined) {
        quantity = parseInt(param['quantity'] as string);
        if (isNaN(quantity) || quantity <= 0) {
          quantity = 1;
        }
      }

      let category = param['category'] as string;
      const subCategory = param['subCategory'] as string;

      // 卡证特有字段提取
      const cardType = (param['cardType'] as string) || '其他';
      const cardBalanceStr = (param['cardBalance'] as string) || (param['balance'] as string) || '';
      const cardBalance = cardBalanceStr !== '' ? parseFloat(cardBalanceStr.replace(/[^0-9.]/g, '')) : undefined;

      let isAutoRenewal = recordType === 'subscription' && (cycle === 'Monthly' || cycle === 'Quarterly' || cycle === 'Yearly');
      const autoRenewalRaw = param['isAutoRenewal'];
      const autoRenewalStr = autoRenewalRaw !== undefined ? String(autoRenewalRaw).toLowerCase() : '';
      if (autoRenewalStr === 'true' || autoRenewalStr === '是' || autoRenewalStr === '开启') {
        isAutoRenewal = true;
      } else if (autoRenewalStr === 'false' || autoRenewalStr === '否' || autoRenewalStr === '未开启') {
        isAutoRenewal = false;
      }

      if (!expireDateStr && cycle !== 'Lifetime' && cycle !== 'Indefinite' && cycle !== 'Indefinite') {
        const d = new Date(startDate);
        if (cycle === 'Monthly') {
          // 修复：包月逻辑改为 +30天，避免月份天数不同导致的问题（如1月31日+1月=3月3日或报错）
          d.setDate(d.getDate() + 30);
        } else if (cycle === 'Quarterly') {
          d.setDate(d.getDate() + 90);
        } else if (cycle === 'Yearly') {
          d.setDate(d.getDate() + 365);
        }
        nextBillingDate = d.getTime();
      }

      // ==== 4. 提醒数量限制校验 (非阻塞拦截) ====
      let isReminderLimitReached = false;
      if (isReminderEnabled) {
          const currentCount = await this.getReminderCount();
          // 本次拟增加的提醒数 = 主项(1) + 延保子项数
          const incomingCount = 1 + extendedWarranties.filter(w => w.isReminderEnabled).length;
          if (currentCount + incomingCount > 30) {
              isReminderLimitReached = true;
              // 强制关闭本条记录的所有提醒
              isReminderEnabled = false;
              extendedWarranties.forEach(w => w.isReminderEnabled = false);
              hilog.warn(0xFEED, TAG, `Reminder limit reached. Disabling specific reminder for new record: ${name}`);
          }
      }

      const newSub: SubscriptionModel = {
        uuid: util.generateRandomUUID(true),
        name: name,
        price: isNaN(price) ? 0 : price,
        billingCycle: cycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
        nextBillingDate: nextBillingDate,
        startDate: startDate,
        currency: 'CNY',
        icon: iconPath,
        category: category || undefined,
        recordType: recordType,
        platform: (platformParam as 'meituan' | 'douyin' | 'dianping') || undefined,
        brand: brandParam || undefined,
        subCategory: subCategory || undefined,
        lastModified: new Date().getTime(),
        isDeleted: false,
        isAutoRenewal: isAutoRenewal,
        reminderDaysBefore: isReminderEnabled ? reminderDaysBefore : 1,
        reminderTime: reminderTime,
        couponCode: couponCode || undefined,
        merchantName: merchantName || undefined,
        usageTime: usageTime || undefined,
        quantity: recordType === 'groupBuy' ? quantity : undefined,
        usageStatus: recordType === 'groupBuy' ? 'unused' : undefined,
        purchaseChannel: purchaseChannel || undefined,
        extendedWarranties: extendedWarranties.length > 0 ? JSON.stringify(extendedWarranties) : undefined,
        cardType: recordType === 'card' ? cardType : undefined,
        cardBalance: recordType === 'card' ? cardBalance : undefined
      };

      if (!isReminderEnabled) {
        newSub.reminderDaysBefore = undefined;
        newSub.reminderTime = undefined;
      }

      await SubscriptionRepository.getInstance().insert(newSub);

      const cycleMap: Record<string, string> = {
        'Monthly': '包月',
        'Quarterly': '包季',
        'Yearly': '包年',
        'Lifetime': '永久买断',
        'Indefinite': '不定期'
      };
      const platformMap: Record<string, string> = {
        'meituan': '美团',
        'douyin': '抖音',
        'dianping': '大众点评'
      };

      const reminderEnabledStr = isReminderEnabled ? '开启' : '未开启';
      const reminderDaysStr = isReminderEnabled ? (newSub.reminderDaysBefore ?? 1).toString() : '未开启';
      const reminderTimeStr = isReminderEnabled ? (newSub.reminderTime || "09:00") : '未开启';

      let resultData: Record<string, Object> = {};
      const defVal = "无";

      // 构造 dataPackage 供 LLM/UI 展示
      const dataPackage: DataPackageItem[] = [];
      
      // 1. 添加主记录 (逻辑变更：对于保修类型，永远不显示主记录，只显示延保；如果没有延保，则 dataPackage 为空)
      if (extendedWarranties.length === 0) {
        if (recordType !== 'warranty') {
           const mainDateStr = DateUtil.formatDate(newSub.nextBillingDate);
           let mainActionStr = '';
           if (recordType === 'groupBuy') {
              mainActionStr = '到期';
           } else {
              mainActionStr = '续费';
           }
           
           const mainCycleText = recordType === 'subscription' ? this.getCycleText(newSub.billingCycle as string) : '';
           const mainPriceStr = `¥${newSub.price.toFixed(2)}`;
           
           dataPackage.push({
             title: `1. ${newSub.name}${newSub.brand ? ` (${newSub.brand})` : ''} ${mainDateStr} ${mainActionStr}${mainPriceStr ? ` ${mainPriceStr}` : ''}${mainCycleText ? ` ${mainCycleText}` : ''}`
           });
        }
      }

      // 2. 添加延保记录
      if (extendedWarranties.length > 0) {
        extendedWarranties.forEach((w, idx) => {
           const wDateStr = DateUtil.formatDate(w.date);
           const wActionStr = w.date < new Date().getTime() ? '已过保' : '在保';
           // 延保通常显示为 "额外保障" 或 "延保服务"
           dataPackage.push({
             title: `${idx + 1}. ${w.name} ${wDateStr} 到期 ${w.price && Number(w.price) > 0 ? `¥${w.price}` : ''}`
           });
        });
      }

      if (recordType === 'subscription') {
        resultData = {
          'name': newSub.name || defVal,
          'price': `${newSub.price}`,
          'billingCycle': cycleMap[newSub.billingCycle || 'Monthly'] || defVal,
          'isAutoRenewal': isAutoRenewal ? "开启" : "未开启",
          'cardCategory': recordType,
          'purchasedDate': DateUtil.formatDate(newSub.startDate || new Date().getTime()),
          'expiredDate': DateUtil.formatDate(newSub.nextBillingDate),
          'subCategory': newSub.subCategory || defVal,
          'isReminderEnabled': reminderEnabledStr,
          'reminderDaysBefore': reminderDaysStr,
          'reminderTime': reminderTimeStr,
          'resultText': `已为您成功记录 ${newSub.name} 订阅，${cycleMap[newSub.billingCycle || 'Monthly']}费用为 ${newSub.price} 元。${isReminderLimitReached ? '由于您的提醒数量已达上限(30个)，本次添加未开启提醒通知。' : ''}`,
          'dataPackage': dataPackage,
          'showPackage': "true"
        };
      } else if (recordType === 'warranty') {
        const totalItems = 1 + extendedWarranties.length;
        resultData = {
          'name': newSub.name || defVal,
          'price': `${newSub.price}`,
          'brand': newSub.brand || defVal,
          'purchaseChannel': newSub.purchaseChannel || defVal,
          'cardCategory': recordType,
          'purchasedDate': DateUtil.formatDate(newSub.startDate || new Date().getTime()),
          'expiredDate': DateUtil.formatDate(newSub.nextBillingDate),
          'category': newSub.category || defVal,
          'subCategory': newSub.category || defVal,
          'isReminderEnabled': reminderEnabledStr,
          'reminderDaysBefore': reminderDaysStr,
          'reminderTime': reminderTimeStr,
          'resultText': `已为您成功记录 ${newSub.brand || ''}${newSub.name} 的保修信息${extendedWarranties.length > 0 ? `及 ${extendedWarranties.length} 项延保服务` : ''}。${isReminderLimitReached ? '由于您的提醒数量已达上限(30个)，本次添加未开启提醒通知。' : ''}`,
          'dataPackage': dataPackage,
          'showPackage': "true"
        };
      } else if (recordType === 'card') {
        resultData = {
          'name': newSub.name || defVal,
          'cardBalance': newSub.cardBalance !== undefined ? `${newSub.cardBalance}` : "无",
          'cardType': newSub.cardType || defVal,
          'cardCategory': recordType,
          'purchasedDate': DateUtil.formatDate(newSub.startDate || new Date().getTime()),
          'expiredDate': DateUtil.formatDate(newSub.nextBillingDate),
          'isReminderEnabled': reminderEnabledStr,
          'reminderDaysBefore': reminderDaysStr,
          'reminderTime': reminderTimeStr,
          'resultText': `已为您成功记录 ${newSub.name} ${newSub.cardType}，有效期至 ${DateUtil.formatDate(newSub.nextBillingDate)}。${isReminderLimitReached ? '由于您的提醒数量已达上限(30个)，本次添加未开启提醒通知。' : ''}`,
          'dataPackage': dataPackage,
          'showPackage': "true"
        };
      } else {
        resultData = {
          'name': newSub.name || defVal,
          'price': `${newSub.price}`,
          'merchantName': newSub.merchantName || defVal,
          'platform': newSub.platform ? (platformMap[newSub.platform] || newSub.platform) : defVal,
          'usageTime': newSub.usageTime || defVal,
          'cardCategory': recordType,
          'purchasedDate': DateUtil.formatDate(newSub.startDate || new Date().getTime()),
          'expiredDate': DateUtil.formatDate(newSub.nextBillingDate),
          'isReminderEnabled': reminderEnabledStr,
          'reminderDaysBefore': reminderDaysStr,
          'reminderTime': reminderTimeStr,
          'resultText': `已为您成功记录 ${newSub.merchantName || newSub.name} 的团购券，有效期至 ${DateUtil.formatDate(newSub.nextBillingDate)}。${isReminderLimitReached ? '由于您的提醒数量已达上限(30个)，本次添加未开启提醒通知。' : ''}`,
          'dataPackage': dataPackage,
          'showPackage': "true"
        };
      }

      hilog.info(0xFEED, TAG, `[RETURN] AddCore Result: ${JSON.stringify(resultData)}`);
      const finalResult: insightIntent.ExecuteResult = { code: 0, result: resultData };
      return finalResult;

    } catch (e) {
      hilog.error(0x0001, TAG, `AddCore failed: ${e}`);
      const errRes: Record<string, Object> = {
        'resultText': "添加订阅失败。",
        'errorMessage': `${e}`
      };
      const finalErrResult: insightIntent.ExecuteResult = {
        code: 0,
        result: errRes
      };
      return finalErrResult;
    }
  }

  private getCycleText(cycle: string): string {
    const cycleMap: Record<string, string> = {
      'Monthly': '月',
      'Quarterly': '季',
      'Yearly': '年',
      'Lifetime': '永久',
      'Indefinite': '次'
    };
    return cycleMap[cycle] || '';
  }

  private async getReminderCount(): Promise<number> {
    try {
      const allSubs = await SubscriptionRepository.getInstance().queryAll();
      const activeSubs = allSubs.filter(s => !s.isDeleted);
      let count = activeSubs.filter(s => s.reminderDaysBefore !== undefined).length;
      activeSubs.forEach(s => {
        if (s.extendedWarranties) {
          try {
            const items: ExtendedWarrantyItem[] = JSON.parse(s.extendedWarranties);
            count += items.filter(i => i.isReminderEnabled).length;
          } catch (e) {}
        }
      });
      return count;
    } catch (e) {
      return 0;
    }
  }
}
