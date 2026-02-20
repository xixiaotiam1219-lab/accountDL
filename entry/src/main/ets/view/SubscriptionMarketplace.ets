import { curves, LengthMetrics } from '@kit.ArkUI';
import { hdsEffect, hdsMaterial, HdsNavDestination, HdsNavigationMenuItemOptions, HdsNavigationTitleBarOptions, HdsNavigationTitleBarStyle, ScrollEffectType } from '@kit.UIDesignKit';
import { SubscriptionIcon } from './SubscriptionIcon';
import { BackgroundWatermark } from './BackgroundWatermark';
import { LocalIconManager, AppInfo } from '../utils/LocalIconManager';
import { deviceInfo } from '@kit.BasicServicesKit';

@Builder
export function SubscriptionMarketplaceBuilder() {
  SubscriptionMarketplace()
}

// === 市场模板数据结构 ===
interface MarketplaceItem {
  name: string;
  icon: string; // 运行时由 LocalIconManager 填充
  category: string;
  subCategory?: string;
  defaultCycle?: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
  keywords?: string[]; // 支持拼音、缩写等模糊搜索
}

interface CategoryGroup {
  title: string;
  icon: Resource;
  items: MarketplaceItem[];
}

// === 导航参数类 ===
class AddSubscriptionNavParams {
  initialType: string = 'subscription';
  marketplaceName: string = '';
  marketplaceIcon: string = '';
  marketplaceCategory: string = '';
  marketplaceSubCategory: string = '';
  marketplaceCycle: string = '';
}

// =========================================================================================
// 推荐数据 — 综合 MemberServiceConfig + app_data.json + 常见知名订阅服务
// 同一个应用的多个会员等级拆分为独立条目，方便用户直接选择
// =========================================================================================
const MARKETPLACE_DATA: CategoryGroup[] = [ // ─────────────────────────── 星河联盟 ───────────────────────────
  {
    title: '星河联盟',
    icon: $r('app.media.xhlm'),
    items: [
      { name: '一日记账', icon: '', category: '记账', defaultCycle: 'Monthly' },
      { name: '桔子账本', icon: '', category: '记账', defaultCycle: 'Monthly' },
      { name: 'MeoW', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '便单', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '像素匠', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '奇妙工具箱', icon: '', category: '实用工具', defaultCycle: 'Lifetime' },
      { name: '快手笔', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '悦览', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '指令魔方', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '每日咖啡', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '流舟', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '溏心音乐', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '灵动小组件', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '素算计算器', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '设备信息', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '轻倒数', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
      { name: '轻木鱼', icon: '', category: '实用工具', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 影视会员 ───────────────────────────
  {
    title: '影视会员',
    icon: $r('sys.symbol.play_circle'),
    items: [
      // 爱奇艺 — 3 个等级
      { name: '爱奇艺', icon: '', category: '影视会员', subCategory: '黄金VIP', defaultCycle: 'Monthly', keywords: ['aiqiyi', 'aqy'] },
      { name: '爱奇艺', icon: '', category: '影视会员', subCategory: '白金VIP', defaultCycle: 'Monthly', keywords: ['aiqiyi', 'aqy'] },
      { name: '爱奇艺', icon: '', category: '影视会员', subCategory: '星钻VIP', defaultCycle: 'Monthly', keywords: ['aiqiyi', 'aqy'] },
      // 腾讯视频 — 3 个等级
      { name: '腾讯视频', icon: '', category: '影视会员', subCategory: 'VIP', defaultCycle: 'Monthly', keywords: ['tengxun', 'tx', 'qqvideo'] },
      { name: '腾讯视频', icon: '', category: '影视会员', subCategory: 'SVIP', defaultCycle: 'Monthly', keywords: ['tengxun', 'tx', 'qqvideo'] },
      { name: '腾讯视频', icon: '', category: '影视会员', subCategory: '腾讯体育VIP', defaultCycle: 'Monthly', keywords: ['tengxun', 'tx', 'qqvideo'] },
      // 优酷视频 — 2 个等级
      { name: '优酷视频', icon: '', category: '影视会员', subCategory: 'VIP会员', defaultCycle: 'Monthly', keywords: ['youku', 'yk'] },
      { name: '优酷视频', icon: '', category: '影视会员', subCategory: 'SVIP会员', defaultCycle: 'Monthly', keywords: ['youku', 'yk'] },
      // 芒果TV
      { name: '芒果TV', icon: '', category: '影视会员', defaultCycle: 'Monthly', keywords: ['mangguo', 'mgtv', 'mg'] },
      // 哔哩哔哩
      { name: '哔哩哔哩', icon: '', category: '影视会员', subCategory: '大会员', defaultCycle: 'Monthly', keywords: ['bilibili', 'bzl', 'blbl'] },
      // 华为视频 — 3 个等级
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '影视会员', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '全屏影视SVIP', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '超钻会员', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      // 海外
      { name: 'Netflix', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'Disney+', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'YouTube', icon: '', category: '影视会员', subCategory: 'Premium', defaultCycle: 'Monthly', keywords: ['youtub', 'ytb'] },
      // 短视频平台
      { name: '抖音', icon: '', category: '影视会员', defaultCycle: 'Monthly', keywords: ['douyin', 'dy', 'tiktok'] },
      { name: '快手', icon: '', category: '影视会员', defaultCycle: 'Monthly', keywords: ['kuaishou', 'ks'] },
    ]
  },

  // ─────────────────────────── 音乐音频 ───────────────────────────
  {
    title: '音乐音频',
    icon: $r('sys.symbol.music'),
    items: [
      // Spotify
      { name: 'Spotify', icon: '', category: '音乐音频', subCategory: 'Premium', defaultCycle: 'Monthly' },
      // QQ音乐 — 3 个等级
      { name: 'QQ音乐', icon: '', category: '音乐音频', subCategory: '豪华绿钻', defaultCycle: 'Monthly', keywords: ['qqmusic', 'qqyinyue'] },
      { name: 'QQ音乐', icon: '', category: '音乐音频', subCategory: '超级会员', defaultCycle: 'Monthly', keywords: ['qqmusic', 'qqyinyue'] },
      { name: 'QQ音乐', icon: '', category: '音乐音频', subCategory: '听书会员', defaultCycle: 'Monthly', keywords: ['qqmusic', 'qqyinyue'] },
      // 网易云音乐 — 3 个等级
      { name: '网易云音乐', icon: '', category: '音乐音频', subCategory: '黑胶VIP', defaultCycle: 'Monthly', keywords: ['wangyiyun', 'wyy', '163', 'netease'] },
      { name: '网易云音乐', icon: '', category: '音乐音频', subCategory: '黑胶SVIP', defaultCycle: 'Monthly', keywords: ['wangyiyun', 'wyy', '163', 'netease'] },
      { name: '网易云音乐', icon: '', category: '音乐音频', subCategory: '畅听会员', defaultCycle: 'Monthly', keywords: ['wangyiyun', 'wyy', '163', 'netease'] },
      // 华为音乐 — 2 个等级
      { name: '华为音乐', icon: '', category: '音乐音频', subCategory: '超级音乐会员', defaultCycle: 'Monthly', keywords: ['huaweiyinyue', 'hw'] },
      { name: '华为音乐', icon: '', category: '音乐音频', subCategory: '超钻会员', defaultCycle: 'Monthly', keywords: ['huaweiyinyue', 'hw'] },
      // 酷狗音乐 — 2 个等级
      { name: '酷狗音乐', icon: '', category: '音乐音频', subCategory: '豪华VIP', defaultCycle: 'Monthly', keywords: ['kugou', 'kg'] },
      { name: '酷狗音乐', icon: '', category: '音乐音频', subCategory: '超级VIP', defaultCycle: 'Monthly', keywords: ['kugou', 'kg'] },
      // 酷我音乐 — 4 个等级
      { name: '酷我音乐', icon: '', category: '音乐音频', subCategory: '豪华会员', defaultCycle: 'Monthly', keywords: ['kuwo', 'kw'] },
      { name: '酷我音乐', icon: '', category: '音乐音频', subCategory: '超级会员', defaultCycle: 'Monthly', keywords: ['kuwo', 'kw'] },
      { name: '酷我音乐', icon: '', category: '音乐音频', subCategory: '车载会员', defaultCycle: 'Monthly', keywords: ['kuwo', 'kw'] },
      { name: '酷我音乐', icon: '', category: '音乐音频', subCategory: '听书会员', defaultCycle: 'Monthly', keywords: ['kuwo', 'kw'] },
      // 其他音频
      { name: '喜马拉雅', icon: '', category: '音乐音频', defaultCycle: 'Monthly', keywords: ['ximalaya', 'xml'] },
      { name: '蜻蜓FM', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      { name: '荔枝FM', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      { name: '汽水音乐', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      { name: '多多音乐', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      { name: '番茄畅听', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 效率办公 ───────────────────────────
  {
    title: '效率办公',
    icon: $r('sys.symbol.doc_text'),
    items: [
      { name: 'WPS Office', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Notion', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'ChatGPT', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: '剪映', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      // 粉笔 — 3 个等级
      { name: '粉笔', icon: '', category: '效率办公', subCategory: 'VIP 会员', defaultCycle: 'Monthly' },
      { name: '粉笔', icon: '', category: '效率办公', subCategory: 'SVIP 会员', defaultCycle: 'Monthly' },
      { name: '粉笔', icon: '', category: '效率办公', subCategory: '行测会员', defaultCycle: 'Monthly' },
      { name: '钉钉', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: '天眼查', icon: '', category: '效率办公', defaultCycle: 'Yearly' },
      { name: '百度文库', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 云盘存储 ───────────────────────────
  {
    title: '云盘存储',
    icon: $r('sys.symbol.cloud'),
    items: [
      { name: 'iCloud', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
      // 百度网盘 — 4 个等级
      { name: '百度网盘', icon: '', category: '云盘存储', subCategory: 'VIP', defaultCycle: 'Monthly', keywords: ['baiduwangpan', 'bdwp', 'pan'] },
      { name: '百度网盘', icon: '', category: '云盘存储', subCategory: 'SVIP', defaultCycle: 'Monthly', keywords: ['baiduwangpan', 'bdwp', 'pan'] },
      { name: '百度网盘', icon: '', category: '云盘存储', subCategory: 'SVIP10', defaultCycle: 'Monthly', keywords: ['baiduwangpan', 'bdwp', 'pan'] },
      { name: '百度网盘', icon: '', category: '云盘存储', subCategory: '空间扩容', defaultCycle: 'Monthly', keywords: ['baiduwangpan', 'bdwp', 'pan'] },
      { name: '阿里云盘', icon: '', category: '云盘存储', defaultCycle: 'Monthly', keywords: ['aliyunpan', 'yunpan'] },
      // 夸克 — 2 个等级
      { name: '夸克', icon: '', category: '云盘存储', subCategory: '网盘VIP', defaultCycle: 'Monthly', keywords: ['kuake', 'quark', 'kk'] },
      { name: '夸克', icon: '', category: '云盘存储', subCategory: '网盘SVIP', defaultCycle: 'Monthly', keywords: ['kuake', 'quark', 'kk'] },
      { name: '云空间会员', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 社交职场 ───────────────────────────
  {
    title: '社交职场',
    icon: $r('sys.symbol.message'),
    items: [
      // QQ — 3 个等级
      { name: 'QQ', icon: '', category: '社交职场', subCategory: 'QQ会员', defaultCycle: 'Monthly', keywords: ['tencent', 'tx'] },
      { name: 'QQ', icon: '', category: '社交职场', subCategory: 'QQ超级会员', defaultCycle: 'Monthly', keywords: ['tencent', 'tx'] },
      { name: 'QQ', icon: '', category: '社交职场', subCategory: 'QQ大会员', defaultCycle: 'Monthly', keywords: ['tencent', 'tx'] },
      { name: '微博', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['weibo', 'wb', 'sina'] },
      { name: '知乎', icon: '', category: '社交职场', subCategory: '盐选会员', defaultCycle: 'Monthly', keywords: ['zhihu', 'zh', 'yanxuan'] },
      { name: '微信读书', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['weixindushu', 'wxds', 'weread'] },
      // 华为阅读 — 2 个等级
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '阅读会员', defaultCycle: 'Monthly' },
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '听书会员', defaultCycle: 'Monthly' },
      { name: '小红书', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['xiaohongshu', 'xhs', 'red'] },
      { name: 'MOMO陌陌', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['momo', 'mm'] },
      { name: '探探', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['tantan', 'tt'] },
      { name: '百度贴吧', icon: '', category: '社交职场', defaultCycle: 'Monthly', keywords: ['baidutieba', 'tieba', 'tb'] },
    ]
  },

  // ─────────────────────────── 生活服务 ───────────────────────────
  {
    title: '生活服务',
    icon: $r('sys.symbol.house'),
    items: [
      { name: '美团', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['meituan', 'mt'] },
      { name: '淘宝闪购', icon: '', category: '生活服务', subCategory: '超级吃货卡', defaultCycle: 'Monthly' },
      { name: 'Keep', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['keep', 'kp'] },
      // 华为运动健康 — 2 个等级
      { name: '华为运动健康', icon: '', category: '生活服务', subCategory: '活力人生会员', defaultCycle: 'Monthly' },
      { name: '华为运动健康', icon: '', category: '生活服务', subCategory: '尊享守护服务', defaultCycle: 'Monthly' },
      // 主题 — 2 个等级
      { name: '主题', icon: '', category: '生活服务', subCategory: '主题会员', defaultCycle: 'Monthly' },
      { name: '主题', icon: '', category: '生活服务', subCategory: '表盘会员', defaultCycle: 'Monthly' },
      { name: '大众点评', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['dazhongdianping', 'dzdp'] },
      { name: '美团外卖', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['meituanwaimai', 'mtwm', 'waimai'] },
      { name: '华为生活服务', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['huawei', 'hw'] },
      { name: '滴滴出行', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['didichuxing', 'dd'] },
      { name: '高德地图', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['gaodeditu', 'amap', 'gd'] },
      { name: '哈啰', icon: '', category: '生活服务', defaultCycle: 'Monthly', keywords: ['haluo', 'hl'] },
    ]
  },

  // ─────────────────────────── 电商购物 ───────────────────────────
  {
    title: '电商购物',
    icon: $r('sys.symbol.bag'),
    items: [
      { name: '京东', icon: '', category: '电商购物', subCategory: 'PLUS会员', defaultCycle: 'Yearly', keywords: ['jingdong', 'jd'] },
      // 淘宝 — 2 个等级
      { name: '淘宝', icon: '', category: '电商购物', subCategory: '88VIP生活卡', defaultCycle: 'Yearly', keywords: ['taobao', 'tb', '88vip'] },
      { name: '淘宝', icon: '', category: '电商购物', subCategory: '88VIP购物卡', defaultCycle: 'Yearly', keywords: ['taobao', 'tb', '88vip'] },
      { name: '拼多多', icon: '', category: '电商购物', subCategory: '省钱月卡', defaultCycle: 'Monthly', keywords: ['pinduoduo', 'pdd'] },
      // 山姆会员商店 — 2 个等级
      { name: '山姆会员商店', icon: '', category: '电商购物', subCategory: '普通会员', defaultCycle: 'Yearly', keywords: ['shanmu', 'sams'] },
      { name: '山姆会员商店', icon: '', category: '电商购物', subCategory: '卓越会员', defaultCycle: 'Yearly', keywords: ['shanmu', 'sams'] },
      { name: '朴朴超市', icon: '', category: '电商购物', defaultCycle: 'Monthly', keywords: ['pupu', 'pp'] },
      { name: '唯品会', icon: '', category: '电商购物', defaultCycle: 'Monthly', keywords: ['weipinhui', 'wph'] },
      { name: '闲鱼', icon: '', category: '电商购物', defaultCycle: 'Monthly', keywords: ['xianyu', 'xy'] },
      { name: '抖音商城', icon: '', category: '电商购物', defaultCycle: 'Monthly', keywords: ['douyin', 'dy', 'tiktok'] },
      { name: '华为商城', icon: '', category: '电商购物', defaultCycle: 'Monthly', keywords: ['huaweishangcheng', 'vmall', 'hw'] },
    ]
  },

  // ─────────────────────────── 华为生态 ───────────────────────────
  {
    title: '华为生态',
    icon: $r('sys.symbol.star'),
    items: [
      // Petal One — 3 档套餐
      { name: 'Petal One 畅享套餐', icon: '', category: '生活服务', defaultCycle: 'Monthly' },
      { name: 'Petal One 悦享套餐', icon: '', category: '生活服务', defaultCycle: 'Monthly' },
      { name: 'Petal One 尊享套餐', icon: '', category: '生活服务', defaultCycle: 'Monthly' },
      // 华为视频
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '影视会员', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '全屏影视SVIP', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      { name: '华为视频', icon: '', category: '影视会员', subCategory: '超钻会员', defaultCycle: 'Monthly', keywords: ['huaweishipin', 'hw'] },
      // 华为音乐
      { name: '华为音乐', icon: '', category: '音乐音频', subCategory: '超级音乐会员', defaultCycle: 'Monthly', keywords: ['huaweiyinyue', 'hw'] },
      { name: '华为音乐', icon: '', category: '音乐音频', subCategory: '超钻会员', defaultCycle: 'Monthly', keywords: ['huaweiyinyue', 'hw'] },
      // 华为阅读
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '阅读会员', defaultCycle: 'Monthly', keywords: ['huaweiyuedu', 'hw'] },
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '听书会员', defaultCycle: 'Monthly', keywords: ['huaweiyuedu', 'hw'] },
      // 华为运动健康
      { name: '华为运动健康', icon: '', category: '生活服务', subCategory: '活力人生会员', defaultCycle: 'Monthly', keywords: ['huaweiyundongjiankang', 'hw'] },
      { name: '华为运动健康', icon: '', category: '生活服务', subCategory: '尊享守护服务', defaultCycle: 'Monthly', keywords: ['huaweiyundongjiankang', 'hw'] },
      // 主题
      { name: '主题', icon: '', category: '生活服务', subCategory: '主题会员', defaultCycle: 'Monthly' },
      { name: '主题', icon: '', category: '生活服务', subCategory: '表盘会员', defaultCycle: 'Monthly' },
      // 云空间
      { name: '云空间会员', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 阅读教育 ───────────────────────────
  {
    title: '阅读教育',
    icon: $r('sys.symbol.book'),
    items: [
      { name: '微信读书', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '阅读会员', defaultCycle: 'Monthly' },
      { name: '华为阅读', icon: '', category: '社交职场', subCategory: '听书会员', defaultCycle: 'Monthly' },
      { name: '知乎', icon: '', category: '社交职场', subCategory: '盐选会员', defaultCycle: 'Monthly' },
      // { name: '得到', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
      { name: '百度文库', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'QQ阅读', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
      { name: '番茄免费小说', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
      { name: '哔哩哔哩漫画', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
      { name: '粉笔', icon: '', category: '效率办公', subCategory: 'VIP 会员', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 金融理财 ───────────────────────────
  {
    title: '金融理财',
    icon: $r('sys.symbol.creditcard'),
    items: [
      { name: '支付宝', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '云闪付', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '招商银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '中国工商银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '中国建设银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '中国银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '中国农业银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '邮储银行', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
      { name: '京东金融', icon: '', category: '金融理财', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── Google 全家桶 ───────────────────────────
  {
    title: 'Google 全家桶',
    icon: $r('sys.symbol.wifi'),
    items: [
      { name: 'Google One', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
      { name: 'YouTube', icon: '', category: '影视会员', subCategory: 'Premium', defaultCycle: 'Monthly' },
      { name: 'YouTube', icon: '', category: '影视会员', subCategory: 'Music', defaultCycle: 'Monthly' },
      { name: 'YouTube', icon: '', category: '影视会员', subCategory: 'TV', defaultCycle: 'Monthly' },
      // { name: 'Google Workspace', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      // { name: 'Google Play Pass', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── Apple 全家桶 ───────────────────────────
  {
    title: 'Apple 全家桶',
    icon: $r('sys.symbol.grid'),
    items: [
      { name: 'Apple One', icon: '', category: '生活服务', subCategory: '个人', defaultCycle: 'Monthly' },
      { name: 'Apple One', icon: '', category: '生活服务', subCategory: '家庭', defaultCycle: 'Monthly' },
      { name: 'Apple Music', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      { name: 'Apple TV+', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      // { name: 'Apple Arcade', icon: '', category: '游戏订阅', defaultCycle: 'Monthly' },
      { name: 'iCloud', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
      // { name: 'Apple News+', icon: '', category: '社交职场', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 微软 / Adobe ───────────────────────────
  {
    title: '微软 / Adobe',
    icon: $r('sys.symbol.display'),
    items: [
      { name: 'Microsoft 365', icon: '', category: '效率办公', subCategory: '个人版', defaultCycle: 'Monthly' },
      { name: 'Microsoft 365', icon: '', category: '效率办公', subCategory: '家庭版', defaultCycle: 'Yearly' },
      { name: 'OneDrive', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
      { name: 'Microsoft Copilot', icon: '', category: '效率办公',  subCategory: 'Pro',defaultCycle: 'Monthly' },
      { name: 'Adobe Creative Cloud', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Adobe Photoshop', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Adobe Premiere Pro', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      // { name: 'Dropbox', icon: '', category: '云盘存储', defaultCycle: 'Monthly' },
      { name: 'Canva', icon: '', category: '效率办公', subCategory: 'Pro',defaultCycle: 'Monthly' },
      { name: 'Figma', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────────── 游戏订阅 ───────────────────────────
  {
    title: '游戏订阅',
    icon: $r('sys.symbol.gamecontroller'),
    items: [
      { name: 'Xbox Game Pass', icon: '', category: '游戏订阅', subCategory: 'Core', defaultCycle: 'Monthly' },
      { name: 'Xbox Game Pass', icon: '', category: '游戏订阅', subCategory: 'Ultimate', defaultCycle: 'Monthly' },
      { name: 'PlayStation Plus', icon: '', category: '游戏订阅', subCategory: 'Essential', defaultCycle: 'Monthly' },
      { name: 'PlayStation Plus', icon: '', category: '游戏订阅', subCategory: 'Extra', defaultCycle: 'Monthly' },
      { name: 'PlayStation Plus', icon: '', category: '游戏订阅', subCategory: 'Premium', defaultCycle: 'Monthly' },
      // { name: 'Nintendo Switch Online', icon: '', category: '游戏订阅', defaultCycle: 'Yearly' },
      { name: 'EA Play', icon: '', category: '游戏订阅', defaultCycle: 'Monthly' },
      // { name: 'Apple Arcade', icon: '', category: '游戏订阅', defaultCycle: 'Monthly' },
      { name: 'Steam', icon: '', category: '游戏订阅', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────── AI / 开发者工具 ─────────────────────────
  {
    title: 'AI / 开发者',
    icon: $r('sys.symbol.sun'),
    items: [
      { name: 'ChatGPT', icon: '', category: '效率办公', subCategory: 'Plus', defaultCycle: 'Monthly' },
      { name: 'ChatGPT', icon: '', category: '效率办公', subCategory: 'Pro', defaultCycle: 'Monthly' },
      { name: 'Claude', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Google Gemini', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Journey AI', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'GitHub Copilot', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'Cursor', icon: '', category: '效率办公', subCategory: 'Pro',defaultCycle: 'Monthly' },
      { name: 'Grammarly', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: 'DeepSeek', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
      { name: '1Password', icon: '', category: '效率办公', defaultCycle: 'Monthly' },
    ]
  },

  // ─────────────────────── 海外流媒体 ─────────────────────────
  {
    title: '海外流媒体',
    icon: $r('sys.symbol.play_circle'),
    items: [
      { name: 'Netflix', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'Disney+', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      // { name: 'HBO Max', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'Amazon Prime Video', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      // { name: 'Amazon Prime', icon: '', category: '电商购物', defaultCycle: 'Monthly' },
      // { name: 'Hulu', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      // { name: 'Paramount+', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      // { name: 'Peacock', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'Apple TV+', icon: '', category: '影视会员', defaultCycle: 'Monthly' },
      { name: 'Spotify', icon: '', category: '音乐音频', subCategory: 'Premium', defaultCycle: 'Monthly' },
      { name: 'Apple Music', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
      // { name: 'Tidal', icon: '', category: '音乐音频', defaultCycle: 'Monthly' },
    ]
  },
];

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct SubscriptionMarketplace {
  @Consume('pageStack') pageStack: NavPathStack;

  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageLink('collapseSide') collapseSide: 'left' | 'right' = 'right';
  @StorageLink('isTabBarCollapsed') isTabBarCollapsed: boolean = false;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @State searchKeyword: string = '';
  @State selectedCategoryIndex: number = -1; // -1 = 全部
  @State animStep1: boolean = false;
  @State animStep2: boolean = false;
  // 运行时从图标库加载的图标映射：serviceName → file:// URI
  @State iconMap: Record<string, string> = {};

  // Floating Search Button State
  private scroller: Scroller = new Scroller();
  @State showFloatingButton: boolean = false;
  @State isFabPressed: boolean = false;
  @State fabLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State showSearchOverlay: boolean = false;
  @State pressedItemName: string = ''; // 记录当前按下的项目名称
  @State isScrolled: boolean = false;
  // @State pressedItemName: string = ''; // 记录当前按下的项目名称

  async aboutToAppear() {
    // 初始化图标库并加载所有市场项目的图标
    await LocalIconManager.getInstance().init(getContext(this));
    await this.loadIcons();
    this.triggerAnimations();
  }

  /**
   * 从 LocalIconManager 加载所有市场项目的图标
   * 使用去重集合避免重复查询（同一应用多个等级共享图标）
   */
  async loadIcons() {
    const iconManager = LocalIconManager.getInstance();
    const newMap: Record<string, string> = {};
    const queried = new Set<string>();

    for (const group of MARKETPLACE_DATA) {
      for (const item of group.items) {
        if (queried.has(item.name)) continue;
        queried.add(item.name);
        const appInfo = await iconManager.getAppInfo(item.name);
        if (appInfo && appInfo.icon) {
          newMap[item.name] = appInfo.icon;
        }
      }
    }
    this.iconMap = newMap;
  }

  /**
   * 获取某个服务的图标（从已加载的 iconMap 取）
   */
  getResolvedIcon(name: string): string {
    return this.iconMap[name] || '';
  }

  triggerAnimations() {
    if (this.isAnimationEnabled) {
      const resp = this.animationResponse;
      const damp = this.animationDamping;
      const duration = this.animationDuration;
      setTimeout(() => {
        animateTo({ duration: duration, curve: curves.springMotion(resp, damp) }, () => {
          this.animStep1 = true;
        })
      }, 50);
      setTimeout(() => {
        animateTo({ duration: duration, curve: curves.springMotion(resp, damp) }, () => {
          this.animStep2 = true;
        })
      }, 150);
    } else {
      this.animStep1 = true;
      this.animStep2 = true;
    }
  }

  /**
   * 获取过滤后的数据
   */
  getFilteredData(): CategoryGroup[] {
    let data = MARKETPLACE_DATA;

    // 分类筛选
    if (this.selectedCategoryIndex >= 0 && this.selectedCategoryIndex < data.length) {
      data = [data[this.selectedCategoryIndex]];
    }

    // 搜索筛选
    if (this.searchKeyword.trim()) {
      const keyword = this.searchKeyword.trim().toLowerCase();
      const filtered: CategoryGroup[] = [];
      for (const group of data) {
        const matchedItems = group.items.filter(item => {
          const nameMatch = item.name.toLowerCase().includes(keyword);
          const subCategoryMatch = item.subCategory && item.subCategory.toLowerCase().includes(keyword);
          const keywordMatch = item.keywords && item.keywords.some(k => k.toLowerCase().includes(keyword));
          return nameMatch || subCategoryMatch || keywordMatch;
        });
        if (matchedItems.length > 0) {
          filtered.push({
            title: group.title,
            icon: group.icon,
            items: matchedItems
          } as CategoryGroup);
        }
      }
      return filtered;
    }
    return data;
  }

  /**
   * 点击市场项目 → 跳转到 AddSubscription 并预填数据
   */
  onItemClick(item: MarketplaceItem) {
    const params = new AddSubscriptionNavParams();
    params.initialType = 'subscription';
    params.marketplaceName = item.name;
    // 传递从图标库加载的真实图标路径
    params.marketplaceIcon = this.getResolvedIcon(item.name);
    params.marketplaceCategory = item.category;
    params.marketplaceSubCategory = item.subCategory || '';
    params.marketplaceCycle = item.defaultCycle || '';
    this.pageStack.removeByName('AddSubscription');
    this.pageStack.pushPathByName('AddSubscription', params);
  }

  /**
   * 获取品牌色
   */
  getBrandColor(): ResourceColor {
    if (this.isNewYearTheme) return $r('app.color.new_year_red_start');
    if (this.showVipTheme) return $r('app.color.vip_gold');
    return $r('app.color.brand_color');
  }

  private getCycleText(cycle?: string): string {
    switch (cycle) {
      case 'Monthly': return '月付';
      case 'Quarterly': return '季付';
      case 'Yearly': return '年付';
      case 'Lifetime': return '永久';
      default: return '';
    }
  }

  /**
   * 获取卡片显示名称：有等级显示"服务名 · 等级"，无等级只显示服务名
   */
  private getDisplayName(item: MarketplaceItem): string {
    if (item.subCategory) {
      return `${item.name} · ${item.subCategory}`;
    }
    return item.name;
  }

  @Builder CategoryChip(title: string, index: number) {
    Button() {
      Text(title)
        .fontSize(13)
        .fontWeight(this.selectedCategoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedCategoryIndex === index ?
          (this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
          $r('app.color.text_secondary'))
    }
    .linearGradient(this.selectedCategoryIndex === index ?
      (this.isNewYearTheme ? { angle: 135, colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] } :
        (this.showVipTheme ? { angle: 135, colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] } : undefined)) : undefined)
    .backgroundColor(this.selectedCategoryIndex === index ?
      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
      $r('app.color.card_background'))
    .borderRadius(16)
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
    .onClick(() => {
      animateTo({
        duration: this.isAnimationEnabled ? 200 : 0,
        curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
      }, () => {
        this.selectedCategoryIndex = index;
        this.scroller.scrollToIndex(0, true);
      });
    })
  }

  @Builder MarketItemCard(item: MarketplaceItem) {
    Row() {
      // 图标 — 使用运行时从图标库加载的真实图标
      SubscriptionIcon({
        icon: this.getResolvedIcon(item.name),
        name: item.name,
        iconSize: 44,
        iconRadius: 12
      })
        .margin({ right: 12 })

      // 名称 + 标签
      Column() {
        Text(this.getDisplayName(item))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_title') : (this.showVipTheme ? $r('app.color.sub_card_vip_title') : $r('app.color.text_primary')))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 4 }) {
          Text(item.category)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
          if (item.defaultCycle) {
            Text('·')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
            Text(this.getCycleText(item.defaultCycle))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
        .opacity(0.3)
    }
    .width('100%')
    .padding(14)
    .linearGradient(this.isNewYearTheme ? {
      angle: 135,
      colors: [[$r('app.color.sub_card_ny_start'), 0.0], [$r('app.color.sub_card_ny_end'), 1.0]]
    } : (this.showVipTheme ? {
      angle: 135,
      colors: [[$r('app.color.sub_card_vip_start'), 0.0], [$r('app.color.sub_card_vip_end'), 1.0]]
    } : {
      angle: 0,
      colors: [[ 'rgba(0,0,0,0)', 0.0 ], [ 'rgba(0,0,0,0)', 1.0 ]]
    }))
    .backgroundColor(this.isNewYearTheme || (this.showVipTheme) ? Color.Transparent : $r('app.color.card_bg_enhanced'))
    .borderRadius(16)
    .shadow({
      radius: this.isNewYearTheme || this.showVipTheme ? 15 : 8,
      color: this.isNewYearTheme ? '#1AFF0000' : (this.showVipTheme ? '#1AFFE57F' : '#06000000'),
      offsetY: this.isNewYearTheme || this.showVipTheme ? 6 : 2
    })
    .border({
      width: this.isNewYearTheme || (this.showVipTheme) ? 1 : 0,
      color: this.isNewYearTheme ? 'rgba(255, 0, 0, 0.1)' : (this.showVipTheme ? 'rgba(212, 175, 55, 0.2)' : Color.Transparent)
    })
    .scale({ 
      x: this.pressedItemName === item.name + (item.subCategory || '') ? 0.95 : 1, 
      y: this.pressedItemName === item.name + (item.subCategory || '') ? 0.95 : 1 
    })
    .animation({ 
      duration: this.isAnimationEnabled ? this.animationDuration : 0, 
      curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressedItemName === item.name + (item.subCategory || '') ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .onTouch((event: TouchEvent) => {
      const uniqueName = item.name + (item.subCategory || '');
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.pressedItemName = uniqueName;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedItemName = '';
      }
    })
    .onClick(() => {
      this.onItemClick(item);
    })
  }
@Builder markbuilder(){
  Stack({ alignContent: Alignment.Top }) {
    // 全局背景/水印
    BackgroundWatermark()
      .zIndex(0)

    List({ space: 0, scroller: this.scroller }) {
      // 顶部占位
      ListItem() {
        Column()
          .height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight))
      }


      // 分类筛选 Chips
      ListItem() {
        Scroll() {
          Row({ space: 8 }) {
            this.CategoryChip('全部', -1)
            ForEach(MARKETPLACE_DATA, (group: CategoryGroup, index: number) => {
              this.CategoryChip(group.title, index)
            })
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: 16 })
        .opacity(this.animStep1 ? 1 : 0)
        .translate({ y: this.animStep1 ? 0 : 30 })
      }

      // 内容列表
      if (this.getFilteredData().length === 0) {
        ListItem() {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(48)
              .fontColor([$r('app.color.text_secondary')])
            Text('未找到匹配的服务')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height(200)
          .justifyContent(FlexAlign.Center)
        }
      } else {
        ForEach(this.getFilteredData(), (group: CategoryGroup) => {
          // 分组标题
          ListItem() {
            Row({ space: 8 }) {
              // 根据资源类型选择渲染组件，避免使用 any 转换
              if (group.title === '星河联盟') {
                Image(group.icon)
                  .width(48)
                  .height(18)
                  .fillColor(this.getBrandColor())
                  .objectFit(ImageFit.Contain)
              } else {
                SymbolGlyph(group.icon)
                  .fontSize(18)
                  .fontColor([this.getBrandColor()])
              }
              Text(group.title)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
              .animation({ curve: curves.springMotion(0.6, 0.7) }))
          }

          // 该分组下的项目
          ForEach(group.items, (item: MarketplaceItem) => {
            ListItem() {
              this.MarketItemCard(item)
            }
            .padding({ left: 16, right: 16, bottom: 10 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
              .animation({ curve: curves.springMotion(0.6, 0.7) }))
          }, (item: MarketplaceItem) => `${group.title}_${item.name}_${item.subCategory || 'default'}_${this.selectedCategoryIndex}`)
        }, (group: CategoryGroup) => `${group.title}_${group.items.length}_${this.selectedCategoryIndex}`)
      }

      // 底部提示
      // 底部提示 - 使用 ForEach 强制刷新以避免布局跳动
      ForEach([1], () => {
        ListItem() {
          Column({ space: 12 }) {
            Column({ space: 4 }) {
              Text('没有找到您需要的服务？')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Text('您可以手动添加任意订阅服务')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .opacity(0.7)
            }

            Row() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(24)
                .fontColor([$r('app.color.text_primary')])
            }
            .width(48)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.pageStack.pushPathByName('AddSubscription', new AddSubscriptionNavParams());
            })
          }
          .width('100%')
          .padding({ top: 20, bottom: 80 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
          .animation({ curve: curves.springMotion(0.6, 0.7) }))
      }, (item: number) => `bottom_prompt_${this.selectedCategoryIndex}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(Color.Transparent)
    .opacity(this.animStep2 ? 1 : 0)
    .translate({ y: this.animStep2 ? 0 : 30 })
    .onDidScroll(() => {
      this.isScrolled = this.scroller.currentOffset().yOffset > 5;
    })


    // Search Overlay
    if (this.showSearchOverlay) {
      Stack({ alignContent: Alignment.Top }) {
        // Transparent Background for click capture
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            animateTo({
              duration: this.isAnimationEnabled ? this.animationDuration : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }, () => {
              this.showSearchOverlay = false;
            })
          })
          .transition(TransitionEffect.OPACITY.animation({
            duration: this.isAnimationEnabled ? this.animationDuration : 0,
            curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
              Curve.Linear
          }))

        // Search Bar Area
        Column() {
          // Placeholder for Status Bar + Title Bar to avoid overlap
          Column().height(this.getUIContext().px2vp(this.topRectHeight) + 56)

          Row({ space: 12 }) {
            Search({ placeholder: '搜索服务或会员等级...', value: this.searchKeyword })
              .layoutWeight(1)
              .height(40)
              .searchButton('搜索', {
                fontColor: this.isNewYearTheme ? '#FFD700' :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              })
              .backgroundColor($r('app.color.tag_bg'))
              .onChange((value: string) => {
                this.searchKeyword = value;
                this.scroller.scrollToIndex(0);
              })
              .onSubmit((value: string) => {
                this.searchKeyword = value;
                this.scroller.scrollToIndex(0, true);
                animateTo({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: this.isAnimationEnabled ?
                    curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                }, () => {
                  this.showSearchOverlay = false;
                })
              })

            Text('取消')
              .fontSize(16)
              .fontColor(this.isNewYearTheme ? '#FFD700' :
                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                animateTo({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: this.isAnimationEnabled ?
                    curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                }, () => {
                  this.showSearchOverlay = false;
                })
              })
          }
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 12
          })
          .backgroundColor(this.isScrolled ?
            (this.showVipTheme ? 'rgba(237,194,105,0.15)' : 'rgba(128,128,128,0.1)') :
            (this.showVipTheme ? 'rgba(237,194,105,0.05)' : 'rgba(128,128,128,0.05)')) // Slight tint at top
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN) // Always apply blur for frosted glass effect
          .borderRadius({ bottomLeft: 16, bottomRight: 16 })
          .shadow(this.isScrolled ? { radius: 20, color: 'rgba(0,0,0,0.1)', offsetY: 4 } : {
            radius: 0,
            color: Color.Transparent,
            offsetY: 0
          })
        }
        .width('100%')
        .transition(TransitionEffect.translate({ y: -100 }).combine(TransitionEffect.OPACITY)
          .animation({
            duration: this.isAnimationEnabled ? this.animationDuration : 0,
            curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
              Curve.Linear
          }))
      }
      .zIndex(200) // Ensure it covers the floating button and list
    }
  }
  .backgroundColor(Color.Transparent)
}
  build() {
    HdsNavDestination() {
      this.markbuilder()
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '推荐服务' },
        menu: {
          value: [
            {
              content: {
                label: '搜索',
                icon: $r('sys.symbol.magnifyingglass'),

                action: (): void => {
                  animateTo({
                    duration: this.isAnimationEnabled ? this.animationDuration : 0,
                    curve: this.isAnimationEnabled ?
                      curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                  }, () => {
                    this.showSearchOverlay = true;
                  })
                }
              }
            } as HdsNavigationMenuItemOptions
          ]
        }
      },
      style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        },
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        }
      }  : undefined
    } as HdsNavigationTitleBarOptions)
    .onBackPressed(() => {
      this.pageStack.pop();
      return true;
    })
  }
}
