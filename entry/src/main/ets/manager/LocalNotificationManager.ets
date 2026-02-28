import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { SubscriptionModel, ExtendedWarrantyItem } from '../model/SubscriptionModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { common } from '@kit.AbilityKit';
import { GlobalBus, EVENT_NOTIFY_PERMISSION_GRANTED } from '../utils/GlobalBus';
import { SubscriptionRepository } from '../model/SubscriptionRepository';

const TAG = 'LocalNotificationManager';
const DOMAIN = 0x0000;

interface ReminderBasicInfo {
  notificationId: number;
}

export class LocalNotificationManager {
  private static instance: LocalNotificationManager;
  private static readonly KEY_NEW_YEAR_REMINDER_ID = 'new_year_reminder_id';

  private constructor() {}

  public static getInstance(): LocalNotificationManager {
    if (!LocalNotificationManager.instance) {
      LocalNotificationManager.instance = new LocalNotificationManager();
    }
    return LocalNotificationManager.instance;
  }

  /**
   * 为订阅添加或更新提醒
   * @param sub 订阅对象
   */
  public async scheduleReminder(sub: SubscriptionModel): Promise<void> {
    // 允许 warranty 类型的 Lifetime 周期设置提醒
    if (!sub.id || (sub.billingCycle === 'Lifetime' && sub.recordType !== 'warranty') || sub.isDeleted || sub.reminderDaysBefore === undefined || sub.reminderDaysBefore === null) {
      if (sub.id) {
        await this.cancelReminder(sub.id);
      }
      return;
    }

    const reminderDays: number = sub.reminderDaysBefore;
    const reminderTimeStr: string = sub.reminderTime || '09:00';
    const timeParts: string[] = reminderTimeStr.split(':');
    let hour: number = 9;
    let minute: number = 0;
    if (timeParts.length >= 2) {
      hour = Number(timeParts[0]);
      minute = Number(timeParts[1]);
    }

    const isEnabled: boolean = await this.isNotificationEnabled();
    if (!isEnabled) return;

    try {
      if (sub.id) {
        await this.cancelReminder(sub.id);
      }

      // 1. 排程主周期提醒
      await this.publishSpecificReminder(sub, sub.nextBillingDate, sub.name, sub.recordType || 'subscription', reminderDays, hour, minute, 0);

      // 2. 排程延保提醒 (针对保修类型)
      if (sub.recordType === 'warranty' && sub.extendedWarranties) {
        try {
          const extendedWarranties = JSON.parse(sub.extendedWarranties) as ExtendedWarrantyItem[];
          for (let i = 0; i < extendedWarranties.length; i++) {
            const item = extendedWarranties[i];
            // 仅在子项开启了提醒时排程，但时刻完全跟随主设置 (reminderDays, hour, minute)
            if (item.date && item.isReminderEnabled) {
              await this.publishSpecificReminder(sub, item.date, item.name || '延伸保修', 'warranty_extended', reminderDays, hour, minute, i + 1);
            }
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Failed to parse extendedWarranties for reminder: ${(e as Error).message}`);
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to schedule reminders for ${sub.name}: ${(err as BusinessError).message}`);
    }
  }

  private async publishSpecificReminder(sub: SubscriptionModel, date: number, name: string, type: string, daysBefore: number, hour: number, minute: number, index: number): Promise<void> {
    const targetDate: Date = new Date(date);
    targetDate.setDate(targetDate.getDate() - daysBefore);
    targetDate.setHours(hour, minute, 0, 0);

    if (targetDate.getTime() < Date.now()) {
      hilog.info(DOMAIN, TAG, `Reminder time passed for ${name}, skipping.`);
      return;
    }

    const dateTime: reminderAgentManager.LocalDateTime = {
      year: targetDate.getFullYear(),
      month: targetDate.getMonth() + 1,
      day: targetDate.getDate(),
      hour: targetDate.getHours(),
      minute: targetDate.getMinutes()
    };

    const currencyStr = sub.currency === 'USD' ? '$' : '¥';
    let title = '订阅到期提醒';
    let content = `您的订阅 ${sub.name} 即将到期 (${currencyStr}${sub.price})`;

    if (sub.recordType === 'groupBuy') {
      title = '团购券过期提醒';
      content = `您的团购券 ${sub.name} 即将过期`;
    } else if (sub.recordType === 'warranty') {
      if (type === 'warranty_extended') {
        title = '延保服务到期提醒';
        content = `您的 ${sub.name} 附加延保项目 [${name}] 即将到期`;
      } else {
        title = '保修到期提醒';
        content = `您的 ${sub.name} 保修即将到期`;
      }
    }

    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      notificationId: (sub.id ?? 0) * 100 + index, // 为每个子项分配唯一 ID
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: title,
      content: content,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION, // 使用社交类型以获得更高优先级
      wantAgent: {
        pkgName: 'com.xxtstudio.accountDL',
        abilityName: 'EntryAbility'
      },
      ringDuration: 0,
      actionButton: [
        {
          title: '关闭',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }
      ]
    };

    const reminderId: number = await reminderAgentManager.publishReminder(reminder);
    if (sub.id) {
      await this.saveReminderId(sub.id, reminderId);
    }
  }

  /**
   * 取消提醒
   * @param subId 订阅ID
   */
  public async cancelReminder(subId: number): Promise<void> {
    const reminderIds: number[] = await this.getReminderIds(subId);
    if (reminderIds.length > 0) {
      for (const rId of reminderIds) {
        try {
          await reminderAgentManager.cancelReminder(rId);
          hilog.info(DOMAIN, TAG, `Cancelled reminder reminderId=${rId}`);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, `Failed to cancel reminder ${rId}: ${(e as BusinessError).message}`);
        }
      }
      await this.removeReminderId(subId);
    }
  }

  // --- 辅助方法 ---

  private async getReminderIds(subId: number): Promise<number[]> {
    return await PreferenceUtil.getInstance().getReminderIds(subId);
  }

  private async saveReminderId(subId: number, reminderId: number): Promise<void> {
    await PreferenceUtil.getInstance().saveReminderId(subId, reminderId);
  }

  private async removeReminderId(subId: number): Promise<void> {
    await PreferenceUtil.getInstance().removeReminderId(subId);
  }

  /**
   * 检查通知权限
   */
  public async isNotificationEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      return false;
    }
  }

  /**
   * 批量重同步提醒
   */
  public async resyncReminders(subs: SubscriptionModel[]): Promise<void> {
    const isEnabled: boolean = await this.isNotificationEnabled();
    if (!isEnabled) return;
    
    for (const sub of subs) {
      await this.scheduleReminder(sub);
    }
    await this.scheduleNewYearReminder(false);
  }

  /**
   * 预约新年提醒
   */
  public async scheduleNewYearReminder(forceRequest: boolean = false): Promise<boolean> {
    const isEnabled: boolean = await this.isNotificationEnabled();
    if (!isEnabled && forceRequest) {
      const rawContext: common.Context | null = PreferenceUtil.getInstance().getContext();
      if (rawContext) {
        const context: common.UIAbilityContext = rawContext as common.UIAbilityContext;
        try {
          // 优先尝试拉起系统请求授权弹窗 (API 9+)
          await notificationManager.requestEnableNotification(context);
          // 再次检查权限
          if (await this.isNotificationEnabled()) {
             // 授权成功，发送全局事件
             GlobalBus.publish(EVENT_NOTIFY_PERMISSION_GRANTED);
          } else {
             // 用户可能取消了，或者需要去设置页（对于某些特殊情况）
             await notificationManager.openNotificationSettings(context);
          }
        } catch (err) {
          hilog.error(DOMAIN, TAG, `Failed to request permission or open settings: ${(err as BusinessError).message}`);
        }
      }
      return false;
    }

    if (!isEnabled) return false;

    const targetDate: Date = new Date('2026-02-17T00:00:00');
    if (targetDate.getTime() < Date.now()) return false;

    const dateTime: reminderAgentManager.LocalDateTime = {
      year: targetDate.getFullYear(),
      month: targetDate.getMonth() + 1,
      day: targetDate.getDate(),
      hour: 0,
      minute: 0
    };

    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: '新年快乐！🧨',
      content: '爆竹声中一岁除，春风送暖入屠苏。2026农历新年到了，记得订阅祝您万事如意！',
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      wantAgent: {
        pkgName: 'com.xxtstudio.accountDL',
        abilityName: 'EntryAbility'
      },
      ringDuration: 0,
      actionButton: [
        {
          title: '2026新年快乐！',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }
      ]
    };

    try {
      await this.cancelNewYearReminder();
      const rId: number = await reminderAgentManager.publishReminder(reminder);
      await PreferenceUtil.getInstance().put(LocalNotificationManager.KEY_NEW_YEAR_REMINDER_ID, rId);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed New Year reminder: ${(err as BusinessError).message}`);
      return false;
    }
  }

  public async cancelNewYearReminder(): Promise<void> {
    const rId: number = await PreferenceUtil.getInstance().get(LocalNotificationManager.KEY_NEW_YEAR_REMINDER_ID, -1) as number;
    if (rId !== -1) {
      try {
        await reminderAgentManager.cancelReminder(rId);
      } catch (e) {}
      await PreferenceUtil.getInstance().put(LocalNotificationManager.KEY_NEW_YEAR_REMINDER_ID, -1);
    }
  }

  public async isNewYearReminderSet(): Promise<boolean> {
    const rId: number = await PreferenceUtil.getInstance().get(LocalNotificationManager.KEY_NEW_YEAR_REMINDER_ID, -1) as number;
    return rId !== -1;
  }

  /**
   * 取消所有订阅相关的系统提醒（通常在登出时调用）
   * @param subs 需要取消提醒的订阅列表
   */
  public async cancelAllReminders(subs: SubscriptionModel[]): Promise<void> {
    hilog.info(DOMAIN, TAG, `Cancelling all reminders for ${subs.length} subscriptions`);
    
    // 1. 取消常规订阅提醒
    for (const sub of subs) {
      if (sub.id !== undefined) {
        const rIds = await PreferenceUtil.getInstance().getReminderIds(sub.id);
        if (rIds.length > 0) {
          for (const rId of rIds) {
            try {
              await reminderAgentManager.cancelReminder(rId);
              hilog.info(DOMAIN, TAG, `Cancelled reminder ${rId} for sub ${sub.id}`);
            } catch (e) {
              hilog.error(DOMAIN, TAG, `Failed to cancel reminder ${rId} for sub ${sub.id}: ${(e as BusinessError).message}`);
            }
          }
          await PreferenceUtil.getInstance().removeReminderId(sub.id);
        }
      }
    }

    // 2. 取消新年提醒
    await this.cancelNewYearReminder();
    hilog.info(DOMAIN, TAG, 'All system reminders cleared during logout');
  }

  /**
   * 启动时自检并修复失效的提醒
   */
  public async selfCheckReminders(): Promise<void> {
    const isEnabled: boolean = await this.isNotificationEnabled();
    if (!isEnabled) {
      hilog.info(DOMAIN, TAG, 'Notification disabled, skipping self-check');
      return;
    }

    try {
      // 1. 获取系统当前所有生效的闹钟
      const activeReminders = await reminderAgentManager.getAllValidReminders() as Object as ReminderBasicInfo[];
      const activeIds = activeReminders.map((r: ReminderBasicInfo): number => r.notificationId);
      hilog.info(DOMAIN, TAG, `Starting self-check, ${activeIds.length} active reminders found in system`);

      // 2. 获取数据库中所有开启了提醒的订阅项
      const subs = await SubscriptionRepository.getInstance().queryAll();

      for (const sub of subs) {
        if (!sub.id || sub.isDeleted || sub.reminderDaysBefore === undefined || sub.reminderDaysBefore === null) continue;

        // 3. 检查主提醒是否存在
        const mainId = (sub.id ?? 0) * 100 + 0;
        if (!activeIds.includes(mainId)) {
          hilog.warn(DOMAIN, TAG, `Main reminder for ${sub.name} (ID: ${mainId}) missing, repairing...`);
          await this.scheduleReminder(sub);
          continue; // scheduleReminder 会处理延保，修复后跳过该 sub 的后续检查
        }

        // 4. 检查延保提醒
        if (sub.recordType === 'warranty' && sub.extendedWarranties) {
          try {
            const extendedWarranties = JSON.parse(sub.extendedWarranties) as ExtendedWarrantyItem[];
            for (let i = 0; i < extendedWarranties.length; i++) {
              // 仅当开启了独立提醒时才需要检查
              if (extendedWarranties[i].date && extendedWarranties[i].isReminderEnabled) {
                const extId = (sub.id ?? 0) * 100 + (i + 1);
                if (!activeIds.includes(extId)) {
                  hilog.warn(DOMAIN, TAG, `Extended reminder ${i + 1} for ${sub.name} (ID: ${extId}) missing, repairing...`);
                  await this.scheduleReminder(sub);
                  break; // 只要缺一项就重排整个记录的提醒
                }
              }
            }
          } catch (e) {
            // ignore parse error
          }
        }
      }
      hilog.info(DOMAIN, TAG, 'Reminder self-check completed');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Reminder self-check failed: ${(err as BusinessError).message}`);
    }
  }
}
