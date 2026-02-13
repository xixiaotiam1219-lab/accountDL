import relationalStore from '@ohos.data.relationalStore';
import { SubscriptionModel } from './SubscriptionModel';
import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GlobalBus, EVENT_SYNC_COMPLETED, EVENT_THEME_CHANGED, EVENT_NOTIFY_PERMISSION_GRANTED } from '../utils/GlobalBus';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DateUtil } from '../utils/DateUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { LocalNotificationManager } from '../manager/LocalNotificationManager';
import { util } from '@kit.ArkTS';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'SubscriptionTracker.db',
  securityLevel: relationalStore.SecurityLevel.S1
};

const TABLE_NAME = 'subscription';

const SQL_CREATE_TABLE = `
  CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    currency TEXT NOT NULL,
    billingCycle TEXT NOT NULL,
    nextBillingDate INTEGER NOT NULL,
    startDate INTEGER,
    icon TEXT,
    category TEXT,
    lastModified INTEGER NOT NULL,
    isDeleted INTEGER DEFAULT 0,
    reminderDaysBefore INTEGER DEFAULT 1,
    reminderTime TEXT DEFAULT '09:00',
    subCategory TEXT,
    isAutoRenewal INTEGER DEFAULT 1,
    paymentMethod TEXT DEFAULT '其他支付方式'
  )
`;

interface ColumnInfo {
  name: string;
  type: string;
}

interface SyncSettings {
  defaultCurrency: string;
  themeMode: number;
  pushEnabled: boolean;
}

interface PushBody {
  unionId: string;
  subscriptions: SubscriptionModel[];
  settings: SyncSettings;
}

interface PullResponse {
  subscriptions: SubscriptionModel[];
}

interface CloudSyncResponse {
  subscriptions: SubscriptionModel[];
  settings: SyncSettings;
}

/**
 * 最小化卡片交互数据接口，用于解决 ArkTS 严格类型检查问题
 */
export interface MinimalCardItem {
  id: number | string;
  recordType: 'subscription' | 'groupBuy';
  usageStatus: 'unused' | 'used' | 'expired';
  name: string;
}

class SnapshotItem {
  title: string = '';
  content: string = '';
  icon: string = '';
  isExpiring: boolean = false;
  originalItem: string = '';
}

class SnapshotData {
  widgetData: SnapshotItem[] = [];
  isLoggedIn: boolean = false;
  totalCount: number = 0;
  activeThemeId: string = 'default';
  timestamp: number = 0;
}

export class SubscriptionRepository {
  private static instance: SubscriptionRepository;
  private rdbStore: relationalStore.RdbStore | undefined = undefined;
  private initPromise: Promise<void> | null = null;
  private syncTimer: number = -1; // For debounce
  private context: common.Context | undefined = undefined;

  private constructor() {}

  public static getInstance(): SubscriptionRepository {
    if (!SubscriptionRepository.instance) {
      SubscriptionRepository.instance = new SubscriptionRepository();
    }
    return SubscriptionRepository.instance;
  }

  public init(context: common.Context): Promise<void> {
    if (this.initPromise) {
       return this.initPromise;
    }

    this.initPromise = new Promise((resolve, reject) => {
      this.context = context;
      relationalStore.getRdbStore(context, STORE_CONFIG, async (err, store) => {
        if (err) {
          console.error(`Failed to get RdbStore. Code:${err.code}, message:${err.message}`);
          reject(err);
          return;
        }
        this.rdbStore = store;
        try {
            await this.rdbStore.executeSql(SQL_CREATE_TABLE); 
            // 数据库迁移逻辑：为旧版本数据库添加新字段
            await this.migrate(this.rdbStore);
            console.info('RdbStore initialized');

            // 监听主题修改事件，同步更新快照
            GlobalBus.subscribe(EVENT_THEME_CHANGED, () => {
                // hilog.info( 'SubscriptionRepository', 'Theme changed event received, updating widget snapshot');
                this.updateWidgetSnapshotSync('theme');
            });

            // [核心增强] 监听通知权限授予事件，触发全量提醒重同步
            // 解决换机/迁移场景下权限开启后的提醒恢复问题
            GlobalBus.subscribe(EVENT_NOTIFY_PERMISSION_GRANTED, async () => {
                hilog.info(0x0000, 'SubscriptionRepository', 'Notification permission granted event received, resyncing all reminders...');
                const subs = await this.queryAllInternal(true); // 包含已删除的（Manager 会过滤）或仅查询有效的
                const activeSubs = subs.filter(s => !s.isDeleted);
                await LocalNotificationManager.getInstance().resyncReminders(activeSubs);
            });

            resolve();
        } catch (e) {
            reject(e);
        }
      })
    })
    return this.initPromise;
  }

  private async migrate(db: relationalStore.RdbStore): Promise<void> {
    const columns: ColumnInfo[] = [
      // 只有在 SQL_CREATE_TABLE 之外新增的字段才需要在这里迁移
      // 团购券相关字段 (后期新增)
      { name: 'recordType', type: 'TEXT DEFAULT "subscription"' },
      { name: 'platform', type: 'TEXT' },
      { name: 'couponCode', type: 'TEXT' },
      { name: 'usageStatus', type: 'TEXT DEFAULT "unused"' },
      { name: 'merchantName', type: 'TEXT' },
      { name: 'quantity', type: 'INTEGER DEFAULT 1' },
      { name: 'couponImage', type: 'TEXT' },
      { name: 'usageTime', type: 'TEXT' },
      { name: 'realUsageTime', type: 'INTEGER' }
    ];
    
    try {
        const resultSet = await db.querySql(`PRAGMA table_info(${TABLE_NAME})`);
        const existingColumns: string[] = [];
        while (resultSet.goToNextRow()) {
            existingColumns.push(resultSet.getString(resultSet.getColumnIndex('name')));
        }
        resultSet.close();

        for (const col of columns) {
            if (!existingColumns.includes(col.name)) {
                try {
                    await db.executeSql(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${col.name} ${col.type}`);
                    console.info(`Added column ${col.name} to ${TABLE_NAME}`);
                } catch (err) {
                    // Ignore
                }
            }
        }
        
        // 修正旧数据：如果没有开通时间，默认为当前时间 (For user upgraded from old version)
        // 仅当 data is null 时更新 (Check isn't easy in pure SQL blindly, but update with where clause is safe)
        const now = new Date().getTime();
        await db.executeSql(`UPDATE ${TABLE_NAME} SET startDate = ? WHERE startDate IS NULL OR startDate = 0`, [now]);

    } catch (e) {
        console.error('Migration failed:', JSON.stringify(e));
    }
  }

  private async ensureInitialized(): Promise<void> {
    if (this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      await this.initPromise;
    } else {
      throw new Error('SubscriptionRepository.init() not called');
    }
  }

  public async insert(subscription: SubscriptionModel, fromSync: boolean = false, skipRefresh: boolean = false): Promise<number> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      return Promise.reject('RdbStore not initialized');
    }
    const valueBucket: relationalStore.ValuesBucket = {
      uuid: subscription.uuid || '',
      name: subscription.name,
      price: subscription.price,
      currency: subscription.currency,
      billingCycle: subscription.billingCycle,
      nextBillingDate: subscription.nextBillingDate,
      icon: subscription.icon || '',
      category: subscription.category || '',
      lastModified: subscription.lastModified || new Date().getTime(),
      isDeleted: subscription.isDeleted ? 1 : 0,
      reminderDaysBefore: subscription.reminderDaysBefore !== undefined ? subscription.reminderDaysBefore : null,
      reminderTime: subscription.reminderTime !== undefined ? subscription.reminderTime : null,
      subCategory: subscription.subCategory || '',
      startDate: subscription.startDate || new Date().getTime(),
      isAutoRenewal: (subscription.isAutoRenewal === false) ? 0 : 1,
      paymentMethod: subscription.paymentMethod || '其他支付方式',
      // 团购券字段
      recordType: subscription.recordType || 'subscription',
      platform: subscription.platform || null,
      couponCode: subscription.couponCode || null,
      usageStatus: subscription.usageStatus || 'unused',
      merchantName: subscription.merchantName || null,
      quantity: subscription.quantity || 1,
      couponImage: subscription.couponImage || null,
      usageTime: subscription.usageTime || null,
      realUsageTime: subscription.realUsageTime || null
    };
    const rowId = await this.rdbStore.insert(TABLE_NAME, valueBucket);
    
    // Ensure ID is set for reminder scheduling
    subscription.id = rowId; 
    
    // Always schedule/update reminders to ensure local notification consistency
    LocalNotificationManager.getInstance().scheduleReminder(subscription);

    if (!fromSync && !skipRefresh) {
        this.updateWidgetSnapshotSync('insert');
        this.syncWithCloud();
        // Notify UI/Widget immediately for better UX
        GlobalBus.publish(EVENT_SYNC_COMPLETED);
    }
    return rowId;
  }

  public async queryAll(): Promise<SubscriptionModel[]> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      return Promise.reject('RdbStore not initialized');
    }
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    // 仅查询未删除的记录
    predicates.equalTo('isDeleted', 0);
    // Order by nextBillingDate ascending
    predicates.orderByAsc('nextBillingDate');

    const resultSet = await this.rdbStore.query(predicates);
    const subscriptions: SubscriptionModel[] = [];
    const now = new Date().getTime();
    const updatePromises: Promise<number>[] = [];
    
    while (resultSet.goToNextRow()) {
      const reminderDaysIdx = resultSet.getColumnIndex('reminderDaysBefore');
      const reminderTimeIdx = resultSet.getColumnIndex('reminderTime');

      const sub: SubscriptionModel = {
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        uuid: resultSet.getString(resultSet.getColumnIndex('uuid')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        price: resultSet.getDouble(resultSet.getColumnIndex('price')),
        currency: resultSet.getString(resultSet.getColumnIndex('currency')),
        billingCycle: resultSet.getString(resultSet.getColumnIndex('billingCycle')) as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
        nextBillingDate: resultSet.getLong(resultSet.getColumnIndex('nextBillingDate')),
        icon: resultSet.getString(resultSet.getColumnIndex('icon')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        lastModified: resultSet.getLong(resultSet.getColumnIndex('lastModified')),
        isDeleted: resultSet.getLong(resultSet.getColumnIndex('isDeleted')) === 1,
        reminderDaysBefore: resultSet.isColumnNull(reminderDaysIdx) ? undefined : resultSet.getLong(reminderDaysIdx),
        reminderTime: resultSet.isColumnNull(reminderTimeIdx) ? undefined : resultSet.getString(reminderTimeIdx),
        subCategory: resultSet.getString(resultSet.getColumnIndex('subCategory')),
        startDate: resultSet.getLong(resultSet.getColumnIndex('startDate')),
        isAutoRenewal: resultSet.getColumnIndex('isAutoRenewal') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('isAutoRenewal')) === 1 : true,
        paymentMethod: resultSet.getColumnIndex('paymentMethod') !== -1 ? resultSet.getString(resultSet.getColumnIndex('paymentMethod')) : '其他支付方式',
        // 团购券字段
        recordType: (resultSet.getColumnIndex('recordType') !== -1 ? resultSet.getString(resultSet.getColumnIndex('recordType')) : 'subscription') as 'subscription' | 'groupBuy',
        platform: resultSet.getColumnIndex('platform') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('platform')) ? resultSet.getString(resultSet.getColumnIndex('platform')) as 'meituan' | 'douyin' | 'dianping' : undefined,
        couponCode: resultSet.getColumnIndex('couponCode') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponCode')) ? resultSet.getString(resultSet.getColumnIndex('couponCode')) : undefined,
        usageStatus: resultSet.getColumnIndex('usageStatus') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageStatus')) ? resultSet.getString(resultSet.getColumnIndex('usageStatus')) as 'unused' | 'used' | 'expired' : 'unused',
        merchantName: resultSet.getColumnIndex('merchantName') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('merchantName')) ? resultSet.getString(resultSet.getColumnIndex('merchantName')) : undefined,
        quantity: resultSet.getColumnIndex('quantity') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('quantity')) : 1,
        couponImage: resultSet.getColumnIndex('couponImage') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponImage')) ? resultSet.getString(resultSet.getColumnIndex('couponImage')) : undefined,
        usageTime: resultSet.getColumnIndex('usageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageTime')) ? resultSet.getString(resultSet.getColumnIndex('usageTime')) : undefined,
        realUsageTime: resultSet.getColumnIndex('realUsageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('realUsageTime')) ? resultSet.getLong(resultSet.getColumnIndex('realUsageTime')) : undefined
      };
      
      // 自动推算过期的 nextBillingDate (永久订阅和不定周期不推算，非自动续费不推算)
      if (sub.billingCycle !== 'Lifetime' && sub.billingCycle !== 'Indefinite' && sub.isAutoRenewal !== false && sub.nextBillingDate > 0 && sub.nextBillingDate < now) {
        const updatedDate = this.calculateNextBillingDate(sub.nextBillingDate, sub.billingCycle);
        sub.nextBillingDate = updatedDate;
        sub.lastModified = now;
        // 异步更新数据库，不阻塞查询
        updatePromises.push(this.update(sub, true)); // fromSync=true 避免触发云同步循环
        
        // 关键修复: 自动续费后，必须重新注册提醒，否则下个周期不会提醒
        // update(..., true) 会跳过提醒注册，所以这里手动调用
        if (sub.reminderDaysBefore !== undefined) {
             LocalNotificationManager.getInstance().scheduleReminder(sub);
        }
      } else {
        // [New Feature] 如果提醒时间已过（且未触发自动续费，说明处于“已提醒但未到期”区间），自动关闭提醒开关
        if (sub.reminderDaysBefore !== undefined && sub.nextBillingDate > now) {
            const reminderDays = sub.reminderDaysBefore || 1;
            const reminderTimeStr = sub.reminderTime || '09:00';
            const timeParts = reminderTimeStr.split(':');
            let hour = 9;
            let minute = 0;
            if (timeParts.length >= 2) {
              hour = Number(timeParts[0]);
              minute = Number(timeParts[1]);
            }
            const targetDate = new Date(sub.nextBillingDate);
            targetDate.setDate(targetDate.getDate() - reminderDays);
            targetDate.setHours(hour, minute, 0, 0);

            // 如果提醒时间已过
            if (targetDate.getTime() < now) {
                // 自动关闭提醒
                sub.reminderDaysBefore = undefined;
                sub.reminderTime = undefined;
                sub.lastModified = now;
                updatePromises.push(this.update(sub, true)); // Persist change
                // Also cancel notification just in case (though it should be done by update logic but we passed fromSync=true)
                // Actually update(true) does NOT call schedule/cancel.
                // So we should manually cancel if needed? 
                // Wait, if it triggered, it's gone from system (one-shot).
                // If we want to be safe: 
                LocalNotificationManager.getInstance().cancelReminder(sub.id!);
            }
        }
      }
      
      subscriptions.push(sub);
    }
    resultSet.close();
    
    // 如果有更新，触发一次云同步
    if (updatePromises.length > 0) {
      Promise.all(updatePromises).then(() => {
        this.syncWithCloud();
        // 如果是自动续费导致的日期变动，同步更新卡片快照
        this.updateWidgetSnapshotSync('auto_renewal');
      });
    }
    // 统一排序：按扣款日期升序，但将永久订阅的项目沉底（因为它们没有后续扣款，且不需要提醒）
    subscriptions.sort((a, b) => {
      if (a.billingCycle === 'Lifetime' && b.billingCycle !== 'Lifetime') return 1;
      if (a.billingCycle !== 'Lifetime' && b.billingCycle === 'Lifetime') return -1;
      return a.nextBillingDate - b.nextBillingDate;
    });
    
    return subscriptions;
  }
  
  /**
   * 计算下一个扣款日期
   * 将过期日期推算到下一个周期
   */
  private calculateNextBillingDate(currentDate: number, billingCycle: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite'): number {
    const nextDate = new Date(currentDate);
    const nowCursor = new Date();
    
    // 如果是永久会员或不定周期,无需更新日期
    if (billingCycle === 'Lifetime' || billingCycle === 'Indefinite') {
      return currentDate;
    }
    
    // 循环增加周期直到大于当前时间
    while (nextDate.getTime() <= nowCursor.getTime()) {
      if (billingCycle === 'Monthly') {
        nextDate.setMonth(nextDate.getMonth() + 1);
      } else if (billingCycle === 'Quarterly') {
        nextDate.setMonth(nextDate.getMonth() + 3);
      } else if (billingCycle === 'Yearly') {
        nextDate.setFullYear(nextDate.getFullYear() + 1);
      }
    }
    
    return nextDate.getTime();
  }
  public async update(subscription: SubscriptionModel, fromSync: boolean = false, skipRefresh: boolean = false): Promise<number> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      return Promise.reject('RdbStore not initialized');
    }
    const valueBucket: relationalStore.ValuesBucket = {
      name: subscription.name,
      price: subscription.price,
      currency: subscription.currency,
      billingCycle: subscription.billingCycle,
      nextBillingDate: subscription.nextBillingDate,
      icon: subscription.icon || '',
      category: subscription.category || '',
      lastModified: subscription.lastModified || new Date().getTime(),
      isDeleted: subscription.isDeleted ? 1 : 0,
      reminderDaysBefore: subscription.reminderDaysBefore !== undefined ? subscription.reminderDaysBefore : null,
      reminderTime: subscription.reminderTime !== undefined ? subscription.reminderTime : null,
      subCategory: subscription.subCategory || '',
      startDate: subscription.startDate || new Date().getTime(),
      isAutoRenewal: (subscription.isAutoRenewal === false) ? 0 : 1,
      paymentMethod: subscription.paymentMethod || '其他支付方式',
      // 团购券字段
      recordType: subscription.recordType || 'subscription',
      platform: subscription.platform || null,
      couponCode: subscription.couponCode || null,
      usageStatus: subscription.usageStatus || 'unused',
      merchantName: subscription.merchantName || null,
      quantity: subscription.quantity || 1,
      couponImage: subscription.couponImage || null,
      usageTime: subscription.usageTime || null,
      realUsageTime: subscription.realUsageTime || null
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    if (!subscription.id) {
       return Promise.reject('Subscription ID is missing for update');
    }
    predicates.equalTo('id', subscription.id);
    const rows = await this.rdbStore.update(valueBucket, predicates);
        
    if (rows > 0) {
        // Always schedule/update reminders to ensure local notification consistency
        LocalNotificationManager.getInstance().scheduleReminder(subscription);
        
        if (!fromSync && !skipRefresh) {
            this.updateWidgetSnapshotSync('update');
            this.syncWithCloud();
            // Notify UI/Widget immediately for better UX
            GlobalBus.publish(EVENT_SYNC_COMPLETED);
        }
    }
    return rows;
  }

  /**
   * 安全导入/批量更新 (Upsert based on UUID)
   * @param skipRefresh 如果在循环中调用，建议设置为 true 以减少性能开销
   */
  public async upsert(subscription: SubscriptionModel, skipRefresh: boolean = false): Promise<number> {
    await this.ensureInitialized();
    if (!subscription.uuid) {
        subscription.uuid = util.generateRandomUUID(true);
    }

    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('uuid', subscription.uuid);
    const resultSet = await this.rdbStore!.query(predicates);
    
    let result = 0;
    if (resultSet.rowCount > 0) {
        // Exists -> Update
        resultSet.goToFirstRow();
        const existingId = resultSet.getLong(resultSet.getColumnIndex('id'));
        subscription.id = existingId; // Force use local ID
        subscription.isDeleted = false; 
        result = await this.update(subscription, false, skipRefresh);
    } else {
        // New -> Insert
        subscription.id = undefined; // Ensure ID is undefined so DB autocreates it
        subscription.isDeleted = false;
        result = await this.insert(subscription, false, skipRefresh);
    }
    resultSet.close();
    return result;
  }

  public async delete(id: number, fromSync: boolean = false): Promise<number> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      return Promise.reject('RdbStore not initialized');
    }
    // 采用软删除逻辑：更新 isDeleted 标记和 lastModified
    const valueBucket: relationalStore.ValuesBucket = {
      isDeleted: 1,
      lastModified: new Date().getTime()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    const rows = await this.rdbStore.update(valueBucket, predicates);

    // always cancel reminder on delete
    if (rows > 0) {
        LocalNotificationManager.getInstance().cancelReminder(id);
    }

    if (rows > 0 && !fromSync) {
        this.updateWidgetSnapshotSync('delete');
        // Notify UI/Widget immediately for better UX
        GlobalBus.publish(EVENT_SYNC_COMPLETED);
    }
    return rows;
  }

  public async clearAllData(): Promise<void> {
    await this.ensureInitialized();
    if (!this.rdbStore) {
      return Promise.reject('RdbStore not initialized');
    }
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    await this.rdbStore.delete(predicates);
    console.info('All local data cleared');
  }

  /**
   * 云端同步核心逻辑
   */
  public async syncWithCloud(): Promise<void> {
    console.info('Sync requested but disabled (Local Mode)');
  }

  /**
   * 强制同步 (已废弃 - 本地模式)
   */
  public async forceSync(): Promise<void> {
    console.info('Force sync requested but disabled (Local Mode)');
  }

  private async doSync(forceSync: boolean = false) {
    // No-op
  }

  // mergeToLocal removed

  /**
   * 清除所有自定义图标 (file:// 开头的)
   * 用于清除缓存功能的配套数据库操作
   */
  public async clearCustomIcons(): Promise<number> {
    await this.ensureInitialized();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.beginsWith('icon', 'file://');
    
    const valueBucket: relationalStore.ValuesBucket = {
        'icon': ''
    };
    
    const rows = await this.rdbStore!.update(valueBucket, predicates);
    
    if (rows > 0) {
        // 触发更新
        this.updateWidgetSnapshotSync('update');
        this.syncWithCloud();
        GlobalBus.publish(EVENT_SYNC_COMPLETED);
    }
    return rows;
  }
  private async queryAllInternal(includeDeleted: boolean = false): Promise<SubscriptionModel[]> {
    await this.ensureInitialized();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    if (!includeDeleted) {
      predicates.equalTo('isDeleted', 0);
    }
    
    const resultSet = await this.rdbStore!.query(predicates);
    const subscriptions: SubscriptionModel[] = [];
    while (resultSet.goToNextRow()) {
      const reminderDaysIdx = resultSet.getColumnIndex('reminderDaysBefore');
      const reminderTimeIdx = resultSet.getColumnIndex('reminderTime');

      subscriptions.push({
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        uuid: resultSet.getString(resultSet.getColumnIndex('uuid')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        price: resultSet.getDouble(resultSet.getColumnIndex('price')),
        currency: resultSet.getString(resultSet.getColumnIndex('currency')),
        billingCycle: resultSet.getString(resultSet.getColumnIndex('billingCycle')) as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
        nextBillingDate: resultSet.getLong(resultSet.getColumnIndex('nextBillingDate')),
        icon: resultSet.getString(resultSet.getColumnIndex('icon')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        lastModified: resultSet.getLong(resultSet.getColumnIndex('lastModified')),
        isDeleted: resultSet.getLong(resultSet.getColumnIndex('isDeleted')) === 1,
        reminderDaysBefore: resultSet.isColumnNull(reminderDaysIdx) ? undefined : resultSet.getLong(reminderDaysIdx),
        reminderTime: resultSet.isColumnNull(reminderTimeIdx) ? undefined : resultSet.getString(reminderTimeIdx),
        subCategory: resultSet.getString(resultSet.getColumnIndex('subCategory')),
        startDate: resultSet.getLong(resultSet.getColumnIndex('startDate')),
        isAutoRenewal: resultSet.getColumnIndex('isAutoRenewal') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('isAutoRenewal')) === 1 : true,
        paymentMethod: resultSet.getColumnIndex('paymentMethod') !== -1 ? resultSet.getString(resultSet.getColumnIndex('paymentMethod')) : '其他支付方式',
        // 团购券字段
        recordType: (resultSet.getColumnIndex('recordType') !== -1 ? resultSet.getString(resultSet.getColumnIndex('recordType')) : 'subscription') as 'subscription' | 'groupBuy',
        platform: resultSet.getColumnIndex('platform') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('platform')) ? resultSet.getString(resultSet.getColumnIndex('platform')) as 'meituan' | 'douyin' | 'dianping' : undefined,
        couponCode: resultSet.getColumnIndex('couponCode') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponCode')) ? resultSet.getString(resultSet.getColumnIndex('couponCode')) : undefined,
        usageStatus: resultSet.getColumnIndex('usageStatus') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageStatus')) ? resultSet.getString(resultSet.getColumnIndex('usageStatus')) as 'unused' | 'used' | 'expired' : 'unused',
        merchantName: resultSet.getColumnIndex('merchantName') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('merchantName')) ? resultSet.getString(resultSet.getColumnIndex('merchantName')) : undefined,
        quantity: resultSet.getColumnIndex('quantity') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('quantity')) : 1,
        couponImage: resultSet.getColumnIndex('couponImage') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponImage')) ? resultSet.getString(resultSet.getColumnIndex('couponImage')) : undefined,
        usageTime: resultSet.getColumnIndex('usageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageTime')) ? resultSet.getString(resultSet.getColumnIndex('usageTime')) : undefined,
        realUsageTime: resultSet.getColumnIndex('realUsageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('realUsageTime')) ? resultSet.getLong(resultSet.getColumnIndex('realUsageTime')) : undefined
      });
    }
    resultSet.close();
    return subscriptions;
  }

  public async findByUuid(uuid: string): Promise<SubscriptionModel | null> {
    await this.ensureInitialized();
    if (!this.rdbStore) return null;
    
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('uuid', uuid);
    
    const resultSet = await this.rdbStore.query(predicates);
    if (resultSet.rowCount === 0) {
        resultSet.close();
        return null;
    }
    
    resultSet.goToFirstRow();
    
    const reminderDaysIdx = resultSet.getColumnIndex('reminderDaysBefore');
    const reminderTimeIdx = resultSet.getColumnIndex('reminderTime');

    const sub: SubscriptionModel = {
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        uuid: resultSet.getString(resultSet.getColumnIndex('uuid')),
        name: resultSet.getString(resultSet.getColumnIndex('name')),
        price: resultSet.getDouble(resultSet.getColumnIndex('price')),
        currency: resultSet.getString(resultSet.getColumnIndex('currency')),
        billingCycle: resultSet.getString(resultSet.getColumnIndex('billingCycle')) as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
        nextBillingDate: resultSet.getLong(resultSet.getColumnIndex('nextBillingDate')),
        icon: resultSet.getString(resultSet.getColumnIndex('icon')),
        category: resultSet.getString(resultSet.getColumnIndex('category')),
        lastModified: resultSet.getLong(resultSet.getColumnIndex('lastModified')),
        isDeleted: resultSet.getLong(resultSet.getColumnIndex('isDeleted')) === 1,
        reminderDaysBefore: resultSet.isColumnNull(reminderDaysIdx) ? undefined : resultSet.getLong(reminderDaysIdx),
        reminderTime: resultSet.isColumnNull(reminderTimeIdx) ? undefined : resultSet.getString(reminderTimeIdx),
        subCategory: resultSet.getString(resultSet.getColumnIndex('subCategory')),
        startDate: resultSet.getLong(resultSet.getColumnIndex('startDate')),
        isAutoRenewal: resultSet.getColumnIndex('isAutoRenewal') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('isAutoRenewal')) === 1 : true,
        paymentMethod: resultSet.getColumnIndex('paymentMethod') !== -1 ? resultSet.getString(resultSet.getColumnIndex('paymentMethod')) : '其他支付方式',
        // 团购券字段
        recordType: (resultSet.getColumnIndex('recordType') !== -1 ? resultSet.getString(resultSet.getColumnIndex('recordType')) : 'subscription') as 'subscription' | 'groupBuy',
        platform: resultSet.getColumnIndex('platform') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('platform')) ? resultSet.getString(resultSet.getColumnIndex('platform')) as 'meituan' | 'douyin' | 'dianping' : undefined,
        couponCode: resultSet.getColumnIndex('couponCode') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponCode')) ? resultSet.getString(resultSet.getColumnIndex('couponCode')) : undefined,
        usageStatus: resultSet.getColumnIndex('usageStatus') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageStatus')) ? resultSet.getString(resultSet.getColumnIndex('usageStatus')) as 'unused' | 'used' | 'expired' : 'unused',
        merchantName: resultSet.getColumnIndex('merchantName') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('merchantName')) ? resultSet.getString(resultSet.getColumnIndex('merchantName')) : undefined,
        quantity: resultSet.getColumnIndex('quantity') !== -1 ? resultSet.getLong(resultSet.getColumnIndex('quantity')) : 1,
        couponImage: resultSet.getColumnIndex('couponImage') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('couponImage')) ? resultSet.getString(resultSet.getColumnIndex('couponImage')) : undefined,
        usageTime: resultSet.getColumnIndex('usageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('usageTime')) ? resultSet.getString(resultSet.getColumnIndex('usageTime')) : undefined,
        realUsageTime: resultSet.getColumnIndex('realUsageTime') !== -1 && !resultSet.isColumnNull(resultSet.getColumnIndex('realUsageTime')) ? resultSet.getLong(resultSet.getColumnIndex('realUsageTime')) : undefined
    };
    resultSet.close();
    return sub;
  }

  /**
   * 同步更新卡片数据快照
   * 供 FormAbility.onAddForm 同步读取，实现“秒开”
   */
  public async updateWidgetSnapshotSync(action: string) {
      hilog.info(0x0000, 'SubscriptionRepository', `Updating widget snapshot due to ${action}`);
      try {
          const subs = await this.queryAllInternal(false);
          // 仅取前10条，防止快照文件过大且符合桌面卡片建议展示数量
          const topSubs = subs.slice(0, 10);
          
          let isLoggedIn = true; // Simplified: Snapshot UI always shows content overlay if exists

          const widgetList: SnapshotItem[] = topSubs.map(item => {
              let iconKey = item.icon || '';
              // 如果没有图标，使用名称首字母作为兜底
              if (!iconKey && item.name && item.name.length > 0) {
                  iconKey = item.name.charAt(0).toUpperCase();
              }
              
              const days = DateUtil.getDaysUntil(item.nextBillingDate);
              const dateStr = DateUtil.formatShortDate(item.nextBillingDate);
              
              const isGroupBuy = item.recordType === 'groupBuy';
              
              const snapshotItem = new SnapshotItem();
              snapshotItem.title = item.name || (isGroupBuy ? '未知团购' : '未知订阅');
              snapshotItem.content = isGroupBuy ? (item.merchantName ? `${item.merchantName}` : '团购券') : `到期:${dateStr}`;
              snapshotItem.icon = iconKey;
              snapshotItem.isExpiring = days <= 3;
              
              const minimalItem: MinimalCardItem = {
                  id: item.id || 0,
                  recordType: item.recordType || 'subscription',
                  usageStatus: item.usageStatus || 'unused',
                  name: item.name || ''
              };
              snapshotItem.originalItem = JSON.stringify(minimalItem);
              return snapshotItem;
          });

          const snapshot = new SnapshotData();
          snapshot.widgetData = widgetList;
          snapshot.isLoggedIn = isLoggedIn;
          snapshot.totalCount = subs.length;
          snapshot.activeThemeId = PreferenceUtil.getInstance().getThemeId();
          snapshot.timestamp = new Date().getTime();

          if (!this.context) {
              hilog.error(0x0000, 'SubscriptionRepository', 'Cannot save snapshot: context is missing');
              return;
          }

          const filePath = this.context.filesDir + '/widget_snapshot.json';
          const tmpPath = filePath + '.tmp';
          const content = JSON.stringify(snapshot);
          
          // Atomic write: write to tmp then rename
          let file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, content);
          fs.closeSync(file);
          
          // Rename tmp to official path
          if (fs.accessSync(filePath)) {
              fs.unlinkSync(filePath);
          }
          fs.renameSync(tmpPath, filePath);
          
          hilog.info(0x0000, 'SubscriptionRepository', `Widget snapshot updated: items=${widgetList.length}, login=${isLoggedIn}`);
      } catch (err) {
          const error: BusinessError = err as BusinessError;
          hilog.error(0x0000, 'SubscriptionRepository', `Failed to update widget snapshot: ${error.code} ${error.message}`);
      }
  }

  /**
   * 导出所有数据为 JSON 字符串
   * 用于本地备份
   */
  public async exportToJson(): Promise<string> {
    const subs = await this.queryAllInternal(false);
    return JSON.stringify(subs, null, 2);
  }

  /**
   * 从 JSON 导入数据
   * @param jsonStr JSON 字符串
   * @returns 导入成功的数量
   */
  public async importFromJson(jsonStr: string): Promise<number> {
    try {
      const subs = JSON.parse(jsonStr) as SubscriptionModel[];
      if (!Array.isArray(subs)) {
        throw new Error('Invalid JSON format: root is not an array');
      }

      let count = 0;
      await this.ensureInitialized();

      for (const item of subs) {
        // 简单校验必要字段
        if (!item.name || !item.uuid) continue;

        // 检查是否存在
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('uuid', item.uuid);
        const resultSet = await this.rdbStore!.query(predicates);
        
        if (resultSet.rowCount > 0) {
           // 存在则更新 (overwrite strategy for restore)
           resultSet.goToFirstRow();
           const existingId = resultSet.getLong(resultSet.getColumnIndex('id'));
           item.id = existingId;
           // 保持本地状态标记
           item.isDeleted = false; 
           await this.update(item, true); // fromSync=true to avoid double sync logic
        } else {
           // 不存在则插入
           item.id = undefined; // Let DB auto-increment
           item.isDeleted = false;
           await this.insert(item, true);
        }
        resultSet.close();
        count++;
      }
      
      // 完成后触发一次全局刷新
      this.updateWidgetSnapshotSync('import_completed');
      GlobalBus.publish(EVENT_SYNC_COMPLETED);
      
      return count;
    } catch (e) {
      hilog.error(0x0000, 'SubscriptionRepository', `Import failed: ${JSON.stringify(e)}`);
      throw new Error(`Import failed: ${e}`);
    }
  }
}
