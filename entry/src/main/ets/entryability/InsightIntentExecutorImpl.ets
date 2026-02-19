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
    
    switch (intentName) {
      case Constants.INTENT_QUERY_RECORD:
        try {
          // Prevent potential crash in LocalNotificationManager due to missing preferences
          await PreferenceUtil.getInstance().loadPreference((this.context as Object) as common.Context);
          
          // await SubscriptionRepository.getInstance().init((this.context as Object) as common.Context);
          // const allSubs = await SubscriptionRepository.getInstance().queryAll();
          
          // --- MOCK DATA FOR TESTING (Force return test data) ---
          const nowTime = new Date().getTime();
          // Ensure dates fall into expected ranges:
          // This Month: +3 days
          // Next Month: +20 days (assuming we are not at end of month, or calculating carefully)
          // To be safe for "Next Month", let's use a fixed date relative to now that is definitely next month.
          const nextMonthDate = new Date();
          nextMonthDate.setMonth(nextMonthDate.getMonth() + 1);
          nextMonthDate.setDate(15); // Middle of next month

          const allSubs: SubscriptionModel[] = [
            {
              id: 1001, uuid: 'mock_netflix', name: 'Netflix Premium', price: 15.99, currency: 'USD', billingCycle: 'Monthly', 
              nextBillingDate: nowTime + 3 * 24 * 3600 * 1000, // +3 days (This Month likely)
              category: 'Entertainment', isDeleted: false, isAutoRenewal: true, 
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'Credit Card', icon: ''
            },
            {
              id: 1002, uuid: 'mock_spotify', name: 'Spotify Duo', price: 12.99, currency: 'USD', billingCycle: 'Monthly', 
              nextBillingDate: nextMonthDate.getTime(), // Definitely Next Month
              category: 'Music', isDeleted: false, isAutoRenewal: true,
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'PayPal', icon: '' 
            },
            {
              id: 1003, uuid: 'mock_kfc', name: '肯德基全家桶券', price: 59.9, currency: 'CNY', billingCycle: 'Indefinite',
              nextBillingDate: nowTime + 2 * 24 * 3600 * 1000, // +2 days (This Month/Urgent)
              usageStatus: 'unused', recordType: 'groupBuy', platform: 'meituan', merchantName: '肯德基',
              category: 'Food', isDeleted: false, startDate: nowTime, lastModified: nowTime,
              subCategory: '', isAutoRenewal: false, paymentMethod: 'WeChat', icon: ''
            },
             {
              id: 9999, uuid: 'mock_today', name: 'Today Test (Catch-All)', price: 0.01, currency: 'CNY', billingCycle: 'Monthly',
              nextBillingDate: nowTime + 1000, // +1 second
              category: 'Other', isDeleted: false, isAutoRenewal: true,
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'None', icon: ''
            }
          ];
          hilog.info(0xFEED, TAG, `[MOCK] Loaded ${allSubs.length} items. Params: ${JSON.stringify(intentParam)}`);
          
          // Support both camelCase (config) and snake_case (common LLM output)
          const queryType = (intentParam['queryType'] as string) || (intentParam['query_type'] as string) || 'expiration';
          const timeRange = (intentParam['timeRange'] as string) || (intentParam['time_range'] as string) || 'next_30_days'; // Default
          
          let resultData: Record<string, Object> = {};

          // --- 1. Determine Logic based on Query Type ---
          if (queryType === 'expiration') {
            // --- Expiration Logic ---
            const now = new Date();
            let startDate = now.getTime(); 
            let endDate = now.getTime() + 30 * 24 * 60 * 60 * 1000; // Default 30 days
            let dateDescription = "最近30天";

            if (timeRange === 'this_month') {
              const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
              startDate = now.getTime();
              endDate = endOfMonth.getTime();
              dateDescription = "本月剩余时间内";
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
               dateDescription = "今年剩余时间内";
            }

            const expiring = allSubs.filter(s => s.nextBillingDate >= startDate && s.nextBillingDate <= endDate);
            
            // Generate Plain Text List
            const recordsListText = expiring.length > 0 
                ? expiring.map((s, index) => `${index + 1}. ${s.name} (${DateUtil.formatShortDate(s.nextBillingDate)})`).join("\n") 
                : "无";

            const summary = expiring.length > 0
                ? `为您找到 ${expiring.length} 条${dateDescription}到期的记录：${expiring.map(s => `${s.name}(${DateUtil.formatShortDate(s.nextBillingDate)})`).join("，")}。`
                : `在${dateDescription}没有找到即将到期的订阅记录。`;

            resultData = {
              'resultText': summary,
              'count': expiring.length,
              'totalAmount': expiring.reduce((sum, s) => sum + s.price, 0).toFixed(2),
              'records': recordsListText
            };

          } else {
            // --- Expense / General Query Logic ---
            const timeRange = (intentParam['timeRange'] as string) || 'month';
            let summaryText = "";
            let total = 0;
            let recordsListText = "";

            if (timeRange === 'year' || timeRange === 'this_year') {
               // Yearly Estimation
               total = allSubs.reduce((sum, s) => sum + (s.price * 12), 0);
               const subNames = allSubs.map(s => s.name).join("，");
               summaryText = `您当前共有 ${allSubs.length} 项有效订阅：${subNames}。年度预估总支出约为 ${total.toFixed(2)} 元。`;
               recordsListText = allSubs.map((s, index) => `${index + 1}. ${s.name} - 约${(s.price * 12).toFixed(2)}/年`).join("\n");
            } else {
               // Monthly Default
               total = allSubs.reduce((sum, s) => sum + s.price, 0);
               const subNames = allSubs.map(s => s.name).join("，");
               summaryText = `您当前共有 ${allSubs.length} 项有效订阅：${subNames}。月度预估总支出为 ${total.toFixed(2)} 元。`;
               recordsListText = allSubs.map((s, index) => `${index + 1}. ${s.name} - ${s.price}/${s.billingCycle || '月'}`).join("\n");
            }

            resultData = {
              'resultText': summaryText,
              'count': allSubs.length,
              'totalAmount': total.toFixed(2),
              'records': recordsListText
            };
          }

          hilog.info(0xFEED, TAG, `[RETURN] InsightIntent Result: ${JSON.stringify(resultData)}`);

          return {
            code: 0,
            result: resultData
          };
        } catch (e) {
          hilog.error(0x0001, TAG, `Background query failed: ${e}`);
          const errorMsg = "抱歉，查询本地数据时遇到一点问题，请稍后重试。";
          return {
            code: 0, // 即使查询失败也返回0，由 resultText 告知
            result: {
              'resultText': errorMsg,
              'count': 0,
              'totalAmount': '0.00'
            }
          };
        }
      case Constants.INTENT_GET_ALL_RECORDS:
        try {
           hilog.info(0xFEED, TAG, `[GetAllRecords] Executing full dump intent.`);
           
           // Ensure environment is ready
           await PreferenceUtil.getInstance().loadPreference((this.context as Object) as common.Context);
           
           // --- MOCK DATA ---
           const nowTime = new Date().getTime();
           const nextMonthDate = new Date();
           nextMonthDate.setMonth(nextMonthDate.getMonth() + 1);
           nextMonthDate.setDate(15); 

           const allSubs: SubscriptionModel[] = [
            {
              id: 1001, uuid: 'mock_netflix', name: 'Netflix Premium', price: 15.99, currency: 'USD', billingCycle: 'Monthly', 
              nextBillingDate: nowTime + 3 * 24 * 3600 * 1000, 
              category: 'Entertainment', isDeleted: false, isAutoRenewal: true, 
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'Credit Card', icon: ''
            },
            {
              id: 1002, uuid: 'mock_spotify', name: 'Spotify Duo', price: 12.99, currency: 'USD', billingCycle: 'Monthly', 
              nextBillingDate: nextMonthDate.getTime(),
              category: 'Music', isDeleted: false, isAutoRenewal: true,
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'PayPal', icon: '' 
            },
            {
              id: 1003, uuid: 'mock_kfc', name: '肯德基全家桶券', price: 59.9, currency: 'CNY', billingCycle: 'Indefinite',
              nextBillingDate: nowTime + 2 * 24 * 3600 * 1000, 
              usageStatus: 'unused', recordType: 'groupBuy', platform: 'meituan', merchantName: '肯德基',
              category: 'Food', isDeleted: false, startDate: nowTime, lastModified: nowTime,
              subCategory: '', isAutoRenewal: false, paymentMethod: 'WeChat', icon: ''
            },
            {
              id: 9999, uuid: 'mock_today', name: 'Today Test (Catch-All)', price: 0.01, currency: 'CNY', billingCycle: 'Monthly',
              nextBillingDate: nowTime + 1000, 
              category: 'Other', isDeleted: false, isAutoRenewal: true,
              recordType: 'subscription', startDate: nowTime, lastModified: nowTime,
              subCategory: '', paymentMethod: 'None', icon: ''
            }
          ];

          const total = allSubs.reduce((sum, s) => sum + s.price, 0);
          const recordsListText = allSubs.map((s, index) => `${index + 1}. ${s.name} (${s.price})`).join("; ");
          
          const summary = `查询成功。共找到 ${allSubs.length} 条记录：${recordsListText}。`;

          const resultData: Record<string, Object> = {
              'resultText': summary,
              'count': allSubs.length,
              'totalAmount': total.toFixed(2),
              'records': recordsListText,
              'errorMessage': "" // Explicitly add this to potentially match agent expectation
          };

          hilog.info(0xFEED, TAG, `[RETURN] GetAllRecords Result: ${JSON.stringify(resultData)}`);

          return {
            code: 0,
            result: resultData
          };

        } catch (e) {
           hilog.error(0x0001, TAG, `GetAllRecords failed: ${e}`);
           return {
             code: 0, 
             result: {
               'resultText': "查询全部数据时出错。",
               'errorMessage': `${e}`
             }
           };
        }

      default:
        return {
          code: -1,
          result: {
            message: 'Unknown background intent'
          }
        };
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
          if (['Monthly', 'Quarterly', 'Yearly', 'Lifetime', 'Indefinite'].includes(cycle)) {
             newRecord.billingCycle = cycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
          }
        }
        // Calculate next billing date based on start date and cycle? 
        // For simplicity, let the UI handle the "next billing" calculation initial logic, 
        // or just set nextBillingDate to purchaseDate for now (meaning "starts now").
      } else if (recordType === 'groupBuy') {
        newRecord.billingCycle = 'Indefinite'; // Internal representation if needed, though model uses recordType
        if (platform) {
          // Map platform to enum if possible, or store as is if model supports arbitrary strings (model defines enum)
          if (['meituan', 'douyin', 'dianping'].includes(platform)) {
             newRecord.platform = platform as 'meituan' | 'douyin' | 'dianping';
          }
        }
        if (expireDateStr) {
           const expireDate = new Date(expireDateStr);
           if (!isNaN(expireDate.getTime())) {
             newRecord.nextBillingDate = expireDate.getTime(); // Group buy expiration is stored in nextBillingDate
           }
        }
      } else if (recordType === 'warranty') {
        newRecord.billingCycle = 'Indefinite';
        if (brand) newRecord.brand = brand;
        if (purchaseChannel) newRecord.purchaseChannel = purchaseChannel; // Assuming this field exists in model
        
        if (expireDateStr) {
           const expireDate = new Date(expireDateStr);
           if (!isNaN(expireDate.getTime())) {
             newRecord.nextBillingDate = expireDate.getTime(); // Warranty expiration is stored in nextBillingDate
           }
        }
      }

      // 4. 将数据传递给 UI
      // 使用 AppStorage 传递临时数据
      AppStorage.setOrCreate('targetSubscription', newRecord);
      AppStorage.setOrCreate('targetAction', 'DirectAddSubscription'); // Custom action to trigger routing in Index.ets

      // 5. 加载页面
      pageLoader.loadContent('pages/Index');

      return {
        code: 0,
        result: {
          message: 'Redirecting to add page'
        }
      };
    } catch (e) {
      hilog.error(0x0000, TAG, `handleAddRecord failed: ${e}`);
      return {
        code: -1,
        result: {
          message: 'Failed to process add record intent'
        }
      };
    }
  }

  private async handleQueryRecord(param: Record<string, Object>, pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
     hilog.info(0xFEED, TAG, `handleQueryRecord called with params: ${JSON.stringify(param)}`);
     try {
       const queryType = param['queryType'] as string || 'expense';
       
       if (queryType === 'expiration') {
          // Calendar View
          AppStorage.setOrCreate('targetAction', 'ViewCalendar');
       } else {
          // Stats View (expense)
          AppStorage.setOrCreate('targetAction', 'ViewStats');
       }

       pageLoader.loadContent('pages/Index');

       return {
         code: 0,
         result: {
           message: 'Redirecting to query page'
         }
       };

     } catch (e) {
       hilog.error(0x0000, TAG, `handleQueryRecord failed: ${e}`);
       return {
         code: -1,
         result: {
           message: 'Failed to process query intent'
         }
       };
     }
  }
}
