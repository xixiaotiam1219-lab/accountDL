import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { common } from '@kit.AbilityKit';
import { GlobalBus, EVENT_NOTIFY_PERMISSION_GRANTED } from '../utils/GlobalBus';

const TAG = 'LocalNotificationManager';
const DOMAIN = 0x0000;

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

    const targetDate: Date = new Date(sub.nextBillingDate);
    targetDate.setDate(targetDate.getDate() - reminderDays);
    targetDate.setHours(hour, minute, 0, 0);

    if (targetDate.getTime() < Date.now()) {
      hilog.info(DOMAIN, TAG, `Reminder time passed for ${sub.name}, skipping.`);
      return;
    }

    const dateTime: reminderAgentManager.LocalDateTime = {
      year: targetDate.getFullYear(),
      month: targetDate.getMonth() + 1,
      day: targetDate.getDate(),
      hour: targetDate.getHours(),
      minute: targetDate.getMinutes()
    };

    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: sub.recordType === 'groupBuy' ? '团购券过期提醒' : (sub.recordType === 'warranty' ? '保修到期提醒' : '订阅到期提醒'),
      content: sub.recordType === 'groupBuy' ? `您的团购券 ${sub.name} 即将过期` : (sub.recordType === 'warranty' ? `您的 ${sub.name} 保修即将到期` : `您的订阅 ${sub.name} 即将到期 (${sub.currency} ${sub.price})`),
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      wantAgent: {
        pkgName: 'com.xxtstudio.accountDL',
        abilityName: 'EntryAbility'
      },
      ringDuration: 5,
      actionButton: [
        {
          title: '关闭',
          type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE
        }
      ]
    };

    try {
      if (sub.id) {
        await this.cancelReminder(sub.id);
      }

      const isEnabled: boolean = await this.isNotificationEnabled();
      if (!isEnabled) return;

      const reminderId: number = await reminderAgentManager.publishReminder(reminder);
      hilog.info(DOMAIN, TAG, `Published reminder for ${sub.name}, reminderId=${reminderId}`);

      if (sub.id) {
        await this.saveReminderId(sub.id, reminderId);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to publish reminder: ${(err as BusinessError).message}`);
    }
  }

  /**
   * 取消提醒
   * @param subId 订阅ID
   */
  public async cancelReminder(subId: number): Promise<void> {
    const reminderId: number = await this.getReminderId(subId);
    if (reminderId !== -1) {
      try {
        await reminderAgentManager.cancelReminder(reminderId);
        hilog.info(DOMAIN, TAG, `Cancelled reminder from cache reminderId=${reminderId}`);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `Failed to cancel cached reminder: ${(e as BusinessError).message}`);
      }
      await this.removeReminderId(subId);
    }
  }

  // --- 辅助方法 ---

  private async getReminderId(subId: number): Promise<number> {
    return await PreferenceUtil.getInstance().getReminderId(subId);
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
      slotType: notificationManager.SlotType.SERVICE_INFORMATION,
      wantAgent: {
        pkgName: 'com.xxtstudio.accountDL',
        abilityName: 'EntryAbility'
      },
      ringDuration: 5,
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
}
