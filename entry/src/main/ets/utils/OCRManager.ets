import { common } from '@kit.AbilityKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { matchMemberService } from './MemberServiceConfig';

const TAG = 'OCRManager';

export interface ImageResult {
  pixelMap: image.PixelMap;
  uri: string;
}

export interface OCRResult {
  fullText: string;
  price?: number;           // 推荐价格（续费价格优先）
  monthlyPrice?: number;    // 包月价格
  quarterlyPrice?: number;  // 包季价格
  yearlyPrice?: number;     // 包年价格
  lifetimePrice?: number;   // 永久/买断价格
  date?: number;            // timestamp
  merchantName?: string;    // 商家名称
  couponCode?: string;      // 券码
  platform?: 'meituan' | 'douyin' | 'dianping'; // 平台
  appName?: string;
  serviceIcon?: string;     // 服务图标
  billingCycle?: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite'; // 建议的付费周期
  category?: string;        // 服务分类
  subCategory?: string;     // 二级分类
  usageTime?: string;       // 使用时间范围
}

export interface PriceCandidate {
  price: number;
  unit?: string;
}

export interface PriceContextItem {
  price: number;
  dist: number;
}

export class OCRManager {
  private static instance: OCRManager;
  private context: common.UIAbilityContext | null = null;
  private isInitialized: boolean = false;

  private constructor() {
  }

  public static getInstance(): OCRManager {
    if (!OCRManager.instance) {
      OCRManager.instance = new OCRManager();
    }
    return OCRManager.instance;
  }

  public setContext(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 初始化 OCR 服务
   */
  async init(): Promise<boolean> {
    if (this.isInitialized) {
      return true;
    }
    try {
      const result = await textRecognition.init();
      this.isInitialized = result;
      hilog.info(0x0000, TAG, `OCR service initialization result: ${result}`);
      return result;
    } catch (e) {
      hilog.error(0x0000, TAG, `OCR init failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 释放 OCR 服务
   */
  async release(): Promise<void> {
    if (this.isInitialized) {
      await textRecognition.release();
      this.isInitialized = false;
      hilog.info(0x0000, TAG, 'OCR service released');
    }
  }

  /**
   * 打开图库选择图片
   */
  private openPhoto(): Promise<string> {
    return new Promise<string>((resolve) => {
      let photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      }).then((res: photoAccessHelper.PhotoSelectResult) => {
        resolve(res.photoUris[0] || '');
      }).catch((err: BusinessError) => {
        hilog.error(0x0000, TAG, `Failed to get photo uri. code: ${err.code}, message: ${err.message}`);
        resolve('');
      });
    });
  }

  /**
   * 从 URI 加载图片为 PixelMap
   */
  private async loadImage(uri: string): Promise<image.PixelMap | undefined> {
    try {
      const fileSource = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(fileSource.fd);
      const pixelMap = await imageSource.createPixelMap();
      await fileIo.close(fileSource);
      return pixelMap;
    } catch (e) {
      hilog.error(0x0000, TAG, `Failed to load image: ${JSON.stringify(e)}`);
      return undefined;
    }
  }

  /**
   * 选择图片并返回 PixelMap
   */
  async pickImage(): Promise<image.PixelMap | undefined> {
    const uri = await this.openPhoto();
    if (!uri) {
      return undefined;
    }
    return this.loadImage(uri);
  }

  /**
   * 选择图片并返回 PixelMap 和 URI
   */
  async pickImageWithUri(): Promise<ImageResult | undefined> {
    const uri = await this.openPhoto();
    if (!uri) {
      return undefined;
    }
    const pixelMap = await this.loadImage(uri);
    if (!pixelMap) {
      return undefined;
    }
    return { pixelMap: pixelMap, uri: uri };
  }

  /**
   * 识别图片中的文字
   */
  async recognizeText(pixelMap: image.PixelMap): Promise<string> {
    // 确保服务已初始化
    if (!this.isInitialized) {
      await this.init();
    }

    try {
      const visionInfo: textRecognition.VisionInfo = {
        pixelMap: pixelMap
      };
      const textConfiguration: textRecognition.TextRecognitionConfiguration = {
        isDirectionDetectionSupported: false
      };

      const result = await textRecognition.recognizeText(visionInfo, textConfiguration);
      hilog.info(0x0000, TAG, `OCR succeeded, text length: ${result.value.length}`);
      return result.value;
    } catch (e) {
      const error = e as BusinessError;
      hilog.error(0x0000, TAG, `OCR failed. Code: ${error.code}, message: ${error.message}`);
      return '';
    }
  }

  /**
   * 解析文字提取订阅信息
   */
  parseText(text: string): OCRResult {
    // 输出原始 OCR 文本
    hilog.info(0x0000, TAG, `OCR Raw Text:\n${text}`);
    hilog.info(0x0000, TAG, `OCR Raw Text (escaped): ${JSON.stringify(text)}`);

    let result: OCRResult = { fullText: text };

    // 特殊优化: 美团神券
    if (text.includes('神券天天膨')) {
       result.appName = '美团';
       const config = matchMemberService('美团');
       if (config) {
         result.serviceIcon = config.icon;
         result.category = config.category;
       }
       hilog.info(0x0000, TAG, 'Detected Meituan Coupon, skipping price parsing.');
       this.tryParseDate(result, text);
       return result;
    }

    // 0. 匹配会员服务配置
    const serviceConfig = matchMemberService(text);
    if (serviceConfig) {
      result.serviceIcon = serviceConfig.icon;
      result.appName = serviceConfig.name;
      result.category = serviceConfig.category;
      result.subCategory = serviceConfig.subCategory;
      if (serviceConfig.fixedBillingCycle) {
        result.billingCycle = serviceConfig.fixedBillingCycle;
      }
      
      // 特殊逻辑：华为主题会员细分
      if (result.appName === '华为主题会员') {
         hilog.info(0x0000, TAG, `Checking Theme subCategory in text: ${text.substring(0, 50)}...`);
         if (text.includes('表盘会员')) {
           result.subCategory = '表盘会员';
           hilog.info(0x0000, TAG, 'Set subCategory to 表盘会员');
         } else if (text.includes('主题会员')) {
           result.subCategory = '主题会员';
           hilog.info(0x0000, TAG, 'Set subCategory to 主题会员');
         } else {
           hilog.info(0x0000, TAG, 'No subCategory keywords found for Theme Member');
         }
      }
      
      // 特殊逻辑：酷狗音乐细分
      if (result.appName === '酷狗音乐') {
         if (text.includes('超级VIP') || text.includes('超级会员')) {
           result.subCategory = '超级VIP';
         } else if (text.includes('豪华VIP') || text.includes('豪华会员')) {
           result.subCategory = '豪华VIP';
         }
      }

      // 特殊逻辑：酷我音乐细分
      if (result.appName === '酷我音乐') {
         if (text.includes('车载会员')) {
           result.subCategory = '车载会员';
         } else if (text.includes('听书会员')) {
           result.subCategory = '听书会员';
         } else if (text.includes('超级会员') || text.includes('超级VIP')) {
           result.subCategory = '超级会员';
         } else if (text.includes('豪华会员') || text.includes('豪华VIP')) {
           result.subCategory = '豪华会员';
         }
      }

      // 特殊逻辑：网易云音乐细分
      if (result.appName === '网易云音乐') {
         if (text.includes('黑胶SVIP')) {
           result.subCategory = '黑胶SVIP';
         } else if (text.includes('黑胶VIP')) {
           result.subCategory = '黑胶VIP';
         } else if (text.includes('畅听会员')) {
           result.subCategory = '畅听会员';
         }
      }

      // 特殊逻辑：华为音乐细分
      if (result.appName === '华为音乐会员') {
         if (text.includes('超级音乐会员')) {
           result.subCategory = '超级音乐会员';
         } else if (text.includes('超钻')) {
           result.subCategory = '超钻会员';
         }
      }

      // 特殊逻辑：爱奇艺会员细分
      if (result.appName === '爱奇艺会员') {
         if (text.includes('星钻VIP') || text.includes('星钻')) {
           result.subCategory = '星钻VIP';
         } else if (text.includes('白金VIP') || text.includes('白金')) {
           result.subCategory = '白金VIP';
         } else if (text.includes('黄金VIP') || text.includes('黄金')) {
           result.subCategory = '黄金VIP';
         }
      }

      // 特殊逻辑：华为阅读细分
      if (result.appName === '华为阅读') {
         if (text.includes('阅读会员')) {
           result.subCategory = '阅读会员';
         } else if (text.includes('听书会员')) {
           result.subCategory = '听书会员';
         }
      }

    }

    // 0.5 如果还没识别到名称，尝试从协议中提取
    if (!result.appName) {
      const protocolPattern = /《([^》]+)会员服务?协议》/;
      const protocolMatch = text.match(protocolPattern);
      if (protocolMatch) {
         let extractedName = protocolMatch[1].replace(/会员|服务|协议|自动续费/g, '');
         if (extractedName.length > 0) {
           const config = matchMemberService(extractedName);
           if (config) {
             result.appName = config.name;
             result.serviceIcon = config.icon;
           } else {
             result.appName = extractedName + '会员';
           }
         }
      }
    }

    this.tryParseDate(result, text);

    // 纠错逻辑: 山姆会员商店 vs 朴朴超市
    if (result.appName === '山姆会员商店') {
       if (text.includes('免费菜') || text.includes('天天0元领')) {
         result.appName = '朴朴超市';
         result.serviceIcon = 'resource:pupu';
         hilog.info(0x0000, TAG, 'Corrected Sam to Pupu');
       } 
       else if ((result.monthlyPrice && result.monthlyPrice < 100) || (result.yearlyPrice && result.yearlyPrice < 200)) {
         if (!text.includes('山姆') && !text.includes('Sams') && !text.includes('SAM')) {
            result.appName = '朴朴超市';
            result.serviceIcon = 'resource:pupu';
            hilog.info(0x0000, TAG, 'Corrected Sam to Pupu (Price too low)');
         }
       }
    }

    // 强特征识别
    if (!result.appName) {
      const quarkKeywords = ['网盘', 'AI会员', '扫描王', '小说'];
      const quarkMatchCount = quarkKeywords.filter(kw => text.includes(kw)).length;
      if (quarkMatchCount >= 2) {
        result.appName = '夸克网盘';
        const config = matchMemberService('夸克网盘');
        if (config) {
          result.serviceIcon = config.icon;
          result.category = config.category;
        }
      }
    }

    // 强特征识别 - 百度网盘
    if (!result.appName) {
      const baiduKeywords = ['SVIP', '空间扩容', '极速下载', '倍速', '30T', '5t', '5120G', '不限量下载'];
      const baiduMatchCount = baiduKeywords.filter(kw => text.includes(kw)).length;
      // 只要出现 SVIP，大概率是百度网盘（或其他视频APP），结合“空间”或“下载”等云盘特征词确诊
      // 优化：将 'T' 改为更具体的 '\\dT' 或 '容量' 相关的匹配，防止误判昵称
      const hasCloudKeyword = text.includes('空间') || text.includes('下载') || text.includes('备份') || 
                             text.includes('云') || /[\d.]+T/i.test(text) || /[\d.]+G/i.test(text);
                             
      if (text.includes('SVIP') && hasCloudKeyword) {
         result.appName = '百度网盘';
         const config = matchMemberService('百度网盘');
         if (config) {
           result.serviceIcon = config.icon;
           result.category = config.category;
         }
         hilog.info(0x0000, TAG, 'Inferred App Name: 百度网盘 (from SVIP + Cloud keywords)');
      } 
      else if (baiduMatchCount >= 2) {
         result.appName = '百度网盘';
         const config = matchMemberService('百度网盘');
         if (config) {
           result.serviceIcon = config.icon;
           result.category = config.category;
         }
         hilog.info(0x0000, TAG, 'Inferred App Name: 百度网盘 (from keyword count)');
      }
    }

    if (!result.appName && (text.includes('不回本退差价') || text.includes('未使用全额退') || text.includes('不自动续费'))) {
      if (text.includes('月卡') || text.includes('拼多多')) {
        result.appName = '拼多多';
        const config = matchMemberService('拼多多');
        if (config) {
          result.serviceIcon = config.icon;
          result.category = config.category;
        }
      }
    }

    // 2. 价格识别策略
    const lines = text.split('\n');
    
    // --- 年付识别 pattern ---
    if (!result.yearlyPrice) {
      const yearlyPatterns = [
        new RegExp('(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元?/年'),
        new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?/年\\s*(?:自动)?续费'),
        new RegExp('按年\\s*(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元'),
        new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?\\s*[/每]年'),
        new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?\\s*.*连续包年'),
        new RegExp('连续包年.*?(\\d+(?:\\.\\d{1,2})?)\\s*元?'),
      ];

      for (const line of lines) {
        if (line.includes('省') || line.includes('折')) continue; // 排除 "省50元" 这种干扰

        for (const pattern of yearlyPatterns) {
          const match = line.match(pattern);
          if (match && match[1]) {
            const price = parseFloat(match[1]);
            // 简单校验范围，避免误识别年份 (如 2024)
            if (price > 0 && price < 2000 && price !== 2023 && price !== 2024 && price !== 2025) {
              result.yearlyPrice = price;
              if (!result.billingCycle) result.billingCycle = 'Yearly';
              hilog.info(0x0000, TAG, `Found yearly price: ${price}`);
              break;
            }
          }
        }
        if (result.yearlyPrice) break;
      }
    }

    // --- 季付识别 pattern ---
    if (!result.quarterlyPrice) {
      const quarterlyRenewPatterns = [
        new RegExp('(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元?/季'),
        new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?/季\\s*(?:自动)?续费'),
        new RegExp('按季\\s*(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元'),
        new RegExp('次季续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元'),
        new RegExp('次季\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元'),
        new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?\\s*[/每]季'),
      ];

      for (const line of lines) {
        if (line.includes('升级') || line.includes('超级') || line.includes('超值') || line.includes('省')) continue;

        for (const pattern of quarterlyRenewPatterns) {
          const match = line.match(pattern);
          if (match && match[1]) {
            const quarterPrice = parseFloat(match[1]);
            if (quarterPrice >= 15 && quarterPrice < 300) {
              result.quarterlyPrice = quarterPrice;
              // 如果还没有周期，或者之前识别的是月付（季付优先于推断的月付）
              if (!result.billingCycle) result.billingCycle = 'Quarterly';
              hilog.info(0x0000, TAG, `Found quarterly price: ${quarterPrice}`);
              break;
            }
          }
        }
        if (result.quarterlyPrice) break;
      }
    }

     // --- 月付识别 pattern ---
     if (!result.monthlyPrice) {
       const monthlyPatterns = [
         new RegExp('(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元?/月'),
         new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?/月\\s*(?:自动)?续费'),
         new RegExp('按月\\s*(?:自动)?续费\\s*(\\d+(?:\\.\\d{1,2})?)\\s*元'),
         new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?\\s*[/每]月'),
         new RegExp('(\\d+(?:\\.\\d{1,2})?)\\s*元?\\s*.*连续包月'),
         new RegExp('连续包月.*?(\\d+(?:\\.\\d{1,2})?)\\s*元?'),
       ];
 
       for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          if (line.includes('省') || line.includes('折')) continue;
 
          for (const pattern of monthlyPatterns) {
            const match = line.match(pattern);
            if (match && match[1]) {
              const price = parseFloat(match[1]);
              if (price > 0 && price < 500) {
                result.monthlyPrice = price;
                if (!result.billingCycle) result.billingCycle = 'Monthly';
                hilog.info(0x0000, TAG, `Found monthly price: ${price}`);
                break;
              }
            }
          }
          
          // 特殊逻辑：处理 "1个月" 后面紧跟数字的情况 (Case: Fenbi)
          if (!result.monthlyPrice && (line.includes('1个月') || line.includes('一个月'))) {
             // 寻找接下来的 5 行内是否有数字
             for (let j = 1; j <= 5 && (i + j) < lines.length; j++) {
                const nextLine = lines[i + j].trim();
                const numMatch = nextLine.match(/^(\d+(?:\.\d{1,2})?)$/); // 纯数字行
                if (numMatch) {
                   const price = parseFloat(numMatch[1]);
                   if (price > 1 && price < 100) {
                      result.monthlyPrice = price;
                      if (!result.billingCycle) result.billingCycle = 'Monthly';
                      hilog.info(0x0000, TAG, `Found monthly price by proximity after "1 month": ${price} (from line ${i+j})`);
                      break;
                   }
                }
             }
          }
          if (result.monthlyPrice) break;
       }
     }
    
    // --- 永久/买断识别 ---
    if (!result.lifetimePrice) {
       if (text.includes('永久') || text.includes('终身') || text.includes('买断')) {
          const lifetimePattern = /(\d+(?:\.\d{1,2})?)\s*元/;
          for (const line of lines) {
             if ((line.includes('永久') || line.includes('终身') || line.includes('买断')) && !line.includes('省')) {
                const match = line.match(lifetimePattern);
                if (match && match[1]) {
                   result.lifetimePrice = parseFloat(match[1]);
                   result.billingCycle = 'Lifetime';
                   hilog.info(0x0000, TAG, `Found lifetime price: ${result.lifetimePrice}`);
                   break;
                }
             }
          }
       }
    }
    
    // ... (rest of the logic remains conceptually the same, simplified for brevity but ensuring functionality)
    // 连体价格识别 (如 ¥168¥228)
    const concatPricePattern = /¥(\d+(?:\.\d{1,2})?)¥(\d+(?:\.\d{1,2})?)/;
    const concatMatch = text.match(concatPricePattern);
    if (concatMatch) {
        const price1 = parseFloat(concatMatch[1]);
        const price2 = parseFloat(concatMatch[2]);
        // 通常第一个是现价，第二个是原价
        result.price = price1;
        if (!result.billingCycle) {
           // 辅助判断周期
           if (text.includes('12个月') || text.includes('年')) result.yearlyPrice = price1;
           else if (text.includes('3个月') || text.includes('季')) result.quarterlyPrice = price1;
           else result.monthlyPrice = price1;
        }
        hilog.info(0x0000, TAG, `Detected concatenated price: ${price1} vs ${price2}, picking ${result.price}`);
    }

    if (!result.price) {
        if (result.monthlyPrice) result.price = result.monthlyPrice;
        else if (result.yearlyPrice) result.price = result.yearlyPrice;
    }

    // 4. Default Price & Cycle Fallback (Refined Logic)
    const fallbackConfig = result.appName ? matchMemberService(result.appName) : undefined;
    if (fallbackConfig) {
       // A. 如果配置了固定周期 (如京东PLUS -> Yearly)，且没识别到对应周期的价格
       // 强制使用默认价格，覆盖可能错误的识别 (如识别成 285)
       if (fallbackConfig.fixedBillingCycle) {
          const defaultP = fallbackConfig.defaultPrice;
          
          if (fallbackConfig.fixedBillingCycle === 'Yearly') {
             if (!result.yearlyPrice || (defaultP && Math.abs(result.yearlyPrice - defaultP) > 500)) { // 偏离太大也覆盖? 暂且只看空值
                if (defaultP) {
                   result.yearlyPrice = defaultP;
                   // 如果之前没有识别到年付价格，甚至由于误识别导致 price 是错的 (比如 285)
                   // 这里我们应该信任配置的默认值
                   result.price = defaultP;
                }
                result.billingCycle = 'Yearly';
                hilog.info(0x0000, TAG, 'Enforced default Yearly price/cycle for fixed config');
             }
          } else if (fallbackConfig.fixedBillingCycle === 'Quarterly') {
             if (!result.quarterlyPrice) {
                if (defaultP) {
                   result.quarterlyPrice = defaultP;
                   result.price = defaultP;
                }
                result.billingCycle = 'Quarterly';
                hilog.info(0x0000, TAG, 'Enforced default Quarterly price/cycle for fixed config');
             }
          } else if (fallbackConfig.fixedBillingCycle === 'Monthly') {
             if (!result.monthlyPrice) {
                if (defaultP) {
                   result.monthlyPrice = defaultP;
                   result.price = defaultP;
                }
                result.billingCycle = 'Monthly';
                hilog.info(0x0000, TAG, 'Enforced default Monthly price/cycle for fixed config');
             }
          } else if (fallbackConfig.fixedBillingCycle === 'Lifetime') {
             if (!result.lifetimePrice) {
                 if (defaultP) {
                    result.lifetimePrice = defaultP;
                    result.price = defaultP;
                 }
                 result.billingCycle = 'Lifetime';
                 hilog.info(0x0000, TAG, 'Enforced default Lifetime price/cycle for fixed config');
             }
          }
       }
       
       // B. 常规兜底: 如果啥价格都没找到，用默认
       else if (fallbackConfig.defaultPrice && !result.price && !result.monthlyPrice && !result.quarterlyPrice && !result.yearlyPrice && !result.lifetimePrice) {
          result.price = fallbackConfig.defaultPrice;
          hilog.info(0x0000, TAG, `Applied default price from config: ${result.price} (General fallback)`);
       }
    }

    // 6. 使用时间提取 (Fallback for base parser)
    const timeMatch = text.match(/周[一二三四五六日](至|到)周[一二三四五六日]/);
    if (timeMatch) {
       result.usageTime = timeMatch[0];
    }

    return result;
  }

  private tryParseDate(result: OCRResult, text: string) {
    // 1. 匹配 "有效期至: 2029/10/15" 或 "到期: 26.05.29" (Support 2-digit year)
    // Group 1: Year (4 or 2 digits)
    const explicitDatePattern = /(?:有效期|到期|截止)(?:时间|日期)?[:：\s]*(20\d{2}|\d{2})[./年-](\d{1,2})[./月-](\d{1,2})(?:日)?/;
    const explicitMatch = text.match(explicitDatePattern);
    
    if (explicitMatch) {
       this.setDateFromResult(result, explicitMatch[1], explicitMatch[2], explicitMatch[3]);
       hilog.info(0x0000, TAG, `Parsed explicit date: ${result.date}`);
       return;
    }

    // 2. 匹配 "Member... 2024-05-12 到期" or "26.05.29 到期"
    const memberDatePattern = new RegExp('([^\\n\\s:：]{2,10})?[：:]?\\s*(20\\d{2}|\\d{2})[/\\-.](\\d{1,2})[/\\-.](\\d{1,2})\\s*到期');
    const memberDateMatch = text.match(memberDatePattern);

    if (memberDateMatch) {
      if (!result.appName && memberDateMatch[1]) {
        // Only use group 1 as appName if it exists and we don't have one
        // But the regex optional group might mess up indices if not careful. 
        // Let's rely on indices being 2,3,4 for date if group 1 is present or not? 
        // No, if group 1 is optional, indices shift if it's not captured but the group exists in regex structure?
        // Actually, if group 1 `([^...])?` matches undefined, it still takes a slot index.
        // Let's verify standard JS regex behavior. Yes. Use named groups for safety? ArkTS strictness?
        // Let's stick to standard indexing. 
        // If match[1] is undefined, we just proceed.
      }
      
      // If the first group was the app name, we might use it. 
      // But for "26.05.29到期", there is no app name prefix necessarily.
      
      this.setDateFromResult(result, memberDateMatch[2], memberDateMatch[3], memberDateMatch[4]);
      return;
    }

    // 3. 宽松匹配 (2-digit year support is risky for loose matching, sticking to 4 digits or strict context)
    // But user's case has "26.05.29到期". This should be caught by #2 above if we fix the regex.
    // The previous pattern for #2 required a prefix `([^\\n\\s:：]{2,10})`.
    // The raw text might be "26.05.29到期" on its own line or just "26.05.29到期" with no prefix.
    // So making the prefix optional `?` is important.
    
    // Loose Pattern: Keep stricter 4-digit validation to avoid FP on prices/versions
    const looseDatePattern = /\b(20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b/;
    const lines = text.split('\n');
    for (const line of lines) {
       // 跳过明显不是日期的 (比如电话号码, 价格)
       if (line.includes('¥') || line.includes('电话')) continue;
       
       const looseMatch = line.match(looseDatePattern);
       if (looseMatch) {
          const year = parseInt(looseMatch[1]);
          if (year >= 2020 && year <= 2035) {
             this.setDateFromResult(result, looseMatch[1], looseMatch[2], looseMatch[3]);
             hilog.info(0x0000, TAG, `Parsed loose date from line: ${line}`);
             return;
          }
       }
    }
  }

  private setDateFromResult(result: OCRResult, yearStr: string, monthStr: string, dayStr: string) {
      let year = parseInt(yearStr);
      // Handle 2-digit year
      if (year < 100) {
        year += 2000; 
      }
      
      let month = parseInt(monthStr) - 1;
      const day = parseInt(dayStr);
      const date = new Date(year, month, day);
      if (!isNaN(date.getTime())) {
        result.date = date.getTime();
      }
  }
}
