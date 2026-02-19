import { common, insightIntent, InsightIntentExecutor, UIExtensionContentSession } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { DateUtil } from '../utils/DateUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';

const TAG = 'InsightIntentExecutorImpl';

class Constants {
  // add_record 前台执行
  public static INTENT_ADD_RECORD = "AddRecord";
  // query_record 前台执行
  public static INTENT_QUERY_RECORD = "QueryRecord";
  // get_all_records 后台执行
  public static INTENT_GET_ALL_RECORDS = "GetAllRecords";
}

export default class InsightIntentExecutorImpl extends InsightIntentExecutor {
  constructor() {
    super();
    hilog.info(0xFEED, TAG, 'InsightIntentExecutorImpl instance created');
  }

  /**
   * override 执行前台UIAbility意图
   *
   * @param name 意图名称
   * @param param 意图参数
   * @param pageLoader 窗口
   * @returns 意图调用结果
   */
  onExecuteInUIAbilityForegroundMode(name: string, param: Record<string, Object>, pageLoader: window.WindowStage):
    Promise<insightIntent.ExecuteResult> {
    
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityForegroundMode called: name=${name}, param=${JSON.stringify(param)}`);

    switch (name) {
      case Constants.INTENT_ADD_RECORD:
        return this.handleAddRecord(param, pageLoader);
      case Constants.INTENT_QUERY_RECORD:
        return this.handleQueryRecord(param, pageLoader);
      default:
        hilog.warn(0xFEED, TAG, `Unknown intent name: ${name}`);
        pageLoader.loadContent('pages/Index');
        break;
    }
    
    return Promise.resolve({
      code: -1,
      result: {
        message: 'Unsupported intent execution mode or unknown intent'
      }
    } as insightIntent.ExecuteResult);
  }

  /**
   * override 执行后台UIAbility意图
   *
   * @param intentName 意图名称
   * @param intentParam 意图参数
   * @returns 意图调用结果
   */
  async onExecuteInUIAbilityBackgroundMode(intentName: string, intentParam: Record<string, Object>):
    Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `onExecuteInUIAbilityBackgroundMode called: name=${intentName}, param=${JSON.stringify(intentParam)}`);
    
    // Ensure environment and database are ready for all background intents
    try {
      await PreferenceUtil.getInstance().loadPreference((this.context as Object) as common.Context);
      await SubscriptionRepository.getInstance().init((this.context as Object) as common.Context);
    } catch (e) {
      hilog.error(0x0001, TAG, `Initialization failed: ${e}`);
    }

    switch (intentName) {
      case Constants.INTENT_QUERY_RECORD:
        try {
          const allSubs = await SubscriptionRepository.getInstance().queryAll();
          
          // Support both camelCase (config) and snake_case (common LLM output)
          const queryType = (intentParam['queryType'] as string) || (intentParam['query_type'] as string) || 'expiration';
          const timeRange = (intentParam['timeRange'] as string) || (intentParam['time_range'] as string) || 'next_30_days'; // Default
          
          // --- 1. Determine Date Range ---
          const now = new Date();
          let startDate = 0;
          let endDate = 0;
          let dateDescription = "";
          let resultData: Record<string, Object> = {};

          if (timeRange === 'this_month') {
            const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
            startDate = now.getTime();
            endDate = endOfMonth.getTime();
            dateDescription = "本月";
          } else if (timeRange === 'next_month') {
            const startOfNextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0, 0);
            const endOfNextMonth = new Date(now.getFullYear(), now.getMonth() + 2, 0, 23, 59, 59, 999);
            startDate = startOfNextMonth.getTime();
            endDate = endOfNextMonth.getTime();
            dateDescription = "下个月";
          } else if (timeRange === 'this_year' || timeRange === 'year') {
            const endOfYear = new Date(now.getFullYear(), 11, 31, 23, 59, 59, 999);
            startDate = now.getTime();
            endDate = endOfYear.getTime();
            dateDescription = "年度";
          } else {
            // Default 30 days
            startDate = now.getTime();
            endDate = now.getTime() + 30 * 24 * 60 * 60 * 1000;
            dateDescription = "最近30天";
          }

          if (queryType === 'expiration') {
            // --- Expiration Logic ---
            const expiring = allSubs.filter(s => s.nextBillingDate >= startDate && s.nextBillingDate <= endDate);
            
            const recordsListText = expiring.length > 0 
                ? expiring.map((s, index) => `${index + 1}. ${s.name} (${DateUtil.formatShortDate(s.nextBillingDate)})`).join("; ") 
                : "无";

            const summary = expiring.length > 0
                ? `为您找到 ${expiring.length} 条${dateDescription}到期的记录：${expiring.map(s => `${s.name}(${DateUtil.formatShortDate(s.nextBillingDate)})`).join("，")}。`
                : `在${dateDescription}没有找到即将到期的记录。`;

            resultData = {
              'resultText': summary,
              'count': expiring.length,
              'totalAmount': expiring.reduce((sum, s) => sum + s.price, 0).toFixed(2),
              'records': recordsListText,
              'errorMessage': ""
            };

          } else {
            // --- Expense Logic ---
            // 1. First attempt: Find actual renewals inside the window (e.g., "upcoming payments")
            const activeInPeriod = allSubs.filter(s => !s.isDeleted && s.nextBillingDate >= startDate && s.nextBillingDate <= endDate);
            
            if (activeInPeriod.length > 0) {
              const total = activeInPeriod.reduce((sum, s) => sum + s.price, 0);
              const summaryText = `您在${dateDescription}共有 ${activeInPeriod.length} 项预计续费支出，合计约 ${total.toFixed(2)} 元。项目包括：${activeInPeriod.map(s => s.name).join('、')}。`;
              const recordsListText = activeInPeriod.map((s, index) => `${index + 1}. ${s.name} (${s.price}元)`).join("; ");

              resultData = {
                'resultText': summaryText,
                'count': activeInPeriod.length,
                'totalAmount': total.toFixed(2),
                'records': recordsListText,
                'errorMessage': ""
              };
            } else {
              // 2. Fallback: Calculation average monthly budget for all active records
              const activeSubs = allSubs.filter(s => !s.isDeleted);
              const monthlyEstimatedTotal = activeSubs.reduce((sum, s) => {
                let monthly = 0;
                if (s.billingCycle === 'Monthly') monthly = s.price;
                else if (s.billingCycle === 'Quarterly') monthly = s.price / 3;
                else if (s.billingCycle === 'Yearly') monthly = s.price / 12;
                else if (s.billingCycle === 'Lifetime' || s.billingCycle === 'Indefinite') monthly = 0; // Don't count one-time in monthly average
                return sum + monthly;
              }, 0);

              const summaryText = activeSubs.length > 0 
                ? `虽然在${dateDescription}没有找到即将到期的续费，但您当前的订阅月度预估总支出约为 ${monthlyEstimatedTotal.toFixed(2)} 元。`
                : `您目前没有任何活跃的订阅或消费记录。`;
              
              const recordsListText = activeSubs.length > 0
                ? activeSubs.map((s, index) => `${index + 1}. ${s.name} (${s.price}/${s.billingCycle})`).join("; ")
                : "无";

              resultData = {
                'resultText': summaryText,
                'count': activeSubs.length,
                'totalAmount': monthlyEstimatedTotal.toFixed(2),
                'records': recordsListText,
                'errorMessage': ""
              };
            }
          }

          hilog.info(0xFEED, TAG, `[RETURN] QueryRecord Result: ${JSON.stringify(resultData)}`);

          const executeResult: insightIntent.ExecuteResult = {
            code: 0,
            result: resultData
          };
          return executeResult;
        } catch (e) {
          hilog.error(0x0001, TAG, `Background query failed: ${e}`);
          const errorResult: insightIntent.ExecuteResult = {
            code: 0,
            result: {
              'resultText': "查询本地数据时出错。",
              'errorMessage': `${e}`
            }
          };
          return errorResult;
        }
      case Constants.INTENT_GET_ALL_RECORDS:
        try {
          hilog.info(0xFEED, TAG, `[GetAllRecords] Executing full dump intent.`);
          const allSubs = await SubscriptionRepository.getInstance().queryAll();
          const activeSubs = allSubs.filter(s => !s.isDeleted);

          const totalCount = activeSubs.length;
          const totalAmount = activeSubs.reduce((sum, s) => sum + s.price, 0);
          const recordsListText = activeSubs.map((s, index) =>
            `${index + 1}. ${s.name} - ${s.price}${s.currency === 'USD' ? '$' : '元'} (${DateUtil.formatShortDate(s.nextBillingDate)})`
          ).join("; ");

          const summary = totalCount > 0
            ? `为您找到了 ${totalCount} 条记录：${recordsListText}`
            : "您目前没有任何订阅或消费记录。";

          const resultData: Record<string, Object> = {
            'resultText': summary,
            'count': totalCount,
            'totalAmount': totalAmount.toFixed(2),
            'records': recordsListText,
            'errorMessage': ""
          };

          hilog.info(0xFEED, TAG, `[RETURN] GetAllRecords Result: ${JSON.stringify(resultData)}`);

          const executeResult: insightIntent.ExecuteResult = {
            code: 0,
            result: resultData
          };
          return executeResult;

        } catch (e) {
          hilog.error(0x0001, TAG, `GetAllRecords failed: ${e}`);
          const errorResult: insightIntent.ExecuteResult = {
            code: 0,
            result: {
              'resultText': "查询全部数据时出错。",
              'errorMessage': `${e}`
            }
          };
          return errorResult;
        }

      default:
        hilog.warn(0xFEED, TAG, `Unknown background intent: ${intentName}`);
        const unknownResult: insightIntent.ExecuteResult = {
          code: -1,
          result: {
            message: 'Unknown background intent',
            errorMessage: 'Intent not supported in background mode'
          }
        };
        return unknownResult;
    }
  }

  private async handleAddRecord(param: Record<string, Object>, pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `handleAddRecord called with params: ${JSON.stringify(param)}`);
    try {
      // 1. 解析参数
      const recordType = param['recordType'] as string || 'subscription';
      const name = param['name'] as string || '';
      const priceStr = param['price'] as string || '0';
      const purchaseDateStr = param['purchaseDate'] as string;
      const expireDateStr = param['expireDate'] as string; // For groupBuy/warranty
      const cycle = param['cycle'] as string; // For subscription billing cycle
      const platform = param['platform'] as string; // For groupBuy platform
      const brand = param['brand'] as string; // For warranty brand
      const purchaseChannel = param['purchaseChannel'] as string; // For warranty channel (from updated config)

      // 2. 构建 SubscriptionModel
      const newRecord: SubscriptionModel = {
        id: new Date().getTime(), // Temporary ID
        uuid: '', // New record
        name: name,
        price: parseFloat(priceStr),
        currency: 'CNY', // Fixed to CNY as per config
        recordType: recordType as 'subscription' | 'groupBuy' | 'warranty',
        billingCycle: 'Monthly', // Default
        nextBillingDate: new Date().getTime(), // Default to now, will override
        startDate: new Date().getTime(), // Default to now, will override
        icon: '', // Default icon logic will handle this in UI
        category: '其他',
        lastModified: new Date().getTime(),
        isDeleted: false,
        isAutoRenewal: true,
        paymentMethod: '微信支付', // Default
        subCategory: '',
      };

      // 3. 处理特定字段
      if (purchaseDateStr) {
        const purchaseDate = new Date(purchaseDateStr);
        if (!isNaN(purchaseDate.getTime())) {
          newRecord.startDate = purchaseDate.getTime();
          // For subscription, next billing date starts from purchase date unless cycle logic applies
          newRecord.nextBillingDate = purchaseDate.getTime();
        }
      }

      if (recordType === 'subscription') {
        if (cycle) {
          // Map cycle string from agent (Monthly, Quarterly, Yearly) to SubscriptionModel
          const validCycles = ['Monthly', 'Quarterly', 'Yearly', 'Lifetime', 'Indefinite'];
          if (validCycles.includes(cycle)) {
            newRecord.billingCycle = cycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
          }
        }
      } else if (recordType === 'groupBuy') {
        newRecord.billingCycle = 'Indefinite';
        if (platform) {
          const validPlatforms = ['meituan', 'douyin', 'dianping'];
          if (validPlatforms.includes(platform)) {
            newRecord.platform = platform as 'meituan' | 'douyin' | 'dianping';
          }
        }
        if (expireDateStr) {
          const expireDate = new Date(expireDateStr);
          if (!isNaN(expireDate.getTime())) {
            newRecord.nextBillingDate = expireDate.getTime();
          }
        }
      } else if (recordType === 'warranty') {
        newRecord.billingCycle = 'Indefinite';
        if (brand) {
          newRecord.brand = brand;
        }
        if (purchaseChannel) {
          newRecord.merchantName = purchaseChannel; // Map channel to merchant name as a fallback or if supported
        }

        if (expireDateStr) {
          const expireDate = new Date(expireDateStr);
          if (!isNaN(expireDate.getTime())) {
            newRecord.nextBillingDate = expireDate.getTime();
          }
        }
      }

      // 4. 将数据传递给 UI
      AppStorage.setOrCreate('targetSubscription', newRecord);
      AppStorage.setOrCreate('targetAction', 'DirectAddSubscription');

      // 5. 加载页面
      pageLoader.loadContent('pages/Index');

      const successResult: insightIntent.ExecuteResult = {
        code: 0,
        result: {
          'message': 'Redirecting to add page'
        }
      };
      return successResult;
    } catch (e) {
      hilog.error(0x0000, TAG, `handleAddRecord failed: ${e}`);
      const errorResult: insightIntent.ExecuteResult = {
        code: -1,
        result: {
          'message': 'Failed to process add record intent'
        }
      };
      return errorResult;
    }
  }

  private async handleQueryRecord(param: Record<string, Object>, pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    hilog.info(0xFEED, TAG, `handleQueryRecord called with params: ${JSON.stringify(param)}`);
    try {
      const queryType = param['queryType'] as string || 'expense';

      if (queryType === 'expiration') {
        AppStorage.setOrCreate('targetAction', 'ViewCalendar');
      } else {
        AppStorage.setOrCreate('targetAction', 'ViewStats');
      }

      pageLoader.loadContent('pages/Index');

      const successResult: insightIntent.ExecuteResult = {
        code: 0,
        result: {
          'message': 'Redirecting to query page'
        }
      };
      return successResult;

    } catch (e) {
      hilog.error(0x0000, TAG, `handleQueryRecord failed: ${e}`);
      const errorResult: insightIntent.ExecuteResult = {
        code: -1,
        result: {
          'message': 'Failed to process query intent'
        }
      };
      return errorResult;
    }
  }
}

