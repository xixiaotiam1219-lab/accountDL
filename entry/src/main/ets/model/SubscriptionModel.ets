export interface SubscriptionModel {
  id?: number;
  uuid: string; // 跨设备唯一标识
  name: string;
  price: number;
  currency: string;
  billingCycle: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
  nextBillingDate: number; // Timestamp
  startDate?: number; // 订阅开通日期
  icon?: string; // Path or Resource string
  category?: string; // 消息分类
  lastModified: number; // 最后修改时间
  isDeleted: boolean; // 软删除标记
  reminderDaysBefore?: number; // 提前几天提醒（默认1天）
  reminderTime?: string; // 提醒时间 HH:mm 格式（默认 09:00）
  subCategory?: string; // 二级分类
  isAutoRenewal?: boolean; // 是否自动续费 (默认 true)
  paymentMethod?: string; // 支付方式 (现金, 银行卡, 支付宝等)

  // === 团购券专属字段 ===
  recordType?: 'subscription' | 'groupBuy' | 'warranty'; // 记录类型，默认 subscription
  platform?: 'meituan' | 'douyin' | 'dianping'; // 团购平台
  couponCode?: string; // 团购券码
  usageStatus?: 'unused' | 'used' | 'expired'; // 使用状态
  merchantName?: string; // 商家名称
  quantity?: number; // 券数量
  couponImage?: string; // 券码截图路径
  usageTime?: string; // 使用时间范围 (周一至周日等) - 这是文本描述
  realUsageTime?: number; // 实际核销/使用时间 (Timestamp)

  // === 保修/保质期专属字段 ===
  brand?: string; // 品牌名称
  purchaseChannel?: string; // 购买渠道 (京东、天猫、线下门店等)

  // === 提醒状态控制 ===
  lastIgnoredBillingDate?: number; // 最后一次点击“我知道了”时对应的到期日，用于屏蔽已处理的提醒
}
