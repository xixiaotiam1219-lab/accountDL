import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ZHIPU_API_BASE_URL, ZHIPU_API_TOKEN, ZHIPU_MODEL } from './ApiConfig';
import { BusinessError } from '@kit.BasicServicesKit';
import { matchMemberService, MEMBER_SERVICES } from './MemberServiceConfig';
import { OCRManager, OCRResult } from './OCRManager';
import { Luban } from '@ark/luban';
import { fileIo } from '@kit.CoreFileKit';
import { PreferenceUtil } from './PreferenceUtil';

const TAG = 'AIVisionManager';
const DOMAIN = 0x0000;

interface ZhipuMessage {
  content: string;
  role: string;
}

interface ZhipuChoice {
  message: ZhipuMessage;
}

interface ZhipuUsage {
  total_tokens: number;
}

/**
 * 智谱 AI 响应接口
 */
interface ZhipuResponse {
  id: string;
  choices: Array<ZhipuChoice>;
  usage: ZhipuUsage;
}

/**
 * 预期 AI 返回的 JSON 结构
 */
interface AIJSONResult {
  appName: string | null;
  monthlyPrice: number | null;
  quarterlyPrice: number | null;
  yearlyPrice: number | null;
  lifetimePrice: number | null;
  date: number | null;
  data: number | null;
  category: string | null;
  subCategory: string | null;
}

export class AIVisionManager {
  private static instance: AIVisionManager;

  private constructor() {}

  public static getInstance(): AIVisionManager {
    if (!AIVisionManager.instance) {
      AIVisionManager.instance = new AIVisionManager();
    }
    return AIVisionManager.instance;
  }

  /**
   * 识别订阅截图
   * @param input 图片输入 (URI 字符串 或 PixelMap)
   * @returns 识别结果
   */
  async recognizeSubscription(input: image.PixelMap | string): Promise<OCRResult> {
    try {
      let base64Image: string;
      let localOCRTask: Promise<string> | undefined;

      if (typeof input === 'string') {
        // 如果是 URI，先使用 Luban 压缩
        hilog.info(DOMAIN, TAG, `Recognizing from URI: ${input}`);
        const compressedPath = await this.compressImage(input);
        base64Image = await this.fileToBase64(compressedPath);
        // String input 场景下暂时略过本地 OCR 并行 (除非有 helper load pixelmap), 
        // 但现有业务逻辑 AddSubscription 必定传入 PixelMap，所以此分支暂不处理
      } else {
        // 如果是 PixelMap
        hilog.info(DOMAIN, TAG, 'Recognizing from PixelMap (Hybrid Mode)');
        base64Image = await this.pixelMapToBase64(input);
        
        // 并行启动本地 OCR
        localOCRTask = OCRManager.getInstance().recognizeText(input);
      }
      
      // 2. 调用 AI API
      const aiTask = this.callZhipuAPI(base64Image);
      
      // 3. 等待结果
      const results = await Promise.all([
        aiTask, 
        localOCRTask ? localOCRTask : Promise.resolve('')
      ]);
      const aiResult = results[0] as AIJSONResult | null;
      const localText = results[1] as string;
      
      // 4. 解析 Local OCR 结果作为基础 (Metadata Source of Truth)
      let finalResult: OCRResult;
      if (localText) {
         hilog.info(DOMAIN, TAG, `Local OCR Text Length: ${localText.length}`);
         finalResult = OCRManager.getInstance().parseText(localText);
      } else {
         finalResult = { fullText: 'AI Only' }; // Fallback
      }
      
      // 5. 融合 AI 价格结果 (Price Source of Truth)
      // AI 的价格识别通常更准，尤其在复杂排版下
      if (aiResult) {
        if (aiResult.monthlyPrice) finalResult.monthlyPrice = aiResult.monthlyPrice;
        if (aiResult.quarterlyPrice) finalResult.quarterlyPrice = aiResult.quarterlyPrice;
        if (aiResult.yearlyPrice) finalResult.yearlyPrice = aiResult.yearlyPrice;
        if (aiResult.lifetimePrice) finalResult.lifetimePrice = aiResult.lifetimePrice;
        if (aiResult.subCategory) finalResult.subCategory = aiResult.subCategory;
      }
      
      // 6. 重新推断 BillingCycle 和最终 Price
      if (finalResult.monthlyPrice) {
          finalResult.billingCycle = 'Monthly';
          finalResult.price = finalResult.monthlyPrice;
      } else if (finalResult.quarterlyPrice) {
          finalResult.billingCycle = 'Quarterly';
          finalResult.price = finalResult.quarterlyPrice;
      } else if (finalResult.yearlyPrice) {
          finalResult.billingCycle = 'Yearly';
          finalResult.price = finalResult.yearlyPrice;
      } else if (finalResult.lifetimePrice) {
          finalResult.billingCycle = 'Lifetime';
          finalResult.price = finalResult.lifetimePrice;
      }

      return finalResult;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `AI Recognition failed: ${JSON.stringify(e)}`);
      throw new Error(`AI Recognition failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 使用 Luban 压缩图片
   */
  private async compressImage(uri: string): Promise<string> {
    try {
      hilog.info(DOMAIN, TAG, `Starting Luban compression for: ${uri}`);
      
      // 使用默认配置: 忽略 100KB 以下，保留透明通道
      // 返回 compressedFiles 数组 (Luban.get() returns Promise<string[]>)
      const compressedFiles = await Luban.with(uri)
        .ignoreBy(100) 
        .filter((path: string) => path.indexOf('.gif') === -1) // 排除 GIF
        .get();

      if (compressedFiles && compressedFiles.length > 0) {
        const targetPath = compressedFiles[0];
        hilog.info(DOMAIN, TAG, `Luban compression success: ${targetPath}`);
        return targetPath;
      } else {
        hilog.warn(DOMAIN, TAG, 'Luban returned empty result, using original URI');
        return uri;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Luban compression failed: ${JSON.stringify(e)}, using original URI`);
      return uri; // 降级: 压缩失败使用原图
    }
  }

  /**
   * 读取文件并转换为 Base64
   */
  private async fileToBase64(filePath: string): Promise<string> {
    try {
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file);
      
      const uint8Array = new Uint8Array(buf);
      const base64Helper = new util.Base64Helper();
      const base64Str = base64Helper.encodeToStringSync(uint8Array);
      
      // 简单的 MIME 类型推断
      let mimeType = 'image/jpeg';
      if (filePath.endsWith('.png')) mimeType = 'image/png';
      else if (filePath.endsWith('.webp')) mimeType = 'image/webp';
      
      return `data:${mimeType};base64,${base64Str}`;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `File read failed: ${e}`);
      throw new Error('Failed to read image file');
    }
  }

  /**
   * 将 PixelMap 转换为 Base64 字符串
   */
  private async pixelMapToBase64(pixelMap: image.PixelMap): Promise<string> {
    const imagePacker = image.createImagePacker();
    const packingOptions: image.PackingOption = { format: 'image/jpeg', quality: 50 };
    
    try {
      const data: ArrayBuffer = await imagePacker.packing(pixelMap, packingOptions);
      const uint8Array = new Uint8Array(data);
      const base64Helper = new util.Base64Helper();
      const base64Str = base64Helper.encodeToStringSync(uint8Array);
      return `data:image/jpeg;base64,${base64Str}`;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `PixelMap packing failed: ${e}`);
      throw new Error('Image processing failed');
    } finally {
      imagePacker.release();
    }
  }

  /**
   * 调用智谱 GLM-4V API
   */
  private async callZhipuAPI(base64Image: string): Promise<AIJSONResult | null> {
    const httpRequest = http.createHttp();
    const url = `${ZHIPU_API_BASE_URL}/chat/completions`;
    
    // 1. 检查用户开关
    const isEnabled = await PreferenceUtil.getInstance().isAIEnabled();
    if (!isEnabled) {
       hilog.info(DOMAIN, TAG, 'AI Recognition disabled by user');
       return null;
    }

    // 强制使用用户配置的 API Key
    const userApiKey = await PreferenceUtil.getInstance().getAIKey();
    if (!userApiKey) {
      hilog.info(DOMAIN, TAG, 'No user API Key, skipping cloud AI call');
      return null;
    }
    const activeToken = userApiKey;
    
    // 省略 prompt 定义...
    const prompt = `
请仔细分析这张订阅服务的截图，提取以下价格信息并以JSON格式返回。

请严格参考以下价格识别规则：
1. **优先续费价**：如果同时出现"原价"和"续费价"/"下次扣款"，优先提取后者
2. **数字清洗**：忽略 "优惠后"、"立省" 等修饰词，只提取实际支付金额

需要提取的字段：
1. 包月价格（monthlyPrice）：数字，单位元
2. 包季价格（quarterlyPrice）：数字，单位元
3. 包年价格（yearlyPrice）：数字，单位元
4. 永久/买断价格（lifetimePrice）：数字，单位元
5. 当前选中的会员等级（subCategory）：字符串

识别规则补充：
- **价格拆分**：如果多个价格连在一起（如 "¥168¥228"），通常第一个是实付价，第二个是原价。请提取第一个实测价格。
- **时长归类**：
  - "12个月"、"1年"、"365天" 对应的价格 -> **yearlyPrice**
  - "1个月"、"30天"、"31天" 对应的价格 -> **monthlyPrice**
  - "3个月"、"1季"、"90天" 对应的价格 -> **quarterlyPrice**
- **视觉选中判断**：请发挥你的视觉理解能力，找到截图中**用户当前选中的那个订阅选项**。
  - **视觉特征**：选中项通常具有**高亮背景**、**颜色反转**、**粗边框**、**对勾图标**或**放大显示**等特征。
  - **提取内容**：提取该选中项所代表的**具体会员等级/套餐名称**（例如：VIP、阅读会员、听书会员）。
  - **清洗周期**：⚠️如果名称中包含周期或时长（如 "阅读会员12个月"），请**删掉周期部分**，只保留核心等级名称（如 "阅读会员"）。
  - **排除项**：⚠️严禁将纯周期词（如 "连续包月"、"12个月"）直接作为等级。如果只看到这些词，说明没有特殊的会员等级，此时 subCategory 应返回 null。
  - 如果截图没有明显的选中状态，请根据页面内的主要推广项或大号字体的项目推测一个最可能的等级。

严格约束：
- **只关注价格和选中项**，不要提取日期等其他信息
- 遇到未知的字段返回 null
- 只返回纯 JSON

返回纯JSON格式：
{
  "monthlyPrice": 19,
  "quarterlyPrice": 58,
  "yearlyPrice": 198,
  "lifetimePrice": null,
  "subCategory": "白金VIP"
}
`;

    try {
      const response = await httpRequest.request(
        url,
        {
          method: http.RequestMethod.POST,
          header: {
            'Authorization': `Bearer ${activeToken}`,
            'Content-Type': 'application/json'
          },
          extraData: {
            model: ZHIPU_MODEL,
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "image_url",
                    image_url: {
                      url: base64Image
                    }
                  },
                  {
                    type: "text",
                    text: prompt
                  }
                ]
              }
            ]
          },
          expectDataType: http.HttpDataType.OBJECT,
          readTimeout: 30000,
          connectTimeout: 10000
        }
      );

      hilog.info(DOMAIN, TAG, `API Response Code: ${response.responseCode}`);

      if (response.responseCode === 200) {
        const result = response.result as ZhipuResponse;
        const choices = result.choices;
        if (!choices || choices.length === 0) {
             throw new Error('Empty choices from AI');
        }
        const content = choices[0].message.content;
        
        hilog.info(DOMAIN, TAG, `AI Raw Content: ${content}`);
        
        // 更稳健的 JSON 提取逻辑：查找第一个 '{' 和最后一个 '}'
        const startIndex = content.indexOf('{');
        const endIndex = content.lastIndexOf('}');
        
        if (startIndex === -1 || endIndex === -1 || startIndex >= endIndex) {
          throw new Error('Invalid JSON format in AI response');
        }
        
        const jsonStr = content.substring(startIndex, endIndex + 1);
        
        try {
          return JSON.parse(jsonStr) as AIJSONResult;
        } catch (parseErr) {
          hilog.error(DOMAIN, TAG, `JSON Parse Error: ${parseErr}, content: ${jsonStr}`);
          throw new Error('Failed to parse AI JSON result');
        }
      } else {
        throw new Error(`API Error: ${response.responseCode}`);
      }
    } catch (e) {
      // 修复: 避免 JSON.stringify(Error) 返回 {} 的问题
      const errorMessage = e instanceof Error ? e.message : JSON.stringify(e);
      hilog.error(DOMAIN, TAG, `Request failed: ${errorMessage}`);
      throw new Error(`AI Request failed: ${errorMessage}`);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 转换 AI 结果为统一的 OCRResult
   */
  private convertToOCRResult(aiResult: AIJSONResult): OCRResult {
    const result: OCRResult = {
      fullText: 'AI Implementation',
      appName: aiResult.appName || undefined,
      monthlyPrice: aiResult.monthlyPrice || undefined,
      quarterlyPrice: aiResult.quarterlyPrice || undefined,
      yearlyPrice: aiResult.yearlyPrice || undefined,
      lifetimePrice: aiResult.lifetimePrice || undefined,
      date: aiResult.date || undefined,
      category: aiResult.category || undefined,
      subCategory: aiResult.subCategory || undefined
    };

    // 智能补充图标
    if (result.appName) {
      const matched = matchMemberService(result.appName);
      if (matched) {
        result.serviceIcon = matched.icon;
        if (!result.category && matched.category) {
          result.category = matched.category;
        }
      }
    }

    // 自动推断 BillingCycle 和 Price
    if (result.lifetimePrice) {
      result.billingCycle = 'Lifetime';
      result.price = result.lifetimePrice;
    } else if (result.yearlyPrice) {
      result.billingCycle = 'Yearly';
      result.price = result.yearlyPrice;
    } else if (result.quarterlyPrice) {
      result.billingCycle = 'Quarterly';
      result.price = result.quarterlyPrice;
    } else if (result.monthlyPrice) {
      result.billingCycle = 'Monthly';
      result.price = result.monthlyPrice;
    }

    // 如果只有一个价格,确保 price 字段有值
    if (!result.price && (result.monthlyPrice || result.quarterlyPrice || result.yearlyPrice || result.lifetimePrice)) {
      result.price = result.monthlyPrice || result.quarterlyPrice || result.yearlyPrice || result.lifetimePrice;
    }

    return result;
  }
}
