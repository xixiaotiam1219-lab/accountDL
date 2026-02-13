import { OCRResult } from './OCRManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { detectBarcode, scanBarcode, scanCore } from '@kit.ScanKit';
import { image } from '@kit.ImageKit';

import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'GroupBuyOCRManager';

export interface QRCodeResult {
  code: string;
  codeImageUri?: string;
}

export class GroupBuyOCRManager {
  private static instance: GroupBuyOCRManager;

  private constructor() {
  }

  public static getInstance(): GroupBuyOCRManager {
    if (!GroupBuyOCRManager.instance) {
      GroupBuyOCRManager.instance = new GroupBuyOCRManager();
    }
    return GroupBuyOCRManager.instance;
  }

  /**
   * 解析团购券文本
   */
  parseText(text: string): OCRResult {
    hilog.info(0x0000, TAG, `Group Buy OCR Raw Text:\n${text}`);
    let result: OCRResult = { fullText: text };

    const lines = text.split('\n');

    // 1. 平台识别
    const hasMeituanKeywords = text.includes('美团') || text.includes('神券');
    const hasDouyinKeywords = text.includes('抖音') || text.includes('字节') || text.includes('TikTok') || text.includes('客服');
    const hasMemberKeywords = text.includes('会员') || text.includes('成长值');
    const hasStatusKeyword = text.includes('待到店使用') || text.includes('待使用');

    if (hasMeituanKeywords) {
      result.platform = 'meituan';
      hilog.info(0x0000, TAG, 'Detected Platform: Meituan (via Name)');
    } else if (hasDouyinKeywords) {
      result.platform = 'douyin';
      hilog.info(0x0000, TAG, 'Detected Platform: Douyin (via keyword or KeFu)');
    } else if (hasStatusKeyword) {
      // 用户规则：即使有待使用状态，如果没有会员/成长值信息，判定为大众点评
      if (hasMemberKeywords) {
        result.platform = 'meituan';
        hilog.info(0x0000, TAG, 'Detected Platform: Meituan (via status + member)');
      } else {
        result.platform = 'dianping';
        hilog.info(0x0000, TAG, 'Detected Platform: Dianping (status without member)');
      }
    } else {
      // 默认判定为大众点评
      result.platform = 'dianping';
      hilog.info(0x0000, TAG, 'No specific platform keywords found, defaulting to Dianping');
    }

    // 2. 商家名称识别
    // 2. 商家名称识别
    // 策略 A: 寻找 "适用门店" 下一行，优先匹配带括号的行 "麦当劳(福州...)"
    let foundMerchant = false;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line === '适用门店' || line.includes('适用门店')) {
            // Check next lines (up to 4 lines)
            for (let j = 1; j <= 4; j++) {
              if (i + j < lines.length) {
                  const nextLine = lines[i + j].trim();
                  
                  // Skip generic noise
                  if (nextLine.includes('全部门店') || nextLine.length <= 1 || nextLine.includes('营业中') || nextLine.includes('距离')) {
                     continue;
                  }
                  
                  // User Rule: Prioritize line with brackets, take the part before bracket.
                  // e.g. "麦当劳(福州...)" -> "麦当劳"
                  // Guard against "2026.03.03(含)"
                  if ((nextLine.includes('(') || nextLine.includes('（')) && !nextLine.includes('含') && !nextLine.includes('距离')) {
                      const parts = nextLine.split(/[\(（]/);
                      if (parts[0].length >= 2) {
                          result.merchantName = parts[0].trim();
                          hilog.info(0x0000, TAG, `Found Merchant by Bracket Rule: ${result.merchantName}`);
                          foundMerchant = true;
                          break;
                      }
                  }
                  
                  // Fallback: Just take the line if it looks like a name and we haven't found a bracket one yet
                  // We delay this fallback to prioritizing the bracket one if possible, 
                  // but since we are scanning linearly, we might hit this first? 
                  // Let's rely on the bracket check mostly. 
                  // If we don't find a bracket one in the window, we might revisit?
                  // For now, let's allow "Target you this year Golden Arches" (bad OCR) to be skipped if possible.
                  
                  // Simple fallback if no specific bracket line found in this block?
                  // Let's store a candidate.
              }
            }
            if (foundMerchant) break;
        }
        
        // 策略 B: Global Bracket Search for Merchant (if we are sure it's not a Project)
        // Usually Merchant Name appears after "适用门店".
        
        // 策略 C: "商家: XXX" (Fallback)
        if (!foundMerchant && (line.startsWith('商家') || line.startsWith('门店')) && line.split(/[:：\s]/).length > 1) {
             const parts = line.split(/[:：]/);
             if (parts.length >= 2) {
               result.merchantName = parts[1].trim();
               foundMerchant = true;
               break;
             }
        }

        // 策略 D: 查找包含括号店名的行 "麦当劳(正荣财富中心店)"
        if (!foundMerchant && (line.includes('(') || line.includes('（')) && (line.endsWith('店') || line.includes('店)'))) {
            const parts = line.split(/[\(（]/);
            if (parts[0].length >= 2) {
                result.merchantName = parts[0].trim();
                foundMerchant = true;
                hilog.info(0x0000, TAG, `Found Merchant by (店) Rule: ${result.merchantName}`);
                break;
            }
        }
    }

    // 3. 项目名称识别
    hilog.info(0x0000, TAG, 'Searching for Project Name...');
    let bestMatchName = '';
    
    // Strategy: Find all brackets 【...】
    // Note: The input text might have newlines inside brackets if we are unlucky, 
    // but lines array is split. We should use the raw `text` for regex matching.
    const allMatches = text.matchAll(/【([\s\S]*?)】/g);
    for (const m of allMatches) {
        let content = m[1];
        // Clean content
        content = content.replace(/[\r\n]/g, '').trim();
        
        // Filter out instructions/warnings
        if (content.includes('取餐') || content.includes('注意') || content.includes('提醒') || 
            content.includes('正确') || content.includes('暂停营业') || content.includes('使用限制')) {
           continue; 
        }
        
        // Filter if it looks like a SKU or small tag
        if (content.length < 2) continue;
        
        // Use this as the name
        bestMatchName = content;
        break; // Use the first valid one, usually the top one is the main title
    }
    
    if (bestMatchName) {
        // Cleaning
        let rawContent = bestMatchName;
        rawContent = rawContent.replace(/¥\d+(\.\d{2})?/g, '')
                               .replace(/x\d+/g, '');
        if (rawContent.length >= 2) {
            result.appName = rawContent.trim();
            hilog.info(0x0000, TAG, `Found Project Name in brackets: ${result.appName}`);
        }
    }
    
    // Fallback: If no brackets found or all rejected, prioritize line containing "套餐"
    if (!result.appName) {
         for (const line of lines) {
             if (line.includes('套餐') && !line.includes('有效期') && !line.includes('须知')) {
                 result.appName = line.replace('套餐', '').trim();
                 // Clean up leading punctuation
                 result.appName = result.appName.replace(/^[:：\s]+/, '');
                 hilog.info(0x0000, TAG, `Found Project Name by "套餐" line: ${result.appName}`);
                 break;
             }
         }
    } 
    
    // Fallback: Line based
    if (!result.appName) {
        for (const line of lines) {
          if ((line.includes('套餐') || line.includes('任选') || line.includes('人餐') || 
               line.includes('代金券') || line.includes('自助')) && !line.includes('有效期')) {
             result.appName = line.trim(); 
             break;
          }
        }
    }

    // 4. 券码识别
    // 增加对常见 OCR 误识别字符的支持 (如 Cyrillic 'С', 'М', 'А', 'О' 等)
    const codePrefixPattern = /(?:券码|券号|验证码|密码|码\d张)[:：\s]*([A-ZСМАО\d\s-]{8,50})/;
    const codeMatch = text.match(codePrefixPattern);
    
    const normalizeCode = (raw: string): string => {
        return raw.replace(/\s/g, '')
                  .replace(/С/g, 'C')
                  .replace(/М/g, 'M')
                  .replace(/А/g, 'A')
                  .replace(/О/g, 'O')
                  .replace(/В/g, 'B')
                  .replace(/Е/g, 'E')
                  .replace(/Н/g, 'H');
    };

    if (codeMatch) {
       let cleanCode = normalizeCode(codeMatch[1]);
       if (cleanCode.length >= 8) { 
           result.couponCode = cleanCode;
           hilog.info(0x0000, TAG, `Found Coupon Code by Prefix: ${result.couponCode}`);
       }
    } 
    
    // 如果还没匹配到或者匹配到的太短，尝试全局搜索特征券码 (如 MCD6 0AWO...)
    if (!result.couponCode || result.couponCode.length < 10) {
        // 匹配 3-6 位一组的字母数字块，由空格分隔，重复 3 次以上
        const globalCodePattern = /\b([A-ZСМАО\d]{3,6}(\s[A-ZСМАО\d]{3,6}){2,})\b/g;
        const matches = text.match(globalCodePattern);
        if (matches && matches.length > 0) {
             // 过滤并排序，取最长的可能是券码的字符串
             const sorted = matches.map(m => m.trim()).sort((a, b) => b.length - a.length);
             const candidate = normalizeCode(sorted[0]);
             if (candidate.length >= 10) {
                 result.couponCode = candidate;
                 hilog.info(0x0000, TAG, `Found Alphanumeric Coupon Code (Global Refined): ${result.couponCode}`);
             }
        }
    }
    if (!result.couponCode) {
       // 纯数字查找 (Strict 12-20 digits sequence, possibly with spaces, difficult to strict match without prefix)
       // Let's stick to prefix for now as user provided "券号"
    }

    // 5. 价格识别
    // 策略: "实付¥51.70"
    const paidPattern = /实付[:：\s]*¥?(\d+(?:\.\d{1,2})?)/;
    const paidMatch = text.match(paidPattern);
    if (paidMatch) {
       result.price = parseFloat(paidMatch[1]);
       hilog.info(0x0000, TAG, `Found Paid Price: ${result.price}`);
    } else {
       // 找最大金额? 或者找 "¥" 开头的
       // 简单复用之前的价格提取逻辑，但要排除原价
       for (const line of lines) {
          if (line.includes('¥') && !line.includes('原价') && !line.includes('折扣')) {
             const priceMatch = line.match(/¥(\d+(?:\.\d{1,2})?)/);
             if (priceMatch) {
                result.price = parseFloat(priceMatch[1]);
                break; // Take the first valid looking price
             }
          }
       }
    }

    // 6. 有效期识别
    this.tryParseDate(result, text);

    // 5. 使用时间范围识别
    const timePatterns = [
        /周[一二三四五六日](至|到)周[一二三四五六日]/,
        /\d{1,2}[:：]\d{2}\s*[-至]\s*\d{1,2}[:：]\d{2}/,
        /每天/,
        /24小时/,
        /法定节假日/
    ];
    
    let timeParts: string[] = [];
    
    // 策略1: 优先查找包含"周X至周X"的行（这通常是券的使用时间）
    for (const line of lines) {
       if (line.match(/周[一二三四五六日](至|到)周[一二三四五六日]/)) {
          // 排除营业时间相关的行
          if (line.includes('营业') || line.includes('营业中') || line.includes('营业结束')) {
             continue;
          }
          timeParts.push(line.trim());
          hilog.info(0x0000, TAG, `Found Usage Time (Weekday Pattern): ${line.trim()}`);
          break; // 找到就停止
       }
    }
    
    // 策略2: 如果没找到周X模式，再查找包含"可用"的行
    if (timeParts.length === 0) {
       for (const line of lines) {
          if (line.includes('可用')) {
             timeParts.push(line.split('可用')[0] + '可用');
             hilog.info(0x0000, TAG, `Found Usage Time (Available Pattern): ${line}`);
             break; 
          }
       }
    }
    
    // 策略3: 最后才尝试其他时间模式
    if (timeParts.length === 0) {
       for (const line of lines) {
          for (const pattern of timePatterns) {
              const match = line.match(pattern);
              if (match) {
                  // 排除明显的门店营业状态行
                  if (line.includes('营业中') || line.includes('营业') || line.includes('营业结束') ||
                      (line.includes('店') && !line.includes('到店'))) {
                     continue;
                  }
                  timeParts.push(line.trim());
                  hilog.info(0x0000, TAG, `Found Usage Time (Time Pattern): ${line.trim()}`);
                  break;
              }
          }
          if (timeParts.length > 0) break; 
       }
    }
    
    if (timeParts.length > 0) {
        result.usageTime = Array.from(new Set(timeParts)).join(' ');
        hilog.info(0x0000, TAG, `Found Usage Time (Final): ${result.usageTime}`);
    }

    return result;
  }

  private tryParseDate(result: OCRResult, text: string) {
      // 1. 匹配 "有效期至: 2029/10/15" 或 "到期: 26.05.29" (Support 2-digit year)
      // Updated Regex:
      // - Support "请在...前到店消费" pattern (e.g. "请在2026/02/19 23:59(含)前到店消费")
      // - Support explicit "到期" suffix without colon
      // - Support "26.05.29" with dots
      const explicitDatePattern = /(?:有效期|到期|截止|请在)(?:时间|日期)?[:：\s]*(20\d{2}|\d{2})[./年-](\d{1,2})[./月-](\d{1,2})(?:日)?/;
      const explicitMatch = text.match(explicitDatePattern);
      
      if (explicitMatch) {
         this.setDateFromResult(result, explicitMatch[1], explicitMatch[2], explicitMatch[3]);
         hilog.info(0x0000, TAG, `Parsed explicit date: ${result.date}`);
         return;
      }
  
      // 2. Loose date matching if needed, similar to OCRManager
      // Updated to match 2026/02/19 in mixed text lines
      const looseDatePattern = /\b(20\d{2})[./-](\d{1,2})[./-](\d{1,2})\b/;
      const lines = text.split('\n');
      for (const line of lines) {
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

  /**
   * 识别二维码提取券码，并尝试裁剪码图片
   * @param context
   * @param pixelMap 
   * @returns {Promise<QRCodeResult | undefined>}
   */
  async extractQRCode(context: common.Context, pixelMap: image.PixelMap): Promise<QRCodeResult | undefined> {
    let tempUri: string | undefined = undefined;
    try {
      // 1. 保存 PixelMap 到临时文件
      tempUri = await this.saveTempImage(context, pixelMap);
      
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: true,
        enableAlbum: true
      };

      const inputImage: detectBarcode.InputImage = { uri: tempUri };
      
      const result: Array<scanBarcode.ScanResult> = await detectBarcode.decode(inputImage, options);
      
      if (result && result.length > 0) {
         const first = result[0];
         const code = first.originalValue;
         let codeImageUri: string | undefined = undefined;
         
         if (first.scanCodeRect) {
             const rect = first.scanCodeRect;
             hilog.info(0x0000, TAG, `Code Rect detected: ${JSON.stringify(rect)}`);
             // 裁剪并保存
             codeImageUri = await this.cropAndSaveCode(context, pixelMap, rect);
         }
         
         hilog.info(0x0000, TAG, `QR/Bar Code Detected: ${code}, URI: ${codeImageUri}`);
         return { code: code, codeImageUri: codeImageUri };
      }
    } catch (e) {
      hilog.error(0x0000, TAG, `QR Code Scan Failed: ${JSON.stringify(e)}`);
    } finally {
      if (tempUri) {
         try { fileIo.unlink(tempUri); } catch (e) {}
      }
    }
    return undefined;
  }

  private async cropAndSaveCode(context: common.Context, originalMap: image.PixelMap, rect: scanBarcode.ScanCodeRect): Promise<string> {
      try {
          // Calculate dimensions from rect
          const rectWidth = rect.right - rect.left;
          const rectHeight = rect.bottom - rect.top;

          if (rectWidth <= 0 || rectHeight <= 0) return '';
          
          const imageInfo = await originalMap.getImageInfo();
          
          // Ensure rect is within bounds
          // Add padding to ensure full code is captured
          const padding = 30; // 30px padding
          const x = Math.max(0, rect.left - padding);
          const y = Math.max(0, rect.top - padding);
          const right = Math.min(imageInfo.size.width, rect.right + padding);
          const bottom = Math.min(imageInfo.size.height, rect.bottom + padding);
          
          const w = right - x;
          const h = bottom - y;
          
          if (w <= 0 || h <= 0) return '';
          
          // 1. Read pixels to buffer to clone
          const bufferSize = originalMap.getPixelBytesNumber();
          const buffer = new ArrayBuffer(bufferSize);
          await originalMap.readPixelsToBuffer(buffer);

          // 2. Create a new editable PixelMap from buffer
          const opts: image.InitializationOptions = {
              editable: true,
              pixelFormat: imageInfo.pixelFormat,
              size: imageInfo.size
          };
          const croppedMap = await image.createPixelMap(buffer, opts);

          // 3. Crop existing map
          await croppedMap.crop({ x: x, y: y, size: { width: w, height: h } });
          
          // Save to persisted filesDir
          const filesDir = context.filesDir;
          const fileName = `coupon_code_${Date.now()}.jpg`;
          const targetPath = `${filesDir}/${fileName}`;
          const file = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
          
          const packer = image.createImagePacker();
          await packer.packToFile(croppedMap, file.fd, { format: 'image/jpeg', quality: 100 });
          await fileIo.close(file);
          
          croppedMap.release();
          return `file://${targetPath}`;

      } catch (e) {
          hilog.error(0x0000, TAG, `Crop Code Failed: ${JSON.stringify(e)}`);
          return '';
      }
  }

  private async saveTempImage(context: common.Context, pixelMap: image.PixelMap): Promise<string> {
    // const context = common.getApplicationContext(); // invalid
    const fileName = `qr_temp_${Date.now()}.jpg`;
    const targetPath = `${context.tempDir}/${fileName}`;
    
    const file = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
    const imagePacker = image.createImagePacker();
    const packData = await imagePacker.packing(pixelMap, { format: 'image/jpeg', quality: 90 });
    
    await fileIo.write(file.fd, packData);
    await fileIo.close(file);
    
    return `file://${targetPath}`;
  }
}
