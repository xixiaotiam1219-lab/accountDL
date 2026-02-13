export class DateUtil {
  /**
   * 格式化日期为 YYYY-MM-DD
   */
  static formatDate(date: Date | number): string {
    const d = typeof date === 'number' ? new Date(date) : date;
    const year = d.getFullYear();
    const month = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * 格式化日期为 YY-MM-DD
   */
  static formatShortDate(date: Date | number): string {
    const d = typeof date === 'number' ? new Date(date) : date;
    const year = d.getFullYear().toString().slice(-2);
    const month = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * 计算下一个扣款日（修复当天计算bug）
   * 如果当前时间已经过了今天的扣款时间点，且就是今天扣款，可能需要特殊处理
   * 这里简单地比较日期部分
   */
  static isSameDay(date1: Date, date2: Date): boolean {
    return date1.getFullYear() === date2.getFullYear() &&
           date1.getMonth() === date2.getMonth() &&
           date1.getDate() === date2.getDate();
  }

  /**
   * 计算从今天到目标日期的天数差
   * 忽略时分秒，只比较日期
   */
  static getDaysUntil(targetDate: number | Date): number {
    const now = new Date();
    // 重置 now 为当天的 00:00:00
    now.setHours(0, 0, 0, 0);

    const target = typeof targetDate === 'number' ? new Date(targetDate) : targetDate;
    // 重置 target 为当天的 00:00:00
    const targetDay = new Date(target);
    targetDay.setHours(0, 0, 0, 0);
    
    const diffTime = targetDay.getTime() - now.getTime();
    return Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  }

  /**
   * 判断两个日期是否在同一个月
   */
  static isSameMonth(date1: Date, date2: Date): boolean {
    return date1.getFullYear() === date2.getFullYear() &&
           date1.getMonth() === date2.getMonth();
  }

  /**
   * 获取是一年中的第几天 (0-365)
   */
  static getDayOfYear(date: Date): number {
    const start = new Date(date.getFullYear(), 0, 0);
    const diff = date.getTime() - start.getTime();
    const oneDay = 1000 * 60 * 60 * 24;
    return Math.floor(diff / oneDay) - 1; // 0-indexed
  }
  /*
   * 获取某个月份的天数
   * month: 0-11
   */
  static getDaysInMonth(year: number, month: number): number {
    return new Date(year, month + 1, 0).getDate();
  }

  /**
   * 安全地减去月份 (避免 3-31 减 1 月变成 3-03 的问题)
   */
  static safeSubtractMonth(date: Date, months: number): Date {
    const d = new Date(date);
    const targetMonth = d.getMonth() - months;
    const yearDiff = Math.floor(targetMonth / 12);
    // JS Date constructor handles negative months automatically
    // but the day overflow is the issue.
    // We should first set to the 1st of the target month
    const tempDate = new Date(d.getFullYear(), targetMonth, 1);
    const daysInTargetMonth = DateUtil.getDaysInMonth(tempDate.getFullYear(), tempDate.getMonth());
    
    // Clamp the day
    const originalDay = d.getDate();
    const newDay = Math.min(originalDay, daysInTargetMonth);
    
    tempDate.setDate(newDay);
    // Keep original time if needed (though we usually care about date only)
    tempDate.setHours(d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
    
    return tempDate;
  }

  /**
   * 安全地减击年份 (避免 2-29 减 1 年变成 3-01 的问题)
   */
  static safeSubtractYear(date: Date, years: number): Date {
     const d = new Date(date);
     const targetYear = d.getFullYear() - years;
     const month = d.getMonth();
     
     // Check leap year case: Feb 29 -> Feb 28
     if (month === 1 && d.getDate() === 29) {
        if (!((targetYear % 4 === 0 && targetYear % 100 !== 0) || targetYear % 400 === 0)) {
           // Target is not leap year
           d.setFullYear(targetYear);
           d.setDate(28);
           return d;
        }
     }
     d.setFullYear(targetYear);
     return d;
  }

  /**
   * 安全地增加月份 (避免 1-31 加 1 月变成 3-03 的问题)
   */
  static safeAddMonth(date: Date, months: number): Date {
    const d = new Date(date);
    const targetMonth = d.getMonth() + months;
    // JS Date automatically handles month overflow/underflow
    const tempDate = new Date(d.getFullYear(), targetMonth, 1);
    const daysInTargetMonth = DateUtil.getDaysInMonth(tempDate.getFullYear(), tempDate.getMonth());
    
    const originalDay = d.getDate();
    const newDay = Math.min(originalDay, daysInTargetMonth);
    
    tempDate.setDate(newDay);
    tempDate.setHours(d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
    
    return tempDate;
  }

  /**
   * 安全地增加年份 (避免 2-29 加 1 年变成 3-01 的问题)
   */
  static safeAddYear(date: Date, years: number): Date {
     const d = new Date(date);
     const targetYear = d.getFullYear() + years;
     
     // Check leap year case: Feb 29 -> Feb 28
     if (d.getMonth() === 1 && d.getDate() === 29) {
        const isLeap = (targetYear % 4 === 0 && targetYear % 100 !== 0) || (targetYear % 400 === 0);
        if (!isLeap) {
           d.setFullYear(targetYear);
           d.setMonth(1);
           d.setDate(28);
           return d;
        }
     }
     d.setFullYear(targetYear);
     return d;
  }
}
