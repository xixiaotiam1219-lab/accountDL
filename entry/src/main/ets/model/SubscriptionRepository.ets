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
import { WARRANTY_ICON_MAP_NAMES, WARRANTY_THEME_MAP, getWarrantyThemeColors } from '../utils/WarrantyConstants';

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
  uuid?: string;
  recordType: 'subscription' | 'groupBuy' | 'warranty' | 'card';
  usageStatus: 'unused' | 'used' | 'expired';
  isWarranty?: boolean;
  name: string;
  price?: number;
  currency?: string;
  platform?: string;
  billingCycle: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
  icon?: string;
  category?: string;
  subCategory?: string;
  isAutoRenewal?: boolean;
  paymentMethod?: string;
  startDate?: number;
  brand?: string;
  purchaseChannel?: string;
  merchantName?: string;
  nextBillingDate?: number;
}

class SnapshotItem {
  id: string = '';
  title: string = '';
  content: string = '';
  icon: string = '';
  colorStart?: string;
  colorEnd?: string;
  isExpiring: boolean = false;
  isLifetime: boolean = false;
  isGroupBuy: boolean = false;
  isWarranty: boolean = false;
  isCard: boolean = false;
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
      { name: 'realUsageTime', type: 'INTEGER' },
      // 保修/保质期专属字段
      { name: 'brand', type: 'TEXT' },
      { name: 'purchaseChannel', type: 'TEXT' },
      // 附加延保服务字段 (JSON 数组存储)
      { name: 'extendedWarranties', type: 'TEXT' },
      // 提醒状态控制字段
      { name: 'lastIgnoredBillingDate', type: 'INTEGER' },
      // 补充缺失的迁移定义（防止从更早版本升级时缺失字段）
      { name: 'startDate', type: 'INTEGER' },
      { name: 'paymentMethod', type: 'TEXT DEFAULT "其他支付方式"' },
      { name: 'icon', type: 'TEXT' },
      { name: 'category', type: 'TEXT' },
      { name: 'reminderDaysBefore', type: 'INTEGER DEFAULT 1' },
      { name: 'reminderTime', type: 'TEXT DEFAULT "09:00"' },
      { name: 'subCategory', type: 'TEXT' },
      { name: 'isAutoRenewal', type: 'INTEGER DEFAULT 1' },
      { name: 'lastModified', type: 'INTEGER' },
      { name: 'isDeleted', type: 'INTEGER DEFAULT 0' },
      // 卡证专属字段
      { name: 'cardLastFour', type: 'TEXT' },
      { name: 'cardBalance', type: 'REAL' },
      { name: 'cardType', type: 'TEXT' }
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
      realUsageTime: subscription.realUsageTime || null,
      // 保修/保质期字段
      brand: subscription.brand || null,
      purchaseChannel: subscription.purchaseChannel || null,
      // 附加延保服务字段 (JSON)
      extendedWarranties: subscription.extendedWarranties || null,
      // 提醒状态
      lastIgnoredBillingDate: subscription.lastIgnoredBillingDate || null,
      // 卡证字段
      cardLastFour: subscription.cardLastFour || null,
      cardBalance: subscription.cardBalance !== undefined ? subscription.cardBalance : null,
      cardType: subscription.cardType || null
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
      const sub: SubscriptionModel = this.mapResultSetToModel(resultSet);

      // 自动推算过期的 nextBillingDate (永久订阅和不定周期不推算，非自动续费不推算)
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      if (sub.billingCycle !== 'Lifetime' && sub.billingCycle !== 'Indefinite' && sub.isAutoRenewal !== false && sub.nextBillingDate > 0 && sub.nextBillingDate < todayStart.getTime()) {
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
      } else if (sub.recordType === 'groupBuy' && sub.usageStatus === 'unused' && sub.nextBillingDate > 0 && sub.nextBillingDate < todayStart.getTime()) {
        // 团购券过期逻辑：如果已过有效期，自动标记为已过期
        sub.usageStatus = 'expired';
        // 清除提醒设置
        sub.reminderDaysBefore = undefined;
        sub.reminderTime = undefined;
        sub.lastModified = now;
        updatePromises.push(this.update(sub, true));
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

    // 如果有更新，同步等待更新完成，防止后台意图过早退出导致更新中断
    if (updatePromises.length > 0) {
      await Promise.all(updatePromises);
      this.syncWithCloud();
      // 如果是自动续费导致的日期变动，同步更新卡片快照
      this.updateWidgetSnapshotSync('auto_renewal');
    }
    // 统一排序：按扣款日期升序，但将永久订阅（非卡证）沉底（它们没有后续扣款）
    subscriptions.sort((a, b) => {
      const aIsLifetime = a.billingCycle === 'Lifetime' && a.recordType !== 'card';
      const bIsLifetime = b.billingCycle === 'Lifetime' && b.recordType !== 'card';
      if (aIsLifetime && !bIsLifetime) return 1;
      if (!aIsLifetime && bIsLifetime) return -1;
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
      realUsageTime: subscription.realUsageTime || null,
      // 保修/保质期字段
      brand: subscription.brand || null,
      purchaseChannel: subscription.purchaseChannel || null,
      // 附加延保服务字段 (JSON)
      extendedWarranties: subscription.extendedWarranties || null,
      // 提醒状态
      lastIgnoredBillingDate: subscription.lastIgnoredBillingDate || null,
      // 卡证字段
      cardLastFour: subscription.cardLastFour || null,
      cardBalance: subscription.cardBalance !== undefined ? subscription.cardBalance : null,
      cardType: subscription.cardType || null
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
      const existingId = this.getLongSafe(resultSet, 'id');
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

    try {
      // 1. 在彻底清空本地数据前，先批量取消所有系统级排程提醒，防止提醒泄漏
      const subs = await this.queryAll();
      if (subs && subs.length > 0) {
        await LocalNotificationManager.getInstance().cancelAllReminders(subs);
      } else {
        // 如果没有普通订阅，也确保取消新年提醒
        await LocalNotificationManager.getInstance().cancelNewYearReminder();
      }
    } catch (e) {
      console.error(`Failed to cancel reminders during clearAllData: ${(e as Error).message}`);
    }

    // 2. 清空数据库列表
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
      subscriptions.push(this.mapResultSetToModel(resultSet));
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
    const sub = this.mapResultSetToModel(resultSet);
    resultSet.close();
    return sub;
  }

  public async findById(id: number): Promise<SubscriptionModel | null> {
    await this.ensureInitialized();
    if (!this.rdbStore) return null;

    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);

    const resultSet = await this.rdbStore.query(predicates);
    if (resultSet.rowCount === 0) {
      resultSet.close();
      return null;
    }

    resultSet.goToFirstRow();
    const sub = this.mapResultSetToModel(resultSet);
    resultSet.close();
    return sub;
  }

  private mapResultSetToModel(resultSet: relationalStore.ResultSet): SubscriptionModel {
    return {
      id: this.getLongSafe(resultSet, 'id'),
      uuid: this.getStringSafe(resultSet, 'uuid') || '',
      name: this.getStringSafe(resultSet, 'name') || '',
      price: this.getDoubleSafe(resultSet, 'price'),
      currency: this.getStringSafe(resultSet, 'currency') || 'CNY',
      billingCycle: (this.getStringSafe(resultSet, 'billingCycle') || 'Monthly') as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite',
      nextBillingDate: this.getLongSafe(resultSet, 'nextBillingDate'),
      icon: this.getStringSafe(resultSet, 'icon'),
      category: this.getStringSafe(resultSet, 'category'),
      lastModified: this.getLongSafe(resultSet, 'lastModified'),
      isDeleted: this.getLongSafe(resultSet, 'isDeleted') === 1,
      reminderDaysBefore: this.getLongOrUndefined(resultSet, 'reminderDaysBefore'),
      reminderTime: this.getStringSafe(resultSet, 'reminderTime'),
      subCategory: this.getStringSafe(resultSet, 'subCategory'),
      startDate: this.getLongSafe(resultSet, 'startDate'),
      isAutoRenewal: this.getLongSafe(resultSet, 'isAutoRenewal') !== 0, // Default to true if missing or 1 (since 0 is false)
      paymentMethod: this.getStringSafe(resultSet, 'paymentMethod') || '其他支付方式',
      // 团购券字段
      recordType: (this.getStringSafe(resultSet, 'recordType') || 'subscription') as 'subscription' | 'groupBuy' | 'warranty' | 'card',
      platform: this.getStringSafe(resultSet, 'platform') as 'meituan' | 'douyin' | 'dianping',
      couponCode: this.getStringSafe(resultSet, 'couponCode'),
      usageStatus: (this.getStringSafe(resultSet, 'usageStatus') || 'unused') as 'unused' | 'used' | 'expired',
      merchantName: this.getStringSafe(resultSet, 'merchantName'),
      quantity: this.getLongSafe(resultSet, 'quantity') || 1,
      couponImage: this.getStringSafe(resultSet, 'couponImage'),
      usageTime: this.getStringSafe(resultSet, 'usageTime'),
      realUsageTime: this.getLongOrUndefined(resultSet, 'realUsageTime'),
      brand: this.getStringSafe(resultSet, 'brand'),
      purchaseChannel: this.getStringSafe(resultSet, 'purchaseChannel'),
      extendedWarranties: this.getStringSafe(resultSet, 'extendedWarranties'),
      lastIgnoredBillingDate: this.getLongOrUndefined(resultSet, 'lastIgnoredBillingDate'),
      // 卡证字段
      cardLastFour: this.getStringSafe(resultSet, 'cardLastFour'),
      cardBalance: (() => {
        const idx = resultSet.getColumnIndex('cardBalance');
        if (idx === -1 || resultSet.isColumnNull(idx)) return undefined;
        return resultSet.getDouble(idx); // 0 是合法余额，不能用 || undefined
      })(),
      cardType: this.getStringSafe(resultSet, 'cardType')
    };
  }

  private getStringSafe(resultSet: relationalStore.ResultSet, columnName: string): string | undefined {
    const index = resultSet.getColumnIndex(columnName);
    if (index === -1 || resultSet.isColumnNull(index)) {
      return undefined;
    }
    return resultSet.getString(index);
  }

  private getLongSafe(resultSet: relationalStore.ResultSet, columnName: string): number {
    const index = resultSet.getColumnIndex(columnName);
    if (index === -1 || resultSet.isColumnNull(index)) {
      return 0;
    }
    return resultSet.getLong(index);
  }

  private getLongOrUndefined(resultSet: relationalStore.ResultSet, columnName: string): number | undefined {
    const index = resultSet.getColumnIndex(columnName);
    if (index === -1 || resultSet.isColumnNull(index)) {
      return undefined;
    }
    return resultSet.getLong(index);
  }

  private getDoubleSafe(resultSet: relationalStore.ResultSet, columnName: string): number {
    const index = resultSet.getColumnIndex(columnName);
    if (index === -1 || resultSet.isColumnNull(index)) {
      return 0;
    }
    return resultSet.getDouble(index);
  }

  /**
   * 同步更新卡片数据快照
   * 供 FormAbility.onAddForm 同步读取，实现“秒开”
   */
  public async updateWidgetSnapshotSync(action: string) {
    hilog.info(0x0000, 'SubscriptionRepository', `Updating widget snapshot due to ${action}`);
    try {
      const subs = await this.queryAllInternal(false);
      // 移除 .slice(0, 10) 限制，允许展示更多项目
      // const topSubs = subs.slice(0, 10);
      const topSubs = subs;

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
        const isWarranty = item.recordType === 'warranty';
        const isCard = item.recordType === 'card';
        const isLifetime = item.billingCycle === 'Lifetime';
        // 证件类型（驾照、身份证、护照等）
        const ID_TYPES = ['驾照/行驶证', '身份证/护照', '社保卡/医保卡'];
        const isIDCard = isCard && (item.cardType ? ID_TYPES.includes(item.cardType) : false);

        const snapshotItem = new SnapshotItem();
        
        if (isGroupBuy) {
           snapshotItem.title = item.name || '未知团购';
           const statusText: string = item.usageStatus === 'used' ? '已使用' : (item.usageStatus === 'expired' ? '已过期' : `剩 ${days} 天`);
           snapshotItem.content = item.merchantName ? `${item.merchantName} | ${statusText}` : statusText;
        } else if (isWarranty) {
           snapshotItem.title = item.name || '未知保修';
           snapshotItem.content = `保修:${dateStr}`;
           
           let warrantyName = item.name || '';
           if (item.category && WARRANTY_ICON_MAP_NAMES[item.category]) {
             warrantyName = item.category;
           } else if (item.subCategory && WARRANTY_ICON_MAP_NAMES[item.subCategory]) {
             warrantyName = item.subCategory;
           }

           const theme = WARRANTY_THEME_MAP[warrantyName] || 'blue';
           const colors = getWarrantyThemeColors(theme);
           snapshotItem.colorStart = colors[0];
           snapshotItem.colorEnd = colors[1];
           
           const svgPath = WARRANTY_ICON_MAP_NAMES[warrantyName];
           if (svgPath) {
             snapshotItem.icon = `rawfile:${svgPath}`;
           }
        } else if (isCard) {
           // 卡证类型：证件显示有效期，其他显示卡类型/余额
           snapshotItem.title = item.name || '未知卡证';
           if (isIDCard) {
             // 证件类型：显示有效期
             snapshotItem.content = `有效期至 ${dateStr}`;
           } else if (item.cardBalance !== undefined && item.cardBalance !== null) {
             snapshotItem.content = `${item.cardType || '卡证'} · 余额 ¥${(item.cardBalance as number).toFixed(2)}`;
           } else {
             snapshotItem.content = item.cardType || '卡证';
           }
        } else if (isLifetime) {
           snapshotItem.title = item.name || '未知订阅';
           snapshotItem.content = `永久买断`;
        } else {
           snapshotItem.title = item.name || '未知订阅';
           snapshotItem.content = `到期:${dateStr}`;
        }
        
        if (!snapshotItem.icon) {
          snapshotItem.icon = iconKey;
        }
        snapshotItem.id = item.uuid || item.id?.toString() || '';
        snapshotItem.isLifetime = isLifetime;
        snapshotItem.isGroupBuy = isGroupBuy;
        snapshotItem.isWarranty = isWarranty;
        snapshotItem.isCard = isCard;

        // 普通订阅和保修在剩余3天内标红；团购券如果是未使用且剩余3天内也标红；证件类有效期内3天标红
        if (isGroupBuy) {
            snapshotItem.isExpiring = item.usageStatus === 'unused' && days <= 3;
        } else {
            snapshotItem.isExpiring = days <= 3;
        }

        const minimalItem: MinimalCardItem = {
          id: item.id || 0,
          uuid: item.uuid,
          recordType: item.recordType || 'subscription',
          usageStatus: item.usageStatus || 'unused',
          isWarranty: isWarranty,
          name: item.name || '',
          price: item.price,
          currency: item.currency,
          platform: item.platform,
          merchantName: item.merchantName,
          nextBillingDate: item.nextBillingDate,
          billingCycle: (item.billingCycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite') || 'Monthly',
          icon: item.icon,
          category: item.category,
          subCategory: item.subCategory,
          isAutoRenewal: item.isAutoRenewal,
          paymentMethod: item.paymentMethod,
          startDate: item.startDate,
          brand: item.brand,
          purchaseChannel: item.purchaseChannel
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
          const existingId = this.getLongSafe(resultSet, 'id');
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
