import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SubscriptionRepository, MinimalCardItem } from '../model/SubscriptionRepository';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { fileIo as fs } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { resourceManager } from '@kit.LocalizationKit';
import { WARRANTY_ICON_MAP_NAMES, WARRANTY_THEME_MAP, getWarrantyThemeColors } from '../utils/WarrantyConstants';

const TAG: string = 'EntryFormAbility';
const DOMAIN_NUMBER: number = 0xFF00;

class CardItemData {
  title: string = '';
  content: string = '';
  icon: string = '';
  isExpiring: boolean = false;
  isLifetime: boolean = false;
  price: string = '';
  fullDate: string = '';
  isGroupBuy: boolean = false;
  isWarranty: boolean = false;
  colorStart?: string;
  colorEnd?: string;
  originalItem: string = '';
}

class WidgetFormData {
  widgetData: CardItemData[] = [];
  isLoggedIn: boolean = false;
  totalCount: number = 0;
  activeThemeId: string = 'default';
  formImages: Record<string, number> = {};
}

class ErrorData {
  widgetData: CardItemData[] = [];
  isLoggedIn: boolean = true;
}

export default class EntryFormAbility extends FormExtensionAbility {
  
  onCreate(want: Want) {
    hilog.info(DOMAIN_NUMBER, TAG, 'FormAbility onCreate');
    // Initialize preferences early
    PreferenceUtil.getInstance().loadPreference(this.context);
  }

  onAddForm(want: Want) {
    // Called to return a FormBindingData object.
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string;
    const formName = want.parameters?.[formInfo.FormParam.NAME_KEY] as string;
    hilog.info(DOMAIN_NUMBER, TAG, `onAddForm: Adding form, id=${formId}, name=${formName}`);
    
    // Attempt to load sync snapshot for "instant" display
    let initialData = new WidgetFormData();
    initialData.isLoggedIn = true; // Default to true to show skeleton/content if snapshot missing

    try {
        // Ensure preferences are loaded for current context
        PreferenceUtil.getInstance().loadPreference(this.context);
        const filePath = this.context.filesDir + '/widget_snapshot.json';
        
        // Initial fallbacks from disk preferences directly (synchronous)
        initialData.activeThemeId = PreferenceUtil.getInstance().getThemeIdSync(this.context);
        
        if (fs.accessSync(filePath)) {
            const content = fs.readTextSync(filePath);
            const snapshot = JSON.parse(content) as Record<string, Object>;
            if (snapshot && snapshot.widgetData) {
                initialData.widgetData = snapshot.widgetData as CardItemData[];
                initialData.isLoggedIn = (snapshot.isLoggedIn as boolean) ?? true;
                initialData.totalCount = (snapshot.totalCount as number) ?? initialData.widgetData.length;
                
                // Use theme from snapshot if exists, else fall back to the one we just loaded
                if (snapshot.activeThemeId) {
                    initialData.activeThemeId = snapshot.activeThemeId as string;
                }
                hilog.info(DOMAIN_NUMBER, TAG, `onAddForm: Snapshot loaded. theme=${initialData.activeThemeId}, total=${initialData.totalCount}`);
            }
        } else {
            hilog.info(DOMAIN_NUMBER, TAG, `onAddForm: No snapshot file found. Initial theme: ${initialData.activeThemeId}`);
        }
    } catch (e) {
        hilog.error(DOMAIN_NUMBER, TAG, `onAddForm: Internal error processing snapshot/theme`);
    }

    let binding = formBindingData.createFormBindingData(initialData);
    
    // Trigger updates immediately for data freshness with a slight delay
    if (formId) {
        setTimeout(() => {
            hilog.info(DOMAIN_NUMBER, TAG, `onAddForm: Triggering background update for formId ${formId}`);
            this.updateFormData(formId);
        }, 150); // Increased slightly for stability
        PreferenceUtil.getInstance().saveFormId(formId);
    }

    return binding;
  }

  onCastToNormalForm(formId: string) {
    // Called when the form provider is notified that a temporary form is successfully
    // converted to a normal form.
    hilog.info(DOMAIN_NUMBER, TAG, `onCastToNormalForm: Form ${formId} cast to normal`);
    this.updateFormData(formId);
    PreferenceUtil.getInstance().saveFormId(formId);
  }

  onUpdateForm(formId: string) {
    // Called to notify the form provider to update a specified form.
    hilog.info(DOMAIN_NUMBER, TAG, `FormAbility onUpdateForm triggered, formId = ${formId}`);
    this.updateFormData(formId);
  }

  onFormEvent(formId: string, message: string) {
    // Called when a specified message event defined by the form provider is triggered.
    hilog.info(DOMAIN_NUMBER, TAG, `FormAbility onFormEvent, formId = ${formId}, message: ${message}`);
  }

  onRemoveForm(formId: string) {
    // Called to notify the form provider that a specified form has been destroyed.
    PreferenceUtil.getInstance().removeFormId(formId);
  }

  onAcquireFormState(want: Want) {
    // Called to return a {@link FormState} object.
    return formInfo.FormState.READY;
  }

  async updateFormData(formId: string) {
      if (!formId) return;
      try {
          await SubscriptionRepository.getInstance().init(this.context);
          await PreferenceUtil.getInstance().loadPreference(this.context);

          const session = await PreferenceUtil.getInstance().loadSession();
          const isLoggedIn = (session['isLoggedIn'] as boolean) ?? false;

          // Query Data
          const subs = await SubscriptionRepository.getInstance().queryAll();
          hilog.info(DOMAIN_NUMBER, TAG, `updateFormData: isLoggedIn=${isLoggedIn}, subsCount=${subs.length}`);
          
          const formImages: Record<string, number> = {};
          const openedFiles: fs.File[] = [];
          const tempDir = this.context.getApplicationContext().tempDir;
          
          try {
              // Process items in parallel to speed up downloads
              const widgetList: CardItemData[] = await Promise.all(subs.map(async (item: SubscriptionModel) => {
                  let iconKey: string = '';
                  const isGroupBuy = item.recordType === 'groupBuy';

                   if (isGroupBuy) {
                       let rawPath: string = '';
                       if (item.platform === 'meituan') rawPath = 'icons/美团.png';
                       else if (item.platform === 'douyin') rawPath = 'icons/抖音.png';
                       else if (item.platform === 'dianping') rawPath = 'icons/大众点评.png';

                       if (rawPath) {
                           try {
                               const content: Uint8Array = await this.context.resourceManager.getRawFileContent(rawPath);
                               const targetPath: string = `${tempDir}/platform_${item.platform}.png`;
                               
                               let fileExists: boolean = false;
                               try { fileExists = fs.accessSync(targetPath); } catch (e) { fileExists = false; }
                               
                               if (!fileExists) {
                                   const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
                                   fs.writeSync(file.fd, content.buffer);
                                   fs.closeSync(file);
                               }
                               
                               const file = fs.openSync(targetPath, fs.OpenMode.READ_ONLY);
                               openedFiles.push(file);
                               const key: string = `platform_${item.platform}`;
                               formImages[key] = file.fd;
                               iconKey = `memory://${key}`;
                           } catch (e) {
                               hilog.error(DOMAIN_NUMBER, TAG, `Failed to load platform icon ${rawPath}: ${JSON.stringify(e)}`);
                           }
                       }
                   }

                   if (!iconKey) {
                       if (item.icon && item.icon.startsWith('file://')) {
                           // case 1: Custom Local Image (file://)
                           const filePath: string = item.icon.replace('file://', '');
                           try {
                               if (fs.accessSync(filePath)) {
                                   const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
                                   openedFiles.push(file); 
                                   const customImageKey: string = `local_${item.id}_${Date.now()}`;
                                   formImages[customImageKey] = file.fd;
                                   iconKey = `memory://${customImageKey}`;
                               }
                           } catch (e) {
                               hilog.warn(DOMAIN_NUMBER, TAG, `Failed to load local icon: ${filePath}`);
                               iconKey = item.name?.charAt(0).toUpperCase() || '?';
                           }
                       } 
                       else if (item.icon && (item.icon.startsWith('http://') || item.icon.startsWith('https://'))) {
                           // case 2: Network Image (http://)
                           try {
                               const fileName: string = `net_${item.uuid || item.id}.png`; 
                               const targetPath: string = `${tempDir}/${fileName}`;
                               let fileExists: boolean = false;
                               
                               try { fileExists = fs.accessSync(targetPath); } catch (e) { fileExists = false; }
                               
                               if (!fileExists) {
                                   const httpRequest = http.createHttp();
                                   const resp = await httpRequest.request(item.icon, { 
                                       readTimeout: 5000, 
                                       connectTimeout: 5000 
                                   });
                                   if (resp.responseCode === 200) {
                                       const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
                                       fs.writeSync(file.fd, resp.result as ArrayBuffer);
                                       fs.closeSync(file);
                                       fileExists = true;
                                   }
                                   httpRequest.destroy();
                               }
                               
                               if (fileExists) {
                                   const file = fs.openSync(targetPath, fs.OpenMode.READ_ONLY);
                                   openedFiles.push(file);
                                   formImages[fileName] = file.fd;
                                   iconKey = `memory://${fileName}`;
                               } else {
                                   iconKey = item.name?.charAt(0).toUpperCase() || '?';
                               }
                           } catch (e) {
                               iconKey = item.name?.charAt(0).toUpperCase() || '?';
                           }
                       } 
                       else {
                           iconKey = item.icon || (item.name?.charAt(0).toUpperCase() || '?');
                       }
                   }
                  
                  if (!iconKey) {
                      iconKey = item.name?.charAt(0).toUpperCase() || '?';
                  }

                  const isLifetime = item.billingCycle === 'Lifetime';
                  const days = isLifetime ? 999 : DateUtil.getDaysUntil(item.nextBillingDate);
                  const dateStr = DateUtil.formatShortDate(item.nextBillingDate);

                const isWarranty = item.recordType === 'warranty';
                const obj = new CardItemData();
                obj.title = item.name || (isWarranty ? '未知保修' : '未知订阅');

                if (isGroupBuy) {
                  const statusText: string = item.usageStatus === 'used' ? '已使用' : (item.usageStatus === 'expired' ? '已过期' : `剩 ${DateUtil.getDaysUntil(item.nextBillingDate)} 天`);
                  obj.content = item.merchantName ? `${item.merchantName} | ${statusText}` : statusText;
                } else if (isWarranty) {
                  const statusStr = days < 0 ? '过保' : '在保';
                  // 保修卡片无论是否为 Lifetime，只要 recordType 是 warranty 就显示保修到期
                  obj.content = `${statusStr}:${dateStr}`;

                  // 预计算保修视觉 (解决跨模块隔离)
                  // 优先使用 category 作为图标查找依据，因为 name 可能是用户自定义的
                  let warrantyName = item.name || '';
                  if (item.category && WARRANTY_ICON_MAP_NAMES[item.category]) {
                    warrantyName = item.category;
                  } else if (item.subCategory && WARRANTY_ICON_MAP_NAMES[item.subCategory]) {
                    warrantyName = item.subCategory;
                  }

                  const theme = WARRANTY_THEME_MAP[warrantyName] || 'blue';
                  const colors = getWarrantyThemeColors(theme);
                  obj.colorStart = colors[0];
                  obj.colorEnd = colors[1];
                  
                  // 转换为 rawfile 路径
                  const svgPath = WARRANTY_ICON_MAP_NAMES[warrantyName];
                  if (svgPath) {
                    iconKey = `rawfile:${svgPath}`;
                  }
                } else {
                  obj.content = isLifetime ? `永久买断` : `到期:${dateStr}`;
                }

                if (!obj.icon) {
                  obj.icon = iconKey;
                }
                // 普通订阅和保修在剩余3天内标红；团购券如果是未使用且剩余3天内也标红
                if (isGroupBuy) {
                  obj.isExpiring = item.usageStatus === 'unused' && days <= 3;
                } else {
                  obj.isExpiring = !isLifetime && days <= 3;
                }
                obj.isLifetime = isLifetime;
                obj.isGroupBuy = isGroupBuy;
                obj.isWarranty = isWarranty;

                let priceStr = `${item.currency === 'USD' ? '$' : '¥'}${item.price}`;
                if (!isGroupBuy && !isWarranty) {
                  if (item.billingCycle === 'Monthly') priceStr += '/月';
                  else if (item.billingCycle === 'Yearly') priceStr += '/年';
                  else if (item.billingCycle === 'Quarterly') priceStr += '/季';
                  else if (item.billingCycle === 'Lifetime') priceStr += '/永久';
                  else if (item.billingCycle === 'Indefinite') priceStr += '/不定';
                } else if (isWarranty) {
                  // 保修不显示价格周期，显示“保修”字样
                  priceStr = '保修';
                }
                obj.price = priceStr;
                   
                    obj.fullDate = DateUtil.formatDate(item.nextBillingDate);
                    // --- 核心优化：只同步必要的最小化数据，避免触发桌面卡片 128KB 限制 ---
                    const minimalItem: MinimalCardItem = {
                      id: item.id || 0,
                      uuid: item.uuid,
                      recordType: item.recordType || 'subscription',
                      usageStatus: item.usageStatus || 'unused',
                      isWarranty: isWarranty,
                      name: item.name || ''
                    };
                    obj.originalItem = JSON.stringify(minimalItem);
                    return obj;
              }));

              const formData = new WidgetFormData();
              formData.totalCount = subs.length;
              // --- 核心优化：解除卡片列表截断限制，应用户要求允许展示更多数据 ---
              // formData.widgetData = widgetList.slice(0, 10);
              formData.widgetData = widgetList;
              formData.isLoggedIn = true; 
              formData.activeThemeId = await PreferenceUtil.getInstance().loadThemeId();

              // --- 新增：卡片列表排序逻辑，团购已使用/已过期置底 ---
              formData.widgetData.sort((a, b) => {
                  try {
                      const aObj = JSON.parse(a.originalItem) as Record<string, Object>;
                      const bObj = JSON.parse(b.originalItem) as Record<string, Object>;
                      
                      const aProcessed = aObj['recordType'] === 'groupBuy' && (aObj['usageStatus'] === 'used' || aObj['usageStatus'] === 'expired');
                      const bProcessed = bObj['recordType'] === 'groupBuy' && (bObj['usageStatus'] === 'used' || bObj['usageStatus'] === 'expired');
                      
                      if (aProcessed && !bProcessed) return 1;
                      if (!aProcessed && bProcessed) return -1;
                      return 0;
                  } catch (e) {
                      return 0;
                  }
              });


              hilog.info(DOMAIN_NUMBER, TAG, `updateFormData: Sending update. theme=${formData.activeThemeId}, items=${formData.widgetData.length}, images=${Object.keys(formImages).length}`);
              
              if (Object.keys(formImages).length > 0) {
                  formData.formImages = formImages;
              }
              
              let formInfoData = formBindingData.createFormBindingData(formData);
              await formProvider.updateForm(formId, formInfoData);
              hilog.info(DOMAIN_NUMBER, TAG, `Form updated for ID: ${formId} successfully with theme ${formData.activeThemeId}`);
              
              // 同步更新本地快照文件，确保下次冷启动(onAddForm)能读到最新数据
              SubscriptionRepository.getInstance().updateWidgetSnapshotSync('bg_refresh');
              
          } catch (innerError) {
              hilog.error(DOMAIN_NUMBER, TAG, `updateFormData inner error: ${JSON.stringify(innerError)}`);
          }
          // Do NOT close FDs here! Per HarmonyOS docs, FDs should be released when
          // FormExtensionAbility process is destroyed, not immediately after updateForm.
          
      } catch (err) {
          const error: BusinessError = err as BusinessError;
          hilog.error(DOMAIN_NUMBER, TAG, `updateFormData failed: ${error.code} ${error.message}`);
          // Should we send error state? maybe not to avoid flashing error on minor glitches
      }
  }
}