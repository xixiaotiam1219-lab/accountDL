/**
 * 会员服务识别配置库
 * 针对不同的会员服务定制识别规则
 */
import { WARRANTY_ICON_MAP } from '../view/WarrantyCategorySheet';
export interface MemberServiceConfig {
  // 服务名称（用于匹配）
  name: string;
  // 别名列表
  aliases?: string[];
  // 图标（首字母或 emoji）
  icon?: string;
  // 价格识别规则
  pricePatterns?: RegExp[];
  // 续费价格关键词
  renewKeywords?: string[];
  // 特惠价格关键词（用于过滤）
  discountKeywords?: string[];
  // 默认价格（如果 OCR 未识别到价格时的兜底）
  defaultPrice?: number;
  // 固定周期（如京东PLUS只有年付）
  fixedBillingCycle?: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
  // 所属分类
  category?: string;
  // 二级分类
  subCategory?: string;
  // 可选的二级分类列表（用于 UI 下拉选择）
  validSubCategories?: string[];
}



/**
 * 会员服务配置库
 * 你可以根据测试结果添加更多服务的配置
 */
export const MEMBER_SERVICES: MemberServiceConfig[] = [
  // ===== 华为生态 =====
  {
    name: '华为运动健康',
    aliases: ['活力人生会员', '尊享守护服务', '华为运动健康', 'Health+'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务',
    validSubCategories: ['活力人生会员', '尊享守护服务']
  },
  {
    name: '华为阅读',
    aliases: ['阅读会员', '听书会员', '阅读尊享VIP'],
    renewKeywords: ['自动续费', '连续包月'],
    discountKeywords: [],
    category: '社交职场',
    validSubCategories: ['阅读会员', '听书会员']
  },
  // ===== 视频类 =====
  {
    name: '腾讯视频',
    aliases: ['腾讯视频会员', '腾讯视频', '腾讯视频VIP', '腾讯VIP', '微视', '云视听极光'],
     renewKeywords: ['自动续费', '续费'],
    discountKeywords: ['特惠', '首'],
    category: '影视会员',
    validSubCategories: ['VIP', 'SVIP','腾讯体育VIP']
  },
  {
    name: '爱奇艺',
    aliases: ['爱奇艺VIP', '爱奇艺会员', '白金VIP', '黄金VIP', '星钻VIP', 'IQIYI'],
     renewKeywords: ['自动续费', '续费'],
    discountKeywords: ['特惠', '首'],
    category: '影视会员',
    validSubCategories: ['黄金VIP', '白金VIP', '星钻VIP']
  },
  {
    name: '优酷视频',
    aliases: ['优酷会员', '优酷视频', '酷喵', '优酷'],
    renewKeywords: ['自动续费', '续费'],
    discountKeywords: ['特惠', '首'],
    category: '影视会员',
    validSubCategories: ['VIP会员', 'SVIP会员'],

  },
  {
    name: '芒果TV',
    aliases: ['芒果会员','芒果TV'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '影视会员'
  },
  {
    name: '哔哩哔哩',
    aliases: ['Bilibili', '哔哩哔哩', '年度大会员', '大会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['首'],
    category: '影视会员'
  },
  {
    name: '华为视频',
    aliases: ['华为影视会员', '华为视频'],
    renewKeywords: ['次月起续费', '自动续费'],
    discountKeywords: [],
    category: '影视会员',
    validSubCategories: ['影视会员', '全屏影视SVIP','超钻会员']
  },
  {
    name: '主题',
    aliases: ['主题会员', '内容畅享', '精选福利', '尊贵标识', '表盘会员', '华为表盘会员'],
     renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务',
    validSubCategories: ['主题会员', '表盘会员']
  },


  // ===== 音乐类 =====
  {
    name: '华为音乐',
    aliases: ['超钻会员', '超级音乐会员', '空间音频', '超高清音频', '智慧屏', '华为音乐'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '音乐音频',
    validSubCategories: ['超级音乐会员', '超钻会员']
  },
  {
    name: 'QQ音乐',
    aliases: ['QQ音乐', 'QQ Music', '绿钻', 'QQ音乐会员', '豪华绿钻'],
    renewKeywords: ['续费', '到期自动续费'],
    discountKeywords: ['升级'],
    category: '音乐音频',
    validSubCategories: ['豪华绿钻', '超级会员','听书会员']
  },
  {
    name: '网易云音乐',
    aliases: ['网易云VIP', '黑胶会员', '黑胶VIP', '黑胶SVIP'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '音乐音频',
    validSubCategories: ['黑胶VIP', '黑胶SVIP', '畅听会员']
  },
  {
    name: 'Spotify',
    aliases: ['Spotify Premium'],
    renewKeywords: [],
    discountKeywords: [],
    category: '音乐音频'
  },
  {
    name: '酷狗音乐',
    aliases: ['酷狗VIP', '酷狗会员', '豪华VIP', '超级VIP'],
   renewKeywords: ['自动续费'],
    discountKeywords: ['立省', '代金券'],
    category: '音乐音频',
    validSubCategories: ['豪华VIP', '超级VIP']
  },

  {
    name: '酷我音乐',
    aliases: ['酷我会员', '豪华会员', '超级会员', '车载会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['立省'],
    category: '音乐音频',
    validSubCategories: ['豪华会员', '超级会员', '车载会员', '听书会员']
  },
  // ===== 云存储类 =====
  {
    name: '百度网盘',
    aliases: ['百度网盘', '百度网盘会员', '度盘'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠', '首', '极速下载'],
    category: '云盘存储',
    validSubCategories: ['VIP', 'SVIP','空间扩容','SVIP10']
  },
  {
    name: '阿里云盘',
    aliases: ['阿里云盘会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '云盘存储'
  },
  {
    name: 'QQ',
    aliases: ['QQ超级会员', 'QQ会员', '超级会员', 'QQ VIP'],
     renewKeywords: ['续费'],
    discountKeywords: ['特惠', '首开'],
    category: '社交职场',
    validSubCategories: ['QQ会员', 'QQ超级会员', 'QQ大会员']
  },
  {
    name: 'iCloud',
    aliases: ['iCloud+', 'Apple'],
    renewKeywords: [],
    discountKeywords: [],
    category: '云盘存储'
  },
  {
    name: '云空间会员',
    aliases: ['华为云空间', '云空间会员', 'Cloud Space', '云空间'],

    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '云盘存储'
  },

  // ===== 生产力类 =====
  {
    name: 'WPS Office',
    aliases: ['WPS会员', 'WPS超级会员'],

    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '效率办公'
  },
  {
    name: 'Notion',
    aliases: ['Notion Plus', 'Notion Pro'],
    renewKeywords: [],
    discountKeywords: [],
    category: '效率办公'
  },

  // ===== AI 类 =====
  {
    name: 'ChatGPT',
    aliases: ['ChatGPT Plus', 'OpenAI'],
    renewKeywords: [],
    discountKeywords: [],
    category: '效率办公'
  },

  // ===== 电商类 =====
  {
    name: '京东',
    aliases: ['京东会员', 'PLUS会员','PLUS年卡'],

    renewKeywords: ['自动续费'],
    discountKeywords: ['首'],
    defaultPrice: 99,
    fixedBillingCycle: 'Yearly',
    category: '电商购物',
    validSubCategories: ['PLUS会员']
  },
  {
    name: '淘宝',
    aliases: ['88VIP', '淘宝会员'],
    renewKeywords: [],
    discountKeywords: [],
    defaultPrice: 88,
    fixedBillingCycle: 'Yearly',
    category: '电商购物',
    validSubCategories: ['88VIP生活卡','88VIP购物卡']
  },

  // ===== 其他 =====
  {
    name: 'Netflix',
    aliases: ['Netflix Premium'],
    renewKeywords: [],
    discountKeywords: [],
    category: '影视会员'
  },
  {
    name: 'Disney+',
    aliases: ['Disney Plus'],
    renewKeywords: [],
    discountKeywords: [],
    category: '影视会员'
  },
  {
    name: 'YouTube',
    aliases: ['YouTube Premium', 'YouTube Music'],
    renewKeywords: [],
    discountKeywords: [],
    category: '影视会员'
  },
  {
    name: '知乎',
    aliases: ['知乎盐选', '知乎会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '社交职场'
  },
  {
    name: '微信读书',
    aliases: ['微信读书会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '社交职场'
  },
  {
    name: 'Keep',
    aliases: ['Keep会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '生活服务'
  },
  {
    name: '微博',
    aliases: ['微博会员', '微博VIP', 'Weibo', '微博之夜'],
    renewKeywords: ['续费'],
    discountKeywords: ['特惠'],
    category: '社交职场'
  },
  {
    name: '山姆会员商店',
    aliases: ['山姆会员', 'Sams Club', 'Sams', '山姆', '卓越会员', '普通会员'],
    renewKeywords: ['续费', '自动续费'],
    discountKeywords: ['券', '礼包', '亲友卡'], // 将 '新人入会券' 相关作为过滤词
    defaultPrice: 260,
    fixedBillingCycle: 'Yearly',
    category: '电商购物',
    validSubCategories: ['普通会员','卓越会员']
  },
  // ===== 华为全家桶 (Petal One) =====
  {
    name: 'Petal One 畅享套餐',
    aliases: ['Petal One', '畅享套餐'],
    // icon: 'resource:petalone',
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务'
  },
  {
    name: 'Petal One 悦享套餐',
    aliases: ['悦享套餐'],
    // icon: 'resource:petalone',
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务'
  },
  {
    name: 'Petal One 尊享套餐',
    aliases: ['尊享套餐'],
    // icon: 'resource:petalone',
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务'
  },
  
  // ===== 团购外卖类 =====
  {
    name: '美团',
    aliases: ['美团外卖', '美团跑腿', '神券', '美团神券', '膨胀', '美团会员'],
    icon: 'resource:meituan_logo',
    renewKeywords: [],
    discountKeywords: [],
    category: '生活服务'
  },
  {
    name: '朴朴超市',
    aliases: ['朴朴', '朴朴超市', '免费菜', '天天0元领'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '电商购物'
  },

  // ===== 音频/播客类 =====
  {
    name: '喜马拉雅',
    aliases: ['喜马拉雅会员', '喜马拉雅VIP', '喜马拉雅FM'],
    renewKeywords: ['自动续费', '续费'],
    discountKeywords: ['特惠', '首月'],
    category: '音乐音频'
  },
  {
    name: '蜻蜓FM',
    aliases: ['蜻蜓FM会员', '蜻蜓会员', '蜻蜓超级会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '音乐音频'
  },
  {
    name: '荔枝FM',
    aliases: ['荔枝FM会员', '荔枝会员', '荔枝VIP'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '音乐音频'
  },
  {
    name: '汽水音乐',
    aliases: ['汽水音乐会员', '汽水VIP'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '音乐音频'
  },

  // ===== 电商/外卖类 =====
  {
    name: '拼多多',
    aliases: ['拼多多省钱月卡', '省钱月卡', '拼多多会员', '月卡会员'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '电商购物',
    validSubCategories: ['省钱月卡']
  },
  {
    name: '淘宝闪购',
    aliases: ['淘宝闪购超级会员', '淘宝闪购会员', '超级吃货卡'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '生活服务',
    validSubCategories: ['超级吃货卡']
  },

  // ===== 云盘/效率类 =====
  {
    name: '夸克',
    aliases: ['夸克网盘会员', '夸克会员', '夸克VIP', '网盘VIP', '网盘SVIP', '扫描王'],
    renewKeywords: ['自动续费'],
    discountKeywords: ['特惠'],
    category: '云盘存储',
    validSubCategories: ['网盘VIP', '网盘SVIP']
  },
  {
    name: '剪映',
    aliases: ['剪映会员', '剪映专业版', '剪映VIP'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '效率办公'
  },
  {
    name: '粉笔',
    aliases: ['粉笔会员', '粉笔教育', '粉笔公考'],
    renewKeywords: ['自动续费'],
    discountKeywords: [],
    category: '效率办公',
    validSubCategories: ['VIP 会员', 'SVIP 会员', '行测会员']
  },
  // ===== 支付/金融类 =====
  {
    name: '抖音支付',
    aliases: ['抖音', '抖支付', '抖音月付'],
    icon: 'resource:douyin_logo',
    category: '生活服务'
  }
];

/**
 * 根据关键词搜索会员服务
 * 返回名称或别名中包含关键词的服务列表（最多返回5个）
 */
export function searchMemberServices(keyword: string): MemberServiceConfig[] {
  if (!keyword || keyword.length === 0) return [];
  
  const lowerKeyword = keyword.toLowerCase();
  const results: MemberServiceConfig[] = [];
  
  for (const service of MEMBER_SERVICES) {
    // 检查名称是否匹配
    if (service.name.toLowerCase().includes(lowerKeyword)) {
      results.push(service);
      continue;
    }
    // 检查别名是否匹配
    if (service.aliases) {
      for (const alias of service.aliases) {
        if (alias.toLowerCase().includes(lowerKeyword)) {
          results.push(service);
          break;
        }
      }
    }
  }
  
  return results.slice(0, 5); // 最多返回5个结果
}

/**
 * 根据文本匹配会员服务
 * 算法优化：引入权重机制，品牌名匹配 > 别名匹配
 */
export function matchMemberService(text: string): MemberServiceConfig | undefined {
  const lowerText = text.toLowerCase();
  
  let bestMatch: MemberServiceConfig | undefined = undefined;
  let maxScore = -1;
  let minIndex = Number.MAX_VALUE;
  
  // 0. 酷我音乐签名匹配 (豪华+超级+车载+车端音效)
  if (lowerText.includes('豪华会员') && lowerText.includes('超级会员') && 
      (lowerText.includes('车载会员') || lowerText.includes('车端音效'))) {
    const kuwo = MEMBER_SERVICES.find(s => s.name === '酷我音乐');
    if (kuwo) return kuwo;
  }

  // 0.1 协议优先策略 (User Suggestion: 支付即同意XXXX)
  // 如果能从《XXX协议》中提取到服务名，这是最准确的
  const agreementPattern = /《([^》]+)》/g;
  let match: RegExpExecArray | null;
  while ((match = agreementPattern.exec(text)) !== null) {
    const agreementName = match[1];
    for (const service of MEMBER_SERVICES) {
      if (agreementName.includes(service.name)) return service;
      if (service.aliases) {
        for (const alias of service.aliases) {
          if (agreementName.includes(alias) && alias.length >= 2) return service;
        }
      }
    }
  }
  
  // 0.1 兜底协议检测（无书名号的情况）
  const noBracketPattern = /支付即同意\s*([^\s,]+?)\s*(?:相关)?协议/g;
  while ((match = noBracketPattern.exec(text)) !== null) {
     const candidate = match[1];
     for (const service of MEMBER_SERVICES) {
       if (candidate.includes(service.name) || (service.aliases && service.aliases.some(a => candidate.includes(a)))) {
         return service;
       }
     }
  }

  for (const service of MEMBER_SERVICES) {
    let currentScore = -1;
    let currentIndex = Number.MAX_VALUE;

    // 1. 检查主名称 (最高权重: 100)
    let nameIndex = lowerText.indexOf(service.name.toLowerCase());
    while (nameIndex !== -1) {
      // 检查上下文：跳过包含"已过期"、"对比"、"权益"的行（这些通常是状态或广告对比）
      const lineStart = text.lastIndexOf('\n', nameIndex) + 1;
      let lineEnd = text.indexOf('\n', nameIndex);
      if (lineEnd === -1) lineEnd = text.length;
      const lineContent = text.substring(lineStart, lineEnd);
      
      if (!lineContent.includes('已过期') && !lineContent.includes('对比')) {
        break; // 找到有效匹配
      }
      // 继续找下一个
      nameIndex = lowerText.indexOf(service.name.toLowerCase(), nameIndex + 1);
    }

    if (nameIndex !== -1) {
      // 检查上下文：跳过包含"已过期"、"对比"、"权益"的行（这些通常是状态或广告对比）
      const lineStart = text.lastIndexOf('\n', nameIndex) + 1;
      let lineEnd = text.indexOf('\n', nameIndex);
      if (lineEnd === -1) lineEnd = text.length;
      const lineContent = text.substring(lineStart, lineEnd);
      
      // 检查是否为福利/广告/赠品 (如：爱奇艺1元，领爱奇艺，立省...)
      const benefitMarkers = ['1元', '领', '送', '含', '券', '礼包', '补贴', '0元', '立省', '代金券', '会员日'];
      // 检查是否为账号说明/登录提示 (如：QQ与微信账号不互通，用微信登录，账号说明...)
      const accountMarkers = ['账号', '登录', '不互通', '互通', '说明', '切换'];
      
      const isBenefit = benefitMarkers.some(m => lineContent.includes(m));
      const isAccountInfo = accountMarkers.some(m => lineContent.includes(m));
      
      if (nameIndex !== -1) {
        // 品牌名权重：基础 100
        // 如果是福利/广告/赠品，分值降低 (降至 20)
        // 如果是账号说明/登录提示，分值大幅降低 (降至 10)，防止 QQ音乐 等应用顶部提示背景账号时误判
        const prefix = text.charAt(nameIndex - 1);
        const isGiftPrefix = ['赠', '送', '含', 'x', 'X', '+', '&'].includes(prefix);
        
        if (isAccountInfo) {
          currentScore = 10;
        } else if (isGiftPrefix || isBenefit) {
          currentScore = 20;
        } else {
          currentScore = 100;
        }
        currentIndex = nameIndex;
      }
    }
    
    // 2. 检查别名
    if (service.aliases) {
      for (const alias of service.aliases) {
        let aliasIndex = lowerText.indexOf(alias.toLowerCase());
        while (aliasIndex !== -1) {
           const lineStart = text.lastIndexOf('\n', aliasIndex) + 1;
           let lineEnd = text.indexOf('\n', aliasIndex);
           if (lineEnd === -1) lineEnd = text.length;
           const lineContent = text.substring(lineStart, lineEnd);
           
           if (!lineContent.includes('已过期') && !lineContent.includes('对比')) {
             break;
           }
           aliasIndex = lowerText.indexOf(alias.toLowerCase(), aliasIndex + 1);
        }

        if (aliasIndex !== -1) {
          // 获取行内容进行福利/账号检测
          const lineStart = text.lastIndexOf('\n', aliasIndex) + 1;
          let lineEnd = text.indexOf('\n', aliasIndex);
          if (lineEnd === -1) lineEnd = text.length;
          const lineContent = text.substring(lineStart, lineEnd);
          const benefitMarkers = ['1元', '抢', '券', '礼包', '补贴', '0元', '会员日'];
          const accountMarkers = ['账号', '登录', '互通', '不互通'];
          
          const isBenefit = benefitMarkers.some(m => lineContent.includes(m));
          const isAccount = accountMarkers.some(m => lineContent.includes(m));

          // 别名权重逻辑：
          // - 长度越长，权重越高
          // - 核心别名提升权重，使其能对抗普通的品牌名匹配
          const aliasLower = alias.toLowerCase();
          const isGeneric = ['vip', 'svip', '会员'].includes(aliasLower);
          const isCoreAlias = ['plus', '大会员', '黑胶', '盐选', '绿钻', '豪华绿钻', '超级会员'].includes(aliasLower);
          
          let aliasScore = isGeneric ? 10 : 30 + (alias.length * 2);
          if (isCoreAlias) aliasScore += 80; // 提升核心别名加分 (从 60 提到 80)
          
          if (aliasIndex > 0) {
            const prefix = text.charAt(aliasIndex - 1);
            if (['赠', '送', '含', 'x', 'X', '+', '&'].includes(prefix) || isBenefit || isAccount) {
              aliasScore /= 2;
            }
          }

          // 如果新得分更高，或者得分相同但位置更靠前，则采用
          if (aliasScore > currentScore || (aliasScore === currentScore && aliasIndex < currentIndex)) {
            currentScore = aliasScore;
            currentIndex = aliasIndex;
          }
        }
      }
    }
    
    // 3. 位置权重 (关键): 位于顶部的匹配项 (Header) 获得巨大加分
    // 这解决了 "黑胶VIP"(Alias at top) vs "爱奇艺"(Name at bottom, joint ad) 的问题
    if (currentIndex < 200 && currentScore > 0) {
      currentScore += 500;
      
      // 越靠前分越高 (Micro adjustment)
      currentScore += (200 - currentIndex);
    }

    // 全局比较：选择得分最高的。如果得分相同，选择位置最靠前的
    if (currentScore > maxScore) {
      maxScore = currentScore;
      minIndex = currentIndex;
      bestMatch = service;
    } else if (currentScore === maxScore && currentIndex < minIndex && currentScore !== -1) {
      minIndex = currentIndex;
      bestMatch = service;
    }
  }
  
  return bestMatch;
}

/**
 * 根据物品名称推断保修分类
 */
export function matchWarrantyCategory(name: string): string {
  if (!name) return '其他物品';
  
  const lowerName = name.toLowerCase();
  
  const mapping: Record<string, string[]> = {
    '电子产品': ['手机', '平板', '电脑', '笔记本', '耳机', '相机', 'iphone', 'ipad', 'mac', 'watch', '手表', 'vr', 'tws', '耳机盒'],
    '家用电器': ['冰箱', '洗衣机', '空调', '电视', '显示器', '微波炉', '洗碗机', '抽油烟机', '风扇', '电饭煲', '吹风机', '空气炸锅', '净化器', '扫地机'],
    '数码配件': ['移动电源', '数据线', '充电器', '鼠标', '键盘', '显卡', '内存', '硬盘', '路由器', '充电宝', '手写笔', '云台'],
    '家居生活': ['沙发', '柜', '桌', '灯', '净水器', '吸尘器', '扫地机', '滤芯'],
    '运动户外': ['自行车', '鞋', '包', '滑板', '帐篷'],
    '办公用品': ['打印机', '投影仪', '墨盒'],
  };

  const categories = Object.keys(mapping);
  for (const category of categories) {
    if (mapping[category].some(keyword => lowerName.includes(keyword))) {
      return category;
    }
  }

  return '其他物品';
}


/**
 * 本地图标资源映射表
 */
const ICON_MAP: Record<string, Resource> = {
  // 'petalone': $r("app.media.petalone"),
  'meituan_logo': $rawfile('icons/美团.png'),
  'douyin_logo': $rawfile('icons/抖音.png'),
  'dianping_logo': $rawfile('icons/大众点评.png')
};

/**
 * 解析图标
 * 如果是 resource: 开头，从映射表读取
 * 否则直接返回（emoji或url）
 */
export function resolveIcon(icon: string): Resource | string {
  if (icon && icon.startsWith('resource:')) {
    const key = icon.split(':')[1];
    return ICON_MAP[key] || icon;
  }
  
  if (icon && icon.startsWith('warranty_icon:')) {
    const name = icon.split(':')[1];
    return WARRANTY_ICON_MAP[name] || icon;
  }

  return icon;
}

/**
 * 获取服务图标
 */
export function getServiceIcon(serviceName: string): string {
  const service = MEMBER_SERVICES.find(s => 
    s.name === serviceName || 
    (s.aliases && s.aliases.includes(serviceName))
  );
  return service?.icon || serviceName.charAt(0).toUpperCase();
}
