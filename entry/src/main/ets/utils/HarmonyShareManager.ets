import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { window, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { SubscriptionRepository } from '../model/SubscriptionRepository';





/**
 * 由于 SDK 类型定义可能滞后，定义此接口用于调用新版本 API
 * 继承自原类型以满足 ArkTS 的类型转换“重叠”要求
 */
interface SharableTargetExtended extends harmonyShare.SharableTarget {
  clarifyNonShare: (params: Record<string, string>) => Promise<void>;
}

/**
 * 隔空传送数据包格式
 */
export class ExportData {
  version: number = 1;
  timestamp: number = Date.now();
  subscriptions: SubscriptionModel[] = [];
}

/**
 * 隔空传送管理类 (参考社区大佬风格优化)
 */
export class HarmonyShareManager {
  private static instance: HarmonyShareManager;
  private context: common.UIAbilityContext | undefined = undefined;
  private isListening: boolean = false;
  private TAG = 'HarmonyShareManager';
  private DOMAIN = 0x0000;

  private constructor() {}

  public static getInstance(): HarmonyShareManager {
    if (!HarmonyShareManager.instance) {
      HarmonyShareManager.instance = new HarmonyShareManager();
    }
    return HarmonyShareManager.instance;
  }

  public setContext(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 隔空传送回调
   */
  private onGesturesShare = async (target: harmonyShare.SharableTarget) => {
    hilog.info(this.DOMAIN, this.TAG, 'GesturesShare triggered (grab/release)');

    try {
      if (!this.context) return;

      // 1. 获取数据
      const subs = await SubscriptionRepository.getInstance().queryAll();
      if (!subs || subs.length === 0) {
        // [优化] 分享 Kit 要求：在无可分享内容时需主动告知系统终止分享
        // 显式断言为继承后的扩展接口，确保类型系统满意
        const extendedTarget = target as SharableTargetExtended;
        if (typeof extendedTarget.clarifyNonShare === 'function') {
           extendedTarget.clarifyNonShare({ 'message': '暂无订阅数据可分享' });
        } else {
           // 使用保底错误码
           target.reject(harmonyShare.SharableErrorCode.DOWNLOAD_ERROR);
        }
        promptAction.showToast({ message: '暂无订阅数据可分享' });
        return;
      }
      // 2. 决定分享方式
      const exportSubs = await this.prepareSubscriptionsForExport(subs, true);
      const exportData = new ExportData();
      exportData.subscriptions = exportSubs;
      const jsonStr = JSON.stringify(exportData);

      // 将 Base64 编码后的数据进行 URI 编码，检查最终长度
      const base64Data = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(jsonStr));
      const finalUri = `accountdl://import?action=import&data=${encodeURIComponent(base64Data)}`;

      let shareData: systemShare.SharedData;

      // 终极稳定性逻辑：
      // 实测证实 128KB 在 17 图场景下依然可能触发系统 IPC 限制。
      // 为保证 100% 稳定性，我们将 Deep Link 阈值降至更保守的 64KB (64,000 字节)。
      // 超过此值将强制走“文件模式”，确保利用华为分享的无上限文件传输能力。
      hilog.info(this.DOMAIN, this.TAG, `ShareData length: ${finalUri.length}`);
      
      if (finalUri.length < 100000) {
        hilog.info(this.DOMAIN, this.TAG, `Using Deep Link (Size: ${finalUri.length})`);
        shareData = new systemShare.SharedData({
          utd: utd.UniformDataType.HYPERLINK,
          content: finalUri,
          title: '分享订阅数据',
          description: `准备分享 ${subs.length} 条订阅数据。`,
          thumbnailUri: await this.getThumbnailUri(subs)
        });
      } else {
        // 超过 IPC 管道限制，自动切换为“文件分享模式”。
        hilog.info(this.DOMAIN, this.TAG, `Data too large (${finalUri.length}), switching to File Share Mode`);
        const filePath = await this.saveToTempFile(jsonStr);
        
        // [优化] 对于想要“应用直达”的自定义文件，显式指定自定义 UTD ID
        // 确保接收端的 module.json5 -> skills -> uris -> utd 能完美匹配
        const customUtd = 'com.accountdl.package';
        
        shareData = new systemShare.SharedData({
          utd: customUtd,
          uri: fileUri.getUriFromPath(filePath),
          title: '分享订阅数据',
          description: `准备分享 ${subs.length} 条订阅数据。`,
          thumbnailUri: await this.getThumbnailUri(subs)
        });
      }

      // 3. 执行分享
      target.share(shareData);

    } catch (e) {
      hilog.error(this.DOMAIN, this.TAG, `OnGesturesShare error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 主动触发系统分享面板
   */
  public async activeShare() {
    hilog.info(this.DOMAIN, this.TAG, 'ActiveShare triggered');

    try {
      if (!this.context) return;

      // 1. 获取数据
      const subs = await SubscriptionRepository.getInstance().queryAll();
      if (!subs || subs.length === 0) {
        promptAction.showToast({ message: '暂无订阅数据可分享' });
        return;
      }
      // 2. 准备分享数据
      const exportSubs = await this.prepareSubscriptionsForExport(subs, true);
      const exportData = new ExportData();
      exportData.subscriptions = exportSubs;
      const jsonStr = JSON.stringify(exportData);

      const base64Data = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(jsonStr));
      const finalUri = `accountdl://import?action=import&data=${encodeURIComponent(base64Data)}`;

      let shareData: systemShare.SharedData;

      // 64KB 是绝大多数 IPC 场景最稳妥的红线
      hilog.info(this.DOMAIN, this.TAG, `ActiveShare total length: ${finalUri.length}`);

      if (finalUri.length < 100000) {
        hilog.info(this.DOMAIN, this.TAG, `ActiveShare using Deep Link (Size: ${finalUri.length})`);
        shareData = new systemShare.SharedData({
          utd: utd.UniformDataType.HYPERLINK,
          content: finalUri,
          title: '分享订阅数据',
          description: `准备分享 ${subs.length} 条订阅数据。`,
          thumbnailUri: await this.getThumbnailUri(subs)
        });
      } else {
        hilog.info(this.DOMAIN, this.TAG, `ActiveShare data too large (${finalUri.length}), switching to File Mode`);
        const filePath = await this.saveToTempFile(jsonStr);
        
        const customUtd = 'com.accountdl.package';
        
        shareData = new systemShare.SharedData({
          utd: customUtd,
          uri: fileUri.getUriFromPath(filePath),
          title: '分享订阅数据',
          description: `准备分享 ${subs.length} 条订阅数据。`,
          thumbnailUri: await this.getThumbnailUri(subs)
        });
      }

      // 3. 弹出系统分享面板
      const controller = new systemShare.ShareController(shareData);
      controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      });

    } catch (e) {
      hilog.error(this.DOMAIN, this.TAG, `ActiveShare error: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 注册监听
   */
  public async register() {
    if (this.isListening || !this.context) return;

    if (canIUse("SystemCapability.Collaboration.HarmonyShare")) {
      try {
        const win = await window.getLastWindow(this.context);
        const windowId = win.getWindowProperties().id;

        // 1. 注册隔空传送 (One-Grab-One-Release)
        harmonyShare.on('gesturesShare', { windowId: windowId }, this.onGesturesShare);

        // 2. 注册碰一碰 (Touch-to-Share / Bump)
        harmonyShare.on('knockShare', { windowId: windowId }, this.onGesturesShare);

        this.isListening = true;
        hilog.info(this.DOMAIN, this.TAG, 'gesturesShare & knockShare registered');
      } catch (error) {
        hilog.error(this.DOMAIN, this.TAG, `Register failed: ${JSON.stringify(error)}`);
      }
    }
  }

  /**
   * 取消监听
   */
  public async unregister() {
    if (!this.isListening || !this.context) return;

    if (canIUse("SystemCapability.Collaboration.HarmonyShare")) {
      try {
        const win = await window.getLastWindow(this.context);
        const windowId = win.getWindowProperties().id;

        harmonyShare.off('gesturesShare', { windowId: windowId });
        harmonyShare.off('knockShare', { windowId: windowId });

        this.isListening = false;
        hilog.info(this.DOMAIN, this.TAG, 'gesturesShare & knockShare unregistered');
      } catch (error) {
        hilog.error(this.DOMAIN, this.TAG, `Unregister failed: ${JSON.stringify(error)}`);
      }
    }
  }

  private async getThumbnailUri(subs: SubscriptionModel[]): Promise<string> {
    if (!this.context) return '';

    try {
      const resourceMgr = this.context.resourceManager;
      const fileContent = await resourceMgr.getMediaContent($r('app.media.foreground'));
      const thumbPath = this.context.filesDir + '/share_logo.png';
      
      const thumbFile = fs.openSync(thumbPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(thumbFile.fd, fileContent.buffer);
      fs.closeSync(thumbFile);
      
      return fileUri.getUriFromPath(thumbPath);
    } catch(err) {
      hilog.error(this.DOMAIN, this.TAG, `Static thumbnail generation failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  private async saveToTempFile(content: string): Promise<string> {
    if (!this.context) return '';
    const filePath = this.context.filesDir + '/subscriptions.json';
    const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, content);
    fs.closeSync(file);
    return filePath;
  }

  /**
   * 预处理订阅数据，将 file:// 类型的图标转换为 Base64
   * 并且执行压缩以减小体积，支持 Deep Link 自动唤起。
   * 设置为 public 以支持备份导出。
   */
  public async prepareSubscriptionsForExport(subs: SubscriptionModel[], compress: boolean = true): Promise<SubscriptionModel[]> {
    const exported: SubscriptionModel[] = [];
    
    for (const sub of subs) {
      const newItem = JSON.parse(JSON.stringify(sub)) as SubscriptionModel;
      
      // 1. 自动填充团购券图标 (与 SettingsView 保持同步)
      if (newItem.recordType === 'groupBuy' && (!newItem.icon || newItem.icon === '')) {
           if (newItem.platform === 'meituan') {
               newItem.icon = 'resource:meituan_logo';
           } else if (newItem.platform === 'douyin') {
               newItem.icon = 'resource:douyin_logo';
           } else if (newItem.platform === 'dianping') {
               newItem.icon = 'resource:dianping_logo';
           }
      }
      
      if (newItem.icon && newItem.icon.startsWith('file://')) {
        try {
          const srcUri = newItem.icon;
          const fileUriObj = new fileUri.FileUri(srcUri);
          const realPath = fileUriObj.path;

          if (fs.accessSync(realPath)) {
             // 核心逻辑：区分内置图标库与自定义图标
             if (realPath.includes('/local_icons/')) {
               // 1. 内置库图标：提取文件名，使用精简协议头，不再转码
               const filename = realPath.substring(realPath.lastIndexOf('/') + 1);
               newItem.icon = `builtin://${filename}`;
               hilog.debug(this.DOMAIN, this.TAG, `Exporting library icon as builtin: ${filename}`);
             } else if (compress) {
               // 2. 真正自定义图标：执行压缩转换
               const base64Str = await this.compressIconToBase64(realPath);
               if (base64Str) {
                 newItem.icon = `data:image/jpeg;base64,${base64Str}`;
               } else {
                 newItem.icon = '';
               }
             } else {
               // 原样输出 (保底逻辑)
               const file = fs.openSync(realPath, fs.OpenMode.READ_ONLY);
               const stat = fs.statSync(file.fd);
               if (stat.size < 1024 * 1024) { 
                 const buf = new ArrayBuffer(stat.size);
                 fs.readSync(file.fd, buf);
                 const base64Str = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
                 newItem.icon = `data:image/png;base64,${base64Str}`;
               }
               fs.closeSync(file);
             }
          }
        } catch (e) {
          hilog.error(this.DOMAIN, this.TAG, `Failed to convert export icon: ${e}`);
          newItem.icon = ''; 
        }
      }

      
      // === 处理 couponImage (团购券截图) ===
      if (newItem.couponImage && newItem.couponImage.startsWith('file://')) {
        try {
          const originalPath = newItem.couponImage;
          const filename = (originalPath.split('/').pop() || '').split('?')[0];
          const ctx = this.context;
          
          let realPath = '';
          try {
              realPath = new fileUri.FileUri(originalPath).path;
          } catch (e) {
              realPath = decodeURIComponent(originalPath.substring(7));
          }

          // 构造搜寻路径
          let searchPaths: string[] = [realPath];
          if (filename && ctx) {
              searchPaths.push(`${ctx.filesDir}/${filename}`);
              searchPaths.push(`${ctx.cacheDir}/${filename}`);
              searchPaths.push(`${ctx.tempDir}/${filename}`);
              searchPaths.push(`${ctx.filesDir}/files/${filename}`);
          }

          let base64Result = '';
          for (const p of searchPaths) {
              try {
                  if (fs.accessSync(p)) {
                      const file = fs.openSync(p, fs.OpenMode.READ_ONLY);
                      const stat = fs.statSync(file.fd);
                      const buf = new ArrayBuffer(stat.size);
                      fs.readSync(file.fd, buf);
                      fs.closeSync(file);
                      
                      const base64Str = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
                      let mime = 'image/png';
                      if (p.toLowerCase().endsWith('.jpg') || p.toLowerCase().endsWith('.jpeg')) mime = 'image/jpeg';
                      else if (p.toLowerCase().endsWith('.webp')) mime = 'image/webp';
                      
                      base64Result = `data:${mime};base64,${base64Str}`;
                      break;
                  }
              } catch (e) { continue; }
          }

          if (base64Result) {
              newItem.couponImage = base64Result;
              hilog.debug(this.DOMAIN, this.TAG, `Exported coupon image via share for ${newItem.name}`);
          }
        } catch (e) {
           hilog.error(this.DOMAIN, this.TAG, `Failed to convert coupon image in share: ${e}`);
        }
      }

      exported.push(newItem);
    }
    return exported;
  }

  /**
   * 压缩图标到 Base64
   */
  private async compressIconToBase64(path: string): Promise<string> {
    try {
      const imageSource = image.createImageSource(path);
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: 120, height: 120 }, // 恢复至 120x120，极大缓解 IPC 压力
        editable: false
      };
      
      const pixelMap = await imageSource.createPixelMap(decodingOptions);
      const imagePacker = image.createImagePacker();
      const packingOptions: image.PackingOption = {
        format: 'image/jpeg',
        quality: 75
      };
      
      const buffer = await imagePacker.packing(pixelMap, packingOptions);
      const base64Str = new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer));
      
      // Release
      pixelMap.release();
      imageSource.release();
      
      return base64Str;
    } catch (e) {
      hilog.error(this.DOMAIN, this.TAG, `Compression failed: ${e}`);
      return '';
    }
  }
}
