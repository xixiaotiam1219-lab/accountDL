import { SubscriptionModel } from '../model/SubscriptionModel';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { BackgroundWatermark } from './BackgroundWatermark';
import { OCRManager, OCRResult } from '../utils/OCRManager';
import { GroupBuyOCRManager, QRCodeResult } from '../utils/GroupBuyOCRManager';
import { AIVisionManager } from '../utils/AIVisionManager';
import { common, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { DateUtil } from '../utils/DateUtil';
import { resolveIcon, matchMemberService, matchWarrantyCategory, MemberServiceConfig, searchMemberServices } from '../utils/MemberServiceConfig';
import { PromptAction, window, display, promptAction, screenshot, curves, LengthMetrics } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { BusinessError, Callback, deviceInfo } from '@kit.BasicServicesKit';
import { FloatingBallManager } from '../utils/FloatingBallManager';
import { photoAccessHelper, PhotoSource, RecentPhotoComponent, RecentPhotoOptions, BaseItemInfo } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { ExtendedWarrantyItem } from '../model/SubscriptionModel';

import { fileIo } from '@kit.CoreFileKit';
import { hdsEffect, hdsMaterial, HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { ImageCropSheet } from './ImageCropPage';
import { GlobalBus, EVENT_SYNC_COMPLETED, EVENT_DATA_CHANGED } from '../utils/GlobalBus';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { PreferenceUtil } from '../utils/PreferenceUtil';
import { AppInfo, LocalIconManager } from '../utils/LocalIconManager';
import { WebViewParam } from './WebViewPage';
import { WarrantyCategorySheet, WarrantyCategory } from './WarrantyCategorySheet';
import { ExtendedWarrantyItemView } from './ExtendedWarrantyItemView';
@Builder
export function AddSubscriptionBuilder() {
  AddSubscription()
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct AddSubscription {
  @Consume('pageStack') pageStack: NavPathStack;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  @State hasApiKey: boolean = true;
  @State name: string = '';
  @State price: string = '';
  @State currency: string = '¥';
  @State billingCycle: 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite' = 'Monthly';
  @State nextBillingDate: Date = new Date();
  @State startDate: Date = new Date(); // 新增开始日期
  @State isAutoRenewal: boolean = true; // 自动续费开关
  @State isOCRLoading: boolean = false;
  // OCR 识别的各周期价格
  @State ocrMonthlyPrice: string = '';
  @State ocrQuarterlyPrice: string = '';
  @State ocrYearlyPrice: string = '';
  @State ocrLifetimePrice: string = '';
  // OCR 识别结果是否显示
  @State showOCRResult: boolean = false;
  @State ocrExpireDate: string = '';
  @State editId: number = -1;
  @State uuid: string = ''; // 记录唯一标识
  @State icon: string = '';
  // 订阅分类
  @State category: string = '其他';
  @State subCategory: string = '';
  @State availableSubCategories: string[] = []; // 可选的二级分类列表
  @State paymentMethod: string = '其他支付方式'; // 支付方式

  // === 团购券/保修期相关状态 ===
  @State recordType: 'subscription' | 'groupBuy' | 'warranty' = 'subscription'; // 记录类型
  @State platform: 'meituan' | 'douyin' | 'dianping' = 'dianping'; // 团购平台
  @State couponCode: string = ''; // 券码
  @State couponImage: string = ''; // 券码截图
  @State usageStatus: 'unused' | 'used' | 'expired' = 'unused'; // 使用状态
  @State merchantName: string = ''; // 商家名称
  @State quantity: number = 1; // 券数量
  @State usageTime: string = ''; // 使用时间范围 (周一至周日等)
  @State realUsageTime: number | undefined = undefined; // 实际核销时间戳
  // === 保修/保质期专属状态 ===
  @State brand: string = ''; // 品牌名称
  @State purchaseChannel: string = ''; // 购买渠道
  
  // === 附加保障服务 (多项支持) ===
  @State extendedWarranties: ExtendedWarrantyItem[] = [];
  @State isExtendedWarrantyListExpanded: boolean = false;
  @State extendedWarrantyListOpacity: number = 0;

  @State isUsageTimePressed: boolean = false;
  @State usageTimeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  // 提醒设置
  @State isReminderEnabled: boolean = false;
  @State reminderDaysBefore: number = 1; // 默认提前1天
  @State reminderTime: string = '09:00'; // 默认早上9点

  // 自动补全建议
  @State suggestions: MemberServiceConfig[] = [];
  @State showSuggestions: boolean = false;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  private skipNextSearch: boolean = false;  // 选中候选项后跳过下次搜索

  // 截图识别模式
  @State isScreenshotMode: boolean = false;
  @State showRecentPhotoSheet: boolean = false;  // 是否显示最近截图选择器
  @State hasDetectedScreenshot: boolean = false;  // 是否检测到截屏

  // 图片裁剪
  @State showCropSheet: boolean = false;
  @State showWarrantyCategorySheet: boolean = false; // 是否显示保修分类 Sheet
  @State isWarrantyCategoryPressed: boolean = false; // 物品分类行是否被按下
  @State cropSourceUri: string = '';
  @State showExampleSheet: boolean = false; // 控制示例图 Sheet 显示

  // RecentPhotoComponent 配置
  private recentPhotoOptions: RecentPhotoOptions = new RecentPhotoOptions();
  private reminderDaysOptions: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30'];


  // 截屏状态监听回调 - 已废弃
  // private captureStatusCallback: Callback<boolean> = (captureStatus: boolean) => {
  //   this.onCaptureStatusChange(captureStatus);
  // };

  // Animation States
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @State animStep1: boolean = false;
  @State animStep2: boolean = false;
  @State isAIProtected: boolean = false; // 新增：AI 识别保护标志位，用于保护 AI 识别出的精准等级不被云端匹配覆盖
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  @State isReminderExpanded: boolean = false;
  @State reminderOpacity: number = 0;

  // Interaction States
  @State isImagePickerPressed: boolean = false;
  @State imagePickerLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isFlashBallPressed: boolean = false;
  @State flashBallLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isSavePressed: boolean = false;
  @State saveLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isCancelPressed: boolean = false;
  @State cancelLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isDeletePressed: boolean = false;
  @State deleteLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State pressedCycleValue: string = ''; // For cycle buttons logic

  @State isOCRCardPressed: boolean = false;
  @State ocrCardLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isCategoryPressed: boolean = false;
  @State categoryLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isDatePressed: boolean = false;
  @State dateLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isPlusPressed: boolean = false;
  @State isMinusPressed: boolean = false;
  @State pressedUsageStatus: string = ''; // 用于识别哪个使用状态按钮正在被按压

  /**
   * 清空表单数据，防止模式切换时文字残留
   */
  private clearFormData() {
    this.name = '';
    this.price = '';
    this.merchantName = '';
    this.couponCode = '';
    this.usageTime = '';
    this.icon = '';
    this.category = '其他';
    this.subCategory = '';
    this.availableSubCategories = [];
    this.showOCRResult = false;
    this.ocrExpireDate = '';
    this.couponImage = '';
    this.ocrMonthlyPrice = '';
    this.ocrQuarterlyPrice = '';
    this.ocrYearlyPrice = '';
    this.ocrLifetimePrice = '';
    this.paymentMethod = '其他支付方式';
    this.quantity = 1;
    this.isAutoRenewal = (this.recordType === 'subscription'); // 团购/保修默认不开启自动续费
    this.usageStatus = 'unused';
    this.realUsageTime = undefined;
    // 保修/保质期字段
    this.brand = '';
    this.purchaseChannel = '';
    this.extendedWarranties = [];
  }

  @State isQROnly: boolean = false; // 新增：是否仅识别二维码模式

  @State isStartDatePressed: boolean = false;
  @State startDateLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isReminderDaysPressed: boolean = false;
  @State reminderDaysLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isReminderTimePressed: boolean = false;
  @State reminderTimeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isNamePressed: boolean = false;
  @State nameLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isLevelPressed: boolean = false;
  @State levelLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isPricePressed: boolean = false;
  @State priceLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isPaymentPressed: boolean = false;
  @State paymentLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // === 团购专属交互状态 ===
  @State isMerchantPressed: boolean = false;
  @State merchantLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isDisclaimerAgreed: boolean = false; // 新增：免责声明勾选状态

  @State isCouponPressed: boolean = false;
  @State couponLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isQuantityPressed: boolean = false;
  @State quantityLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isPlatformPressed: boolean = false;
  @State platformLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isUsageStatusPressed: boolean = false;
  @State usageStatusLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isEditQRPressed: boolean = false;
  @State editQRLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isHelpPressed: boolean = false;
  @State helpLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isBrandPressed: boolean = false;
  @State brandLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isChannelPressed: boolean = false;
  @State channelLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;



  private getPreviewIcon(): string {
    if (this.recordType === 'groupBuy') {
      if (this.platform === 'meituan') return 'resource:meituan_logo';
      if (this.platform === 'douyin') return 'resource:douyin_logo';
      if (this.platform === 'dianping') return 'resource:dianping_logo';
      return 'resource:meituan_logo';
    }
    return this.icon;
  }

  triggerAnimations() {
    const duration = this.animationDuration;
    const interval = 100;
    if (this.isAnimationEnabled) {
      // 使用全局动画参数，但为了更明显的入场效果，适当调整 response
      // 这里的 0.35/0.9 是为了强化"弹跳"感，也可以改为使用全局变量但微调
      // 既然用户要求适配阻尼，我们应该使用全局配置或其变体
      const resp = this.animationResponse;
      const damp = this.animationDamping;
      setTimeout(() => { animateTo({ duration: duration, curve: curves.springMotion(resp, damp) }, () => { this.animStep1 = true }) }, 50); 
      setTimeout(() => { animateTo({ duration: duration, curve: curves.springMotion(resp, damp) }, () => { this.animStep2 = true }) }, 50 + interval);
    } else {
          this.animStep1 = true;
          this.animStep2 = true;
      }
  }

  async aboutToAppear() {
    this.hasApiKey = !!(await PreferenceUtil.getInstance().getAIKey());
    // 初始化本地图标管理器
    await LocalIconManager.getInstance().init(getContext(this));
    
    // 如果存在残留的闪控球，自动关闭
    try {
      await FloatingBallManager.getInstance().stop();
    } catch (e) {
      hilog.error(0x0000, 'AddSubscription', `Stop floating ball on appear failed: ${e}`);
    }

    const paramsArray = this.pageStack.getParamByName('AddSubscription') as Object[];
    if (paramsArray && paramsArray.length > 0) {
      const params = paramsArray[paramsArray.length - 1] as Record<string, Object>;
      if (params && params['initialType']) {
        this.recordType = params['initialType'] as 'subscription' | 'groupBuy' | 'warranty';
      }
    }

    this.triggerAnimations();
  }

  private searchTimer: number = -1;

  async searchHuaweiApps(keyword: string) {
    if (!keyword) return;

    // 使用本地图标库搜索 (不再联网)
    const localApps = await LocalIconManager.getInstance().searchApps(keyword, 20);

    animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: curves.responsiveSpringMotion(0.35, 1.0) }, () => {
        // 转换格式
        const suggestions: MemberServiceConfig[] = localApps.map(app => {
            return {
                name: app.name,
                icon: app.icon,
                category: app.category || '其他',
                subCategory: ''
            } as MemberServiceConfig;
        });

        // 合并建议：LocalIconManager 的结果优先
        // 原有的 searchMemberServices 结果作为补充（如果它们没有图标的话）
        // 这里简化策略：直接使用 LocalIconManager 的结果作为主要建议源
        this.suggestions = suggestions;
        this.showSuggestions = this.suggestions.length > 0;

        // 自动填充逻辑 - 恢复智能匹配策略 (Exact > Contain > Prefix)
        // localApps 已经是排好序的 (LocalIconManager searchApps)

        const lowerKeyword = keyword.toLowerCase();
        let currentMatch: AppInfo | undefined = undefined;

        // 策略 A: 精确匹配优先
        const exactMatch = localApps.find(app => app.name.toLowerCase() === lowerKeyword);
        if (exactMatch) {
            currentMatch = exactMatch;
        } else {
            // 策略 B: 用户输入包含了完整应用名 (e.g. "Netflix Premium" -> "Netflix") -> 高置信度
            const containMatch = localApps.find(app => lowerKeyword.startsWith(app.name.toLowerCase()));
            if (containMatch) {
                currentMatch = containMatch;
            } else {
                // 策略 C: 前缀匹配 (e.g. "Netf" -> "Netflix")
                // 仅当唯一匹配时才自动填充，避免歧义
                const prefixMatches = localApps.filter(app => app.name.toLowerCase().startsWith(lowerKeyword));
                if (prefixMatches.length === 1) {
                    currentMatch = prefixMatches[0];
                }
            }
        }

        if (currentMatch) {
            if (currentMatch.icon) this.icon = currentMatch.icon;
            if (currentMatch.category) this.category = currentMatch.category;

            // 尝试从本地配置补充二级分类
            const localConfig = matchMemberService(currentMatch.name);
            if (localConfig && localConfig.subCategory) {
                if (!this.subCategory && !this.isAIProtected) {
                    this.subCategory = localConfig.subCategory;
                }
            }
        }
    });
  }

  @Builder ExampleImagesDialog() {
    Column() {
      Scroll() {
        Column({ space: 20 }) {
          // 标题
          Text("请参照以下格式截图，以获得最佳识别效果")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Start)

          // 并排展示
          Flex({ justifyContent: FlexAlign.SpaceBetween }) {
            Column() {
              Image($r('app.media.groupbuy_example'))
                .width('100%')
                .aspectRatio(0.6) // 保持纵横比，防止变形
                .objectFit(ImageFit.Contain)
                .borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 8 })
              
              Text("订阅截图示例")
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
            }
            .width('48%') // 留出间隙

            Column() {
              Image($r('app.media.subscription_example'))
                .width('100%')
                .aspectRatio(0.6)
                .objectFit(ImageFit.Contain)
                .borderRadius(8)
                .backgroundColor('#F5F5F5')
                .margin({ bottom: 8 })
              
              Text("团购券截图示例")
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .fontWeight(FontWeight.Medium)
            }
            .width('48%')
          }
          .width('100%')
        }
        .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')

      Button("我知道了")
        .width('90%')
        .height(40)
        .backgroundColor($r('app.color.brand_color'))
        .fontColor(Color.White)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.showExampleSheet = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
  }
  @Builder addBuilder()
  {
    Stack({ alignContent: Alignment.Top }) {
      // Universal Background Watermark
      BackgroundWatermark()
        .zIndex(0)
      Scroll() {
        Column() {
          Column() {
            Blank()
              .height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight))
          }

          // === 订阅/团购模式切换 ===
          if (this.editId === -1) {
            Row() {
              Button() {
                Text("添加服务")
                  .fontSize(14)
                  .fontWeight(this.recordType === 'subscription' ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.recordType === 'subscription' ?
                    (this.isNewYearTheme ? '#FFD700' :
                      (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                    $r('app.color.text_secondary'))
              }
              .linearGradient(this.recordType === 'subscription' ?
                (this.isNewYearTheme ? {
                  angle: 135,
                  colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                } :
                  (this.showVipTheme ? {
                    angle: 135,
                    colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                  } : undefined)) : undefined)
              .backgroundColor(this.recordType === 'subscription' ?
                (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                Color.Transparent)
              .borderRadius(14)
              .padding({
                left: 20,
                right: 20,
                top: 6,
                bottom: 6
              })
              .onClick(() => {
                animateTo({
                  duration: this.isAnimationEnabled ? 300 : 0,
                  curve: this.isAnimationEnabled ?
                    curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                }, () => {
                  if (this.recordType !== 'subscription') {
                    this.clearFormData();
                    this.recordType = 'subscription';
                  }
                });
              })

              Button() {
                Text("添加团购")
                  .fontSize(14)
                  .fontWeight(this.recordType === 'groupBuy' ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.recordType === 'groupBuy' ?
                    (this.isNewYearTheme ? '#FFD700' :
                      (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                    $r('app.color.text_secondary'))
              }
              .linearGradient(this.recordType === 'groupBuy' ?
                (this.isNewYearTheme ? {
                  angle: 135,
                  colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                } :
                  (this.showVipTheme ? {
                    angle: 135,
                    colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                  } : undefined)) : undefined)
              .backgroundColor(this.recordType === 'groupBuy' ?
                (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                Color.Transparent)
              .borderRadius(14)
              .padding({
                left: 20,
                right: 20,
                top: 6,
                bottom: 6
              })
              .onClick(() => {
                animateTo({
                  duration: this.isAnimationEnabled ? 300 : 0,
                  curve: this.isAnimationEnabled ?
                    curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                }, () => {
                  if ((this.recordType as string) !== 'groupBuy') {
                    this.clearFormData();
                    this.recordType = 'groupBuy';
                  }
                });
              })

              Button() {
                Text("添加保修")
                  .fontSize(14)
                  .fontWeight(this.recordType === 'warranty' ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.recordType === 'warranty' ?
                    (this.isNewYearTheme ? '#FFD700' :
                      (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                    $r('app.color.text_secondary'))
              }
              .linearGradient(this.recordType === 'warranty' ?
                (this.isNewYearTheme ? {
                  angle: 135,
                  colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                } :
                  (this.showVipTheme ? {
                    angle: 135,
                    colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                  } : undefined)) : undefined)
              .backgroundColor(this.recordType === 'warranty' ?
                (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                Color.Transparent)
              .borderRadius(14)
              .padding({
                left: 20,
                right: 20,
                top: 6,
                bottom: 6
              })
              .onClick(() => {
                animateTo({
                  duration: this.isAnimationEnabled ? 300 : 0,
                  curve: this.isAnimationEnabled ?
                    curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                }, () => {
                  if (this.recordType !== 'warranty') {
                    this.clearFormData();
                    this.recordType = 'warranty';
                  }
                });
              })
            }
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(16)
            .padding(4)
            .margin({ bottom: 24 })
            .opacity(this.animStep1 ? 1 : 0)
            .translate({ y: this.animStep1 ? 0 : 100 })
            .scale({ x: this.animStep1 ? 1 : 0.9, y: this.animStep1 ? 1 : 0.9 })
          }

          // 1. OCR 智能扫描区 - 双按钮布局
          if (!this.hasApiKey) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(14)
                .fontColor([$r('app.color.text_secondary')])
              Text(" 您暂未配置 API Key，将使用本地OCR能力识别")
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 6 })
            .onClick(() => {
              this.pageStack.pushPathByName('AIConfig', null);
            })
            .opacity(this.animStep1 ? 1 : 0)
            .translate({ y: this.animStep1 ? 0 : 100 })
            .scale({ x: this.animStep1 ? 1 : 0.9, y: this.animStep1 ? 1 : 0.9 })
          }

          Row({ space: 12 }) {
            // 按钮 A: 拍摄/导入
            Button() {
              Row() {
                if (this.isOCRLoading) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(Color.White)
                    .margin({ right: 6 })
                  Text("图片解析中...")
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                } else {
                  SymbolGlyph($r('sys.symbol.camera_fill'))
                    .fontSize(18)
                    .fontColor([this.isNewYearTheme ? '#FFD700' :
                      (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)])
                    .margin({ right: 6 })
                  Text("相册/拍照")
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isNewYearTheme ? '#FFD700' :
                      (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                }
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(50)
            .linearGradient(this.isOCRLoading ? undefined : (this.isNewYearTheme ? {
              angle: 135,
              colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
            } : (this.showVipTheme ? {
              angle: 135,
              colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
            } : {
              angle: 0,
              colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]]
            })))
            .backgroundColor(this.isOCRLoading ? $r('app.color.text_secondary') : Color.Transparent)
            .borderRadius(14)
            .shadow({ radius: 8, color: '#20007AFF', offsetY: 4 })
            .enabled(!this.isOCRLoading)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.imagePickerLight,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.isImagePickerPressed ? 0.98 : 1, y: this.isImagePickerPressed ? 0.98 : 1 })
            .animation({
              duration: this.isAnimationEnabled ? 150 : 0,
              curve: curves.springMotion(this.animationResponse, this.animationDamping)
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.isImagePickerPressed = true;
                  this.imagePickerLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isImagePickerPressed = false;
                this.imagePickerLight = hdsEffect.PointLightSourceType.NONE;
              }
            })
            .onClick(async () => {
              let pixelMap: image.PixelMap | undefined = undefined;
              let imageUri: string | undefined = undefined;
              try {
                const pickResult = await OCRManager.getInstance().pickImageWithUri();
                if (!pickResult) {
                  return;
                }
                pixelMap = pickResult.pixelMap;
                imageUri = pickResult.uri;

                // [Fix] For Group Buy, use the specialized logic (Local OCR + QR Code) consistent with Screenshot
                if (this.recordType === 'groupBuy') {
                  await this.processPixelMap(pixelMap);
                  return;
                }

                // 使用动画包裹状态变化 - 清空所有 OCR 相关状态
                animateTo({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                }, () => {
                  this.ocrMonthlyPrice = '';
                  this.ocrQuarterlyPrice = '';
                  this.ocrYearlyPrice = '';
                  this.ocrLifetimePrice = '';
                  this.showOCRResult = false;
                  this.ocrExpireDate = '';
                  this.icon = '';
                  this.price = '';
                  this.subCategory = '';
                  this.couponImage = ''; // Clear image
                  this.availableSubCategories = [];

                  this.name = '';
                  this.category = '其他';
                });

                this.isOCRLoading = true;

                // 优先使用 AI 识别
                const result = await AIVisionManager.getInstance().recognizeSubscription(pixelMap);

                animateTo({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: curves.springMotion(0.4, 0.8)
                }, () => {
                  // 检查是否是首次识别（在更新价格之前）
                  const isFirstScan = !this.ocrMonthlyPrice && !this.ocrQuarterlyPrice && !this.ocrYearlyPrice &&
                    !this.ocrLifetimePrice;

                  // 更新价格信息
                  this.ocrMonthlyPrice = result.monthlyPrice ? result.monthlyPrice.toString() : '';
                  this.ocrQuarterlyPrice = result.quarterlyPrice ? result.quarterlyPrice.toString() : '';
                  this.ocrYearlyPrice = result.yearlyPrice ? result.yearlyPrice.toString() : '';
                  this.ocrLifetimePrice = result.lifetimePrice ? result.lifetimePrice.toString() : '';

                  hilog.info(0x0000, 'AddSubscription',
                    `AI OCR Prices - Monthly: ${this.ocrMonthlyPrice}, Quarterly: ${this.ocrQuarterlyPrice}, Yearly: ${this.ocrYearlyPrice}, Lifetime: ${this.ocrLifetimePrice}`);

                  // 只在首次识别时采用 AI 推断的周期，后续保留用户选择
                  if (isFirstScan) {
                    if (result.billingCycle) {
                      this.billingCycle = result.billingCycle;
                    } else if (result.yearlyPrice && !result.monthlyPrice && !result.quarterlyPrice) {
                      this.billingCycle = 'Yearly';
                    } else if (result.monthlyPrice && !result.yearlyPrice && !result.quarterlyPrice) {
                      this.billingCycle = 'Monthly';
                    }
                  }

                  // 根据当前选中的周期填充对应价格
                  if (this.billingCycle === 'Monthly' && this.ocrMonthlyPrice) {
                    this.price = this.ocrMonthlyPrice;
                  } else if (this.billingCycle === 'Quarterly' && this.ocrQuarterlyPrice) {
                    this.price = this.ocrQuarterlyPrice;
                  } else if (this.billingCycle === 'Yearly' && this.ocrYearlyPrice) {
                    this.price = this.ocrYearlyPrice;
                  } else if (this.billingCycle === 'Lifetime' && this.ocrLifetimePrice) {
                    this.price = this.ocrLifetimePrice;
                  } else if (result.price) {
                    this.price = result.price.toString();
                  }

                  // 更新分类和会员等级 (独立于应用名称)
                  if (result.category) {
                    this.category = result.category;
                  }
                  if (result.subCategory) {
                    this.subCategory = result.subCategory;
                    hilog.info(0x0000, 'AddSubscription', `AI Detected SubCategory: ${result.subCategory}`);
                  } else {
                    this.subCategory = '';
                  }

                  // 更新名称和图标
                  if (result.appName) {
                    this.isAIProtected = true; // 关键：开启保护，允许后续 searchHuaweiApps 自动匹配图标和分类，但禁止其覆盖识别出的精准等级
                    this.name = result.appName;
                    this.icon = result.serviceIcon || '';

                    // Update available sub-categories based on recognized name
                    const service = matchMemberService(this.name);
                    if (service) {
                      if (service.validSubCategories) {
                        this.availableSubCategories = service.validSubCategories;
                      } else {
                        this.availableSubCategories = [];
                      }

                      // [Fix] Enforce Fixed Billing Cycle & Default Price (Override AI errors like "285")
                      if (service.fixedBillingCycle) {
                        hilog.info(0x0000, 'AddSubscription',
                          `Enforcing fixed billing cycle: ${service.fixedBillingCycle} for ${service.name}`);
                        this.billingCycle = service.fixedBillingCycle;

                        // Re-evaluate price based on the enforced cycle
                        let enforcedPrice = '';
                        if (this.billingCycle === 'Yearly') {
                          if (this.ocrYearlyPrice && parseFloat(this.ocrYearlyPrice) > 0) {
                            enforcedPrice = this.ocrYearlyPrice;
                          }
                        } else if (this.billingCycle === 'Quarterly') {
                          if (this.ocrQuarterlyPrice && parseFloat(this.ocrQuarterlyPrice) > 0) {
                            enforcedPrice = this.ocrQuarterlyPrice;
                          }
                        } else if (this.billingCycle === 'Monthly') {
                          if (this.ocrMonthlyPrice && parseFloat(this.ocrMonthlyPrice) > 0) {
                            enforcedPrice = this.ocrMonthlyPrice;
                          }
                        }

                        // If no valid price found for the enforced cycle, or if we want to be strict
                        // Use default price if available and currently found price is empty OR looks suspicious (e.g. absent)
                        if (!enforcedPrice && service.defaultPrice) {
                          enforcedPrice = service.defaultPrice.toString();
                          hilog.info(0x0000, 'AddSubscription',
                            `Applied default price ${enforcedPrice} because specific cycle price was missing.`);
                        }

                        // Apply the enforced price
                        if (enforcedPrice) {
                          this.price = enforcedPrice;
                        }
                      }
                    } else {
                      this.availableSubCategories = [];
                    }

                    this.showOCRResult = true;
                  } else {
                    this.name = '';
                    this.icon = '';
                    this.showOCRResult = false;
                    this.availableSubCategories = [];
                  }

                  // 更新日期
                  if (result.date) {
                    this.nextBillingDate = new Date(result.date);
                    this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);

                    // [Smart Inference] 根据到期日反推开始日期
                    const inferredStart = new Date(this.nextBillingDate);
                    if (this.billingCycle === 'Monthly') {
                      // [Rule] 月付按 30 天推算 (用户指定逻辑: Expiration - 30 days)
                      inferredStart.setDate(inferredStart.getDate() - 30);
                    } else if (this.billingCycle === 'Quarterly') {
                      inferredStart.setMonth(inferredStart.getMonth() - 3);
                    } else if (this.billingCycle === 'Yearly') {
                      inferredStart.setFullYear(inferredStart.getFullYear() - 1);
                    } else if (this.billingCycle === 'Lifetime') {
                      // Lifetime: nextBillingDate is effectively purchase date
                    }
                    this.startDate = inferredStart;

                  } else {
                    // 默认过期时间逻辑
                    const target = new Date();

                    const sDate = new Date(); // Default start date is today for new entries without date

                    if (this.billingCycle === 'Yearly' ||
                      (result.yearlyPrice && !result.monthlyPrice && !result.quarterlyPrice)) {
                      target.setFullYear(target.getFullYear() + 1);
                    } else if (this.billingCycle === 'Quarterly' ||
                      (result.quarterlyPrice && !result.monthlyPrice && !result.yearlyPrice)) {
                      target.setMonth(target.getMonth() + 3);
                    } else {
                      target.setMonth(target.getMonth() + 1);
                    }

                    this.nextBillingDate = target;
                    this.startDate = sDate; // Set start date to today if no date found
                    this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
                  }
                });

                this.isOCRLoading = false;
                this.promptAction.showToast({ message: `AI识别完成` });

              } catch (e) {
                // 级联兜底: AI 失败后尝试本地 OCR
                console.error('AI识别失败，切换本地OCR:', JSON.stringify(e));
                this.promptAction.showToast({ message: 'AI服务繁忙，正在使用本地引擎...' });

                try {
                  if (!pixelMap) {
                    throw new Error('Image data not available');
                  }
                  if (!pixelMap) {
                    throw new Error('Image data not available');
                  }
                  let text = await OCRManager.getInstance().recognizeText(pixelMap);
                  if (!text) {
                    throw new Error('本地OCR未识别到文字');
                  }

                  let result: OCRResult;
                  if (this.recordType === 'groupBuy') {
                    result = GroupBuyOCRManager.getInstance().parseText(text);
                  } else {
                    result = OCRManager.getInstance().parseText(text);
                  }

                  animateTo({
                    duration: this.isAnimationEnabled ? this.animationDuration : 0,
                    curve: curves.springMotion(this.animationResponse, this.animationDamping)
                  }, () => {
                    // Group Buy Specific Logic
                    if (this.recordType === 'groupBuy') {
                      if (result.merchantName) {
                        this.merchantName = result.merchantName;
                      }
                      if (result.appName) {
                        this.name = result.appName;
                      } // Project Name
                      if (result.couponCode) {
                        this.couponCode = result.couponCode;
                      }
                      if (result.platform) {
                        this.platform = result.platform;
                      }

                      if (result.price) {
                        this.price = result.price.toString();
                      }

                      if (result.date) {
                        this.nextBillingDate = new Date(result.date);
                        this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
                        this.startDate = new Date(); // Start date essentially now for coupon
                      }

                      this.isOCRLoading = false;
                      this.promptAction.showToast({ message: '团购券识别完成' });
                      return;
                    }

                    // Existing Subscription Logic
                    // 更新基本信息
                    this.ocrMonthlyPrice = result.monthlyPrice ? result.monthlyPrice.toString() : '';
                    this.ocrQuarterlyPrice = result.quarterlyPrice ? result.quarterlyPrice.toString() : '';
                    this.ocrYearlyPrice = result.yearlyPrice ? result.yearlyPrice.toString() : '';
                    this.ocrLifetimePrice = result.lifetimePrice ? result.lifetimePrice.toString() : '';

                    // 周期推断
                    if (result.billingCycle) {
                      this.billingCycle = result.billingCycle;
                    } else if (result.yearlyPrice && !result.monthlyPrice) {
                      this.billingCycle = 'Yearly';
                    } else if (result.monthlyPrice && !result.yearlyPrice) {
                      this.billingCycle = 'Monthly';
                    }

                    // 价格填充
                    if (this.billingCycle === 'Monthly' && result.monthlyPrice) {
                      this.price = result.monthlyPrice.toString();
                    } else if (this.billingCycle === 'Quarterly' && result.quarterlyPrice) {
                      this.price = result.quarterlyPrice.toString();
                    } else if (this.billingCycle === 'Yearly' && result.yearlyPrice) {
                      this.price = result.yearlyPrice.toString();
                    } else if (this.billingCycle === 'Lifetime' && result.lifetimePrice) {
                      this.price = result.lifetimePrice.toString();
                    } else if (result.price) {
                      this.price = result.price.toString();
                    }

                    // 元数据
                    if (result.category) {
                      this.category = result.category;
                    }
                    if (result.subCategory) {
                      this.subCategory = result.subCategory;
                    } else {
                      this.subCategory = '';
                    }

                    if (result.appName) {
                      this.name = result.appName;
                      this.icon = result.serviceIcon || '';
                      this.showOCRResult = true;

                      const service = matchMemberService(this.name);
                      if (service && service.validSubCategories) {
                        this.availableSubCategories = service.validSubCategories;
                      } else {
                        this.availableSubCategories = [];
                      }
                    } else {
                      this.showOCRResult = false;
                      this.availableSubCategories = [];
                    }

                    // 日期
                    if (result.date) {
                      this.nextBillingDate = new Date(result.date);
                      this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);

                      // [Smart Inference] 根据到期日反推开始日期
                      const inferredStart = new Date(this.nextBillingDate);
                      if (this.billingCycle === 'Monthly') {
                        // [Rule] 月付按 30 天推算 (用户指定逻辑: Expiration - 30 days)
                        inferredStart.setDate(inferredStart.getDate() - 30);
                      } else if (this.billingCycle === 'Quarterly') {
                        inferredStart.setMonth(inferredStart.getMonth() - 3);
                      } else if (this.billingCycle === 'Yearly') {
                        inferredStart.setFullYear(inferredStart.getFullYear() - 1);
                      }
                      this.startDate = inferredStart;

                    } else {
                      const target = new Date();
                      this.startDate = new Date(); // Default today if no date found
                      target.setDate(target.getDate() + 31);
                      this.nextBillingDate = target;
                      this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
                    }
                  });

                  this.isOCRLoading = false;
                  this.promptAction.showToast({ message: '本地识别完成' });

                } catch (ocrError) {
                  this.isOCRLoading = false;
                  this.promptAction.showToast({ message: '识别失败，请手动输入' });
                }
              }
            })

            // 按钮 B: 闪控球截图
            Button() {
              Row() {
                SymbolGlyph($r('sys.symbol.crop'))
                  .fontSize(18)
                  .fontColor([this.isOCRLoading ? $r('app.color.text_secondary') :
                    (this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))])
                  .margin({ right: 6 })
                Text("闪控截屏")
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isOCRLoading ? $r('app.color.text_secondary') :
                    (this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))))
              }
              .justifyContent(FlexAlign.Center)
            }
            .layoutWeight(1)
            .height(50)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(14)
            .opacity(this.isOCRLoading ? 0.6 : 1.0)
            .enabled(!this.isOCRLoading)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.flashBallLight,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.isFlashBallPressed ? 0.98 : 1, y: this.isFlashBallPressed ? 0.98 : 1 })
            .animation({
              duration: this.isAnimationEnabled ? 150 : 0,
              curve: curves.springMotion(this.animationResponse, this.animationDamping)
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.isFlashBallPressed = true;
                  this.flashBallLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isFlashBallPressed = false;
                this.flashBallLight = hdsEffect.PointLightSourceType.NONE;
              }
            })
            .onClick(async () => {
              await this.startScreenshotCapture();
            })
          }
          .width('90%')
          .margin({  bottom: 20 })
          .opacity(this.animStep1 ? 1 : 0)
          .translate({ y: this.animStep1 ? 0 : 100 })
          .scale({ x: this.animStep1 ? 1 : 0.9, y: this.animStep1 ? 1 : 0.9 })


          // === 根据记录类型显示不同表单 ===
          if (this.recordType === 'groupBuy') {
            // 团购券预览卡片
            Row() {
              // 1. 图标区
              SubscriptionIcon({
                icon: this.getPreviewIcon(),
                name: this.merchantName || this.name,
                iconSize: 56,
                iconRadius: 14,
                showGroupBadge: true
              })
                .margin({ right: 16 })

              // 2. 信息区
              Column() {
                Text(this.merchantName || "商家名称")
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ bottom: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.name || "项目名称")
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ right: 12 })

              // 3. 价格区
              Column() {
                Text(`${this.currency === 'USD' ? '$' : '¥'}${this.price || '0.00'}`)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                    (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              }
              .alignItems(HorizontalAlign.End)
              .flexShrink(0)
            }
            .width('90%')
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            .margin({ bottom: 20 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({
              duration: this.isAnimationEnabled ? undefined : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }))

            // ========== 团购券专用表单 (优化版) ==========
            Column({ space: 24 }) {
              Column({ space: 12 }) {
                // 标题行
                Row() {
                  SymbolGlyph($r('sys.symbol.ticket_fill'))
                    .fontSize(18)
                    .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                    .margin({ right: 8 })
                  Text(this.recordType === 'groupBuy' ? "团购详情" : "订阅详情")
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)

                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .justifyContent(FlexAlign.Start)
                .margin({ bottom: 4 })

                // 1. 平台选择
                Row() {
                  Text("所属平台")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row({ space: 8 }) {
                    Button() {
                      Text("美团")
                        .fontSize(13)
                        .fontColor(this.platform === 'meituan' ?
                          (this.isNewYearTheme ? '#FFD700' :
                            (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                          $r('app.color.text_secondary'))
                    }
                    .linearGradient(this.platform === 'meituan' ?
                      (this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined)) : undefined)
                    .backgroundColor(this.platform === 'meituan' ?
                      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                      $r('app.color.card_background'))
                    .borderRadius(14)
                    .padding({
                      left: 14,
                      right: 14,
                      top: 6,
                      bottom: 6
                    })
                    .onClick(() => {
                      animateTo({
                        duration: this.isAnimationEnabled ? 200 : 0,
                        curve: this.isAnimationEnabled ?
                          curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                      }, () => {
                        this.platform = 'meituan';
                      });
                    })

                    Button() {
                      Text("抖音")
                        .fontSize(13)
                        .fontColor(this.platform === 'douyin' ?
                          (this.isNewYearTheme ? '#FFD700' :
                            (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                          $r('app.color.text_secondary'))
                    }
                    .linearGradient(this.platform === 'douyin' ?
                      (this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined)) : undefined)
                    .backgroundColor(this.platform === 'douyin' ?
                      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                      $r('app.color.card_background'))
                    .borderRadius(14)
                    .padding({
                      left: 14,
                      right: 14,
                      top: 6,
                      bottom: 6
                    })
                    .onClick(() => {
                      animateTo({
                        duration: this.isAnimationEnabled ? 200 : 0,
                        curve: this.isAnimationEnabled ?
                          curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                      }, () => {
                        this.platform = 'douyin';
                      });
                    })

                    Button() {
                      Text("大众点评")
                        .fontSize(13)
                        .fontColor(this.platform === 'dianping' ?
                          (this.isNewYearTheme ? '#FFD700' :
                            (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                          $r('app.color.text_secondary'))
                    }
                    .linearGradient(this.platform === 'dianping' ?
                      (this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined)) : undefined)
                    .backgroundColor(this.platform === 'dianping' ?
                      (this.isNewYearTheme || this.showVipTheme ? Color.Transparent : $r('app.color.brand_color')) :
                      $r('app.color.card_background'))
                    .borderRadius(14)
                    .padding({
                      left: 14,
                      right: 14,
                      top: 6,
                      bottom: 6
                    })
                    .onClick(() => {
                      animateTo({
                        duration: this.isAnimationEnabled ? 200 : 0,
                        curve: this.isAnimationEnabled ?
                          curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                      }, () => {
                        this.platform = 'dianping';
                      });
                    })
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isPlatformPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isPlatformPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isPlatformPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isPlatformPressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isPlatformPressed = false;
                  }
                })

                if (this.platform === 'dianping') {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_secondary')])
                    Text() {
                      Span("识别结果仅供参考，本APP不代替平台核销！团购券解释权归原平台及商家所有。为保证您的财产安全，团购券识别仅使用本地OCR能力识别，不使用AI识别。如果是多次团购券，您仅需录入第一个券码或者分开录入，感谢您的理解。\n")
                      Span("大众点评请在识别基本信息后，点击编辑二维码，打开券码页再次扫描。")
                        .fontWeight(FontWeight.Bold)
                    }
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ left: 4, top: 4, bottom: 4 })
                } else {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(14)
                      .fontColor([$r('app.color.text_secondary')])
                    Text() {
                      Span("识别结果仅供参考，本APP不代替平台核销！团购券解释权归原平台及商家所有。为保证您的财产安全，团购券识别仅使用本地OCR能力识别，不使用AI识别。如果是多次团购券，您仅需录入第一个券码或者分开录入，感谢您的理解。")
                    }
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ left: 4, top: 4, bottom: 4 })
                }

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 2. 商家名称
                Row() {
                  Text("商家名称")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ text: this.merchantName, placeholder: '输入商家名称' })
                    .width('60%')
                    .fontSize(15)
                    .textAlign(TextAlign.End)
                    .backgroundColor(Color.Transparent)
                    .placeholderColor($r('app.color.text_secondary'))
                    .onChange((value) => {
                      this.merchantName = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isMerchantPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isMerchantPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isMerchantPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isMerchantPressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isMerchantPressed = false;
                  }
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 3. 团购名称
                Row() {
                  Text("项目名称")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ text: this.name, placeholder: '如：双人晚餐套餐' })
                    .width('60%')
                    .fontSize(15)
                    .textAlign(TextAlign.End)
                    .backgroundColor(Color.Transparent)
                    .placeholderColor($r('app.color.text_secondary'))
                    .onChange((value) => {
                      this.name = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isNamePressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isNamePressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isNamePressed = false;
                  }
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 3.5 可用时间
                Row() {
                  Text("可用时间")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ text: this.usageTime, placeholder: '如：周一至周日' })
                    .layoutWeight(1)
                    .fontSize(15)
                    .textAlign(TextAlign.End)
                    .backgroundColor(Color.Transparent)
                    .placeholderColor($r('app.color.text_secondary'))
                    .onChange((value) => {
                      this.usageTime = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isUsageTimePressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isUsageTimePressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isUsageTimePressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isUsageTimePressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isUsageTimePressed = false;
                  }
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 4. 券码
                Row() {
                  Text("团购券码")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ text: this.couponCode, placeholder: '输入券码 (可选)' })
                    .layoutWeight(1)
                    .fontSize(14)
                    .textAlign(TextAlign.End)
                    .backgroundColor(Color.Transparent)
                    .placeholderColor($r('app.color.text_secondary'))
                    .onChange((value) => {
                      this.couponCode = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isCouponPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isCouponPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isCouponPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isCouponPressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isCouponPressed = false;
                  }
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 4.1 支付方式 (移动到截图上方，统一样式)
                Row() {
                  Text("支付方式")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))

                  Blank()

                  Row() {
                    Text(this.paymentMethod)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ right: 4 })
                      .fontWeight(FontWeight.Medium)

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isPaymentPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isPaymentPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isPaymentPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isPaymentPressed = true;
                  } else if (event.type ===
                  TouchType.Up || event.type === TouchType.Cancel) {
                    this.isPaymentPressed = false;
                  }
                })
                .onClick(() => {
                  const paymentMethods =
                    ['现金', '银行卡', '云闪付', '支付宝', '微信支付', '华为支付', '京东支付', '抖音支付',
                      '美团支付', '数字人民币', 'Apple Pay', 'PayPal', '其他支付方式'];
                  TextPickerDialog.show({
                    range: paymentMethods,
                    selected: paymentMethods.indexOf(this.paymentMethod),
                    selectedTextStyle: {
                      color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    acceptButtonStyle: {
                      fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    onAccept: (result: TextPickerResult) => {
                      animateTo({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0,
                        curve: curves.springMotion(this.animationResponse, this.animationDamping)
                      }, () => {
                        this.paymentMethod = result.value as string;
                      });
                    }
                  })
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 4.5 截取的二维码图片 (常驻显示并支持编辑)
                Column() {
                  Row() {
                    Text("券码截图")
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Button("编辑二维码", { type: ButtonType.Capsule })
                      .height(24)
                      .fontSize(11)
                      .fontColor(this.isNewYearTheme ? '#FFD700' :
                        (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                      .linearGradient(this.isNewYearTheme ? {
                        angle: 135,
                        colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                      } :
                        (this.showVipTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                        } : undefined))
                      .backgroundColor(this.isNewYearTheme || this.showVipTheme ? Color.Transparent :
                        $r('app.color.brand_color'))
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: (this.isAnimationEnabled && this.isPointLightEnabled &&
                          this.isEditQRPressed) ? hdsEffect.PointLightSourceType.BRIGHT :
                            hdsEffect.PointLightSourceType.NONE,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({
                        x: (this.isAnimationEnabled && this.isEditQRPressed) ? 0.95 : 1,
                        y: (this.isAnimationEnabled && this.isEditQRPressed) ? 0.95 : 1
                      })
                      .animation({
                        duration: this.isAnimationEnabled ? 150 : 0,
                        curve: curves.springMotion(this.animationResponse, this.animationDamping)
                      })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          this.isEditQRPressed = true;
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isEditQRPressed = false;
                        }
                      })
                      .onClick(() => {
                        this.recognizeQRCodeOnly();
                      })
                  }
                  .width('100%')
                  .margin({ bottom: 8 })

                  if (this.couponImage) {
                    Image(this.couponImage)
                      .width('100%')
                      .height(100)
                      .borderRadius(8)
                      .objectFit(ImageFit.Contain)
                      .backgroundColor($r('app.color.card_background'))
                      .onClick(() => {
                        this.recognizeQRCodeOnly();
                      })
                  } else {
                    Stack() {
                      Rect()
                        .fill($r('app.color.card_background'))
                        .borderRadius(8)
                        .width('100%')
                        .height(80)

                      Column({ space: 4 }) {
                        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                          .fontSize(20)
                          .fontColor([$r('app.color.text_secondary')])
                          .opacity(0.5)
                        Text("点击“编辑二维码”截取券码图片")
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .opacity(0.6)
                      }
                    }
                    .onClick(() => {
                      this.recognizeQRCodeOnly();
                    })
                  }
                }
                .width('100%')
                .padding({
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: 12
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 5. 金额输入 (对齐订阅样式)
                Column({ space: 0 }) {
                  Text("总计金额")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .margin({ bottom: 12 })

                  Row({ space: 4 }) {
                    Text(this.currency === 'USD' ? '$' : '¥')
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))

                    TextInput({ placeholder: '0.00', text: this.price })
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderFont({ size: 36, weight: FontWeight.Bold })
                      .placeholderColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.Start)
                      .backgroundColor(Color.Transparent)
                      .type(InputType.NUMBER_DECIMAL)
                      .maxLength(10)
                      .caretColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                      .padding(0)
                      .layoutWeight(1)
                      .onChange((value: string) => {
                        this.price = value;
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Bottom)
                  .margin({ bottom: 12 })

                  Divider()
                    .color($r('app.color.divider_color'))
                    .strokeWidth(1)

                  Row() {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_secondary')])
                      .opacity(0.6)
                      .margin({ right: 4 })

                    Text("请填写您实际支付的团购总金额。")
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .opacity(0.6)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }
                .width('100%')

                // 移除总计金额压感效果，保持静默显示

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 6. 数量
                Row() {
                  Text("购买数量")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row({ space: 16 }) {
                    Button() {
                      SymbolGlyph($r('sys.symbol.minus'))
                        .fontSize(18)
                        .fontColor([$r('app.color.text_primary')])
                    }
                    .width(32)
                    .height(32)
                    .backgroundColor($r('app.color.page_background')) // 还原为页面背景色
                    .shadow({ radius: 4, color: '#10000000' })
                    .borderRadius(10)
                    .enabled(this.quantity > 1)
                    .scale({
                      x: (this.isAnimationEnabled && this.isMinusPressed) ? 0.9 : 1,
                      y: (this.isAnimationEnabled && this.isMinusPressed) ? 0.9 : 1
                    })
                    .animation({
                      duration: this.isAnimationEnabled ? 150 : 0,
                      curve: curves.springMotion(this.animationResponse, this.animationDamping)
                    })
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        this.isMinusPressed = true;
                      } else if (event.type ===
                      TouchType.Up || event.type === TouchType.Cancel) {
                        this.isMinusPressed = false;
                      }
                    })
                    .onClick(() => {
                      if (this.quantity > 1) {
                        this.quantity--;
                      }
                    })

                    Text(this.quantity.toString())
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .fontWeight(FontWeight.Bold)

                    Button() {
                      SymbolGlyph($r('sys.symbol.plus'))
                        .fontSize(18)
                        .fontColor([$r('app.color.text_primary')])
                    }
                    .width(32)
                    .height(32)
                    .backgroundColor($r('app.color.page_background'))
                    .shadow({ radius: 4, color: '#10000000' })
                    .borderRadius(10)
                    .scale({
                      x: (this.isAnimationEnabled && this.isPlusPressed) ? 0.9 : 1,
                      y: (this.isAnimationEnabled && this.isPlusPressed) ? 0.9 : 1
                    })
                    .animation({
                      duration: this.isAnimationEnabled ? 150 : 0,
                      curve: curves.springMotion(this.animationResponse, this.animationDamping)
                    })
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        this.isPlusPressed = true;
                      } else if (event.type ===
                      TouchType.Up || event.type === TouchType.Cancel) {
                        this.isPlusPressed = false;
                      }
                    })
                    .onClick(() => {
                      this.quantity++;
                    })
                  }
                }
                .width('100%')
                .padding({ left: 0, right: 0 }) // 移除 Padding 确保标题对齐

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 7. 到期日期
                Row() {
                  Text("券码有效期")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row() {
                    Text(DateUtil.formatDate(this.nextBillingDate))
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .fontWeight(FontWeight.Medium)
                      .margin({ right: 6 })
                    SymbolGlyph($r('sys.symbol.calendar'))
                      .fontSize(16)
                      .fontColor([this.isNewYearTheme ? '#FFD700' :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                  }
                  .padding({
                    left: 12,
                    right: 10,
                    top: 6,
                    bottom: 6
                  })
                  .backgroundColor($r('app.color.page_background')) // 内部气泡背景
                  .borderRadius(8)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isDatePressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({
                    x: (this.isAnimationEnabled && this.isDatePressed) ? 0.98 : 1,
                    y: (this.isAnimationEnabled && this.isDatePressed) ? 0.98 : 1
                  })
                  .animation({
                    duration: this.isAnimationEnabled ? 150 : 0,
                    curve: curves.springMotion(this.animationResponse, this.animationDamping)
                  })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isDatePressed = true;
                    } else if (event.type ===
                    TouchType.Up || event.type === TouchType.Cancel) {
                      this.isDatePressed = false;
                    }
                  })
                  .onClick(() => {
                    DatePickerDialog.show({
                      selected: this.nextBillingDate,
                      selectedTextStyle: {
                        color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                      },
                      onDateAccept: (value: Date) => {
                        this.nextBillingDate = value;
                      }
                    });
                  })
                }
                .width('100%')
                .padding({ left: 0, right: 0 })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 8. 使用状态
                Row() {
                  Text("使用状态")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row({ space: 4 }) {
                    ForEach(['unused', 'used', 'expired'], (status: string) => {
                      Button() {
                        Text(status === 'unused' ? "未使用" : status === 'used' ? "已使用" : "已过期")
                          .fontSize(12)
                          .fontColor(this.usageStatus === status ?
                            (this.isNewYearTheme ? '#FFD700' :
                              (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                            $r('app.color.text_secondary'))
                      }
                      .height(28)
                      .linearGradient(this.usageStatus === status ?
                        (this.isNewYearTheme ? {
                          angle: 135,
                          colors: [[$r('app.color.new_year_red_start'), 0.0],
                            [$r('app.color.new_year_red_end'), 1.0]]
                        } :
                          (this.showVipTheme ? {
                            angle: 135,
                            colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                          } : undefined)) : undefined)
                      .backgroundColor(this.usageStatus === status ?
                        (this.isNewYearTheme || this.showVipTheme ? Color.Transparent :
                          $r('app.color.brand_color')) :
                        $r('app.color.page_background')) // 内部按钮背景还原
                      .borderRadius(8)
                      .padding({ left: 10, right: 10 })
                      .scale({
                        x: (this.isAnimationEnabled && this.pressedUsageStatus === status) ? 0.95 : 1,
                        y: (this.isAnimationEnabled && this.pressedUsageStatus === status) ? 0.95 : 1
                      })
                      .animation({
                        duration: this.isAnimationEnabled ? 150 : 0,
                        curve: curves.springMotion(this.animationResponse, this.animationDamping)
                      })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          this.pressedUsageStatus = status;
                        } else if (event.type ===
                        TouchType.Up || event.type === TouchType.Cancel) {
                          this.pressedUsageStatus = '';
                        }
                      })
                      .onClick(() => {
                        animateTo({
                          duration: this.isAnimationEnabled ? 200 : 0,
                          curve: this.isAnimationEnabled ?
                            curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear
                        }, () => {
                          this.usageStatus = status as 'unused' | 'used' | 'expired';
                          // 如果切换到已使用，记录当前时间
                          if (this.usageStatus === 'used') {
                            this.realUsageTime = new Date().getTime();
                          } else {
                            this.realUsageTime = undefined;
                          }
                        });
                      })
                    })
                  }
                }
                .width('100%')
                .padding({ left: 0, right: 0 })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 9. 到期提醒 (置底对齐订阅设计)
                Column({ space: 12 }) {
                  Row() {
                    Text("到期提醒")
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .layoutWeight(1)

                    Toggle({ type: ToggleType.Switch, isOn: this.isReminderEnabled })
                      .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                      .switchPointColor(Color.White)
                      .onChange((isOn: boolean) => {
                        this.isReminderEnabled = isOn;
                        if (this.isAnimationEnabled) {
                          if (isOn) {
                            animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                              this.isReminderExpanded = true;
                              this.reminderOpacity = 1;
                            })
                          } else {
                            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                              this.reminderOpacity = 0;
                            });
                            setTimeout(() => {
                              animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                                this.isReminderExpanded = false;
                              });
                            }, 200);
                          }
                        } else {
                          this.isReminderExpanded = isOn;
                          this.reminderOpacity = isOn ? 1 : 0;
                        }
                      })
                  }
                  .width('100%')

                  if (this.isReminderExpanded) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.info_circle'))
                        .fontSize(12)
                        .fontColor([$r('app.color.text_secondary')])
                        .margin({ right: 4 })

                      Text("提示音为系统默认闹钟铃声，可能会出现铃声过大问题，可通过调整系统闹钟音量调整本应用提示音量。请合理设置提醒时间，避免过度滥用提醒功能。本应用不对因提醒失效导致的任何损失承担责任。")
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .margin({ top: -4, bottom: 8 })
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
                      .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
                    .opacity(this.reminderOpacity)

                    Row() {
                      Blank()
                      // 提前天数
                      Row() {
                        Text(`提前 ${this.reminderDaysBefore} 天`)
                          .fontSize(14)
                          .fontColor($r('app.color.text_primary'))
                      }
                      .height(32)
                      .padding({ left: 10, right: 10 })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(8)
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: this.reminderDaysLight,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({ x: this.isReminderDaysPressed ? 0.98 : 1, y: this.isReminderDaysPressed ? 0.98 : 1 })
                      .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          if (this.isAnimationEnabled && this.isPointLightEnabled) {
                            this.isReminderDaysPressed = true;
                            this.reminderDaysLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isReminderDaysPressed = false;
                          this.reminderDaysLight = hdsEffect.PointLightSourceType.NONE;
                        }
                      })
                      .onClick(() => {
                        TextPickerDialog.show({
                          range: this.reminderDaysOptions,
                          selected: this.reminderDaysOptions.indexOf(this.reminderDaysBefore.toString()),
                          selectedTextStyle: {
                            color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          acceptButtonStyle: {
                            fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          onAccept: (value: TextPickerResult) => {
                            this.reminderDaysBefore = parseInt(value.value as string);
                          }
                        })
                      })
                      .margin({ right: 12 })

                      // 提醒时间
                      Row() {
                        Text(this.reminderTime)
                          .fontSize(14)
                          .fontColor($r('app.color.text_primary'))
                      }
                      .height(32)
                      .padding({ left: 10, right: 10 })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(8)
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: this.reminderTimeLight,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({ x: this.isReminderTimePressed ? 0.98 : 1, y: this.isReminderTimePressed ? 0.98 : 1 })
                      .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          if (this.isAnimationEnabled && this.isPointLightEnabled) {
                            this.isReminderTimePressed = true;
                            this.reminderTimeLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isReminderTimePressed = false;
                          this.reminderTimeLight = hdsEffect.PointLightSourceType.NONE;
                        }
                      })
                      .onClick(() => {
                        const timeParts = this.reminderTime.split(':');
                        const selectedHour = parseInt(timeParts[0]);
                        const selectedMinute = parseInt(timeParts[1]);
                        const selectedDate = new Date();
                        selectedDate.setHours(selectedHour, selectedMinute);

                        TimePickerDialog.show({
                          selected: selectedDate,
                          selectedTextStyle: {
                            color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          acceptButtonStyle: {
                            fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          onAccept: (value: TimePickerResult) => {
                            const h = value.hour.toString().padStart(2, '0');
                            const m = value.minute.toString().padStart(2, '0');
                            this.reminderTime = `${h}:${m}`;
                          }
                        })
                      })
                    }
                    .width('100%')
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
                      .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
                    .opacity(this.reminderOpacity)
                  }
                }
                .width('100%')
              }
            }
            .padding(20)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(24)
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            .width('90%')
            .opacity(this.animStep2 ? 1 : 0)
            .translate({ y: this.animStep2 ? 0 : 20 })
            .margin({ bottom: 32 })
            .borderRadius(24)
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            .width('90%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({
              duration: this.isAnimationEnabled ? undefined : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }))

          } else if (this.recordType === 'warranty') {
            // ========== 保修/保质期专属表单 ==========

            // 预览卡片
            Row() {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  SubscriptionIcon({
                    icon: this.icon,
                    name: this.name,
                    iconSize: 56,
                    iconRadius: 14,
                    showGroupBadge: false
                  })

                  // 编辑角标
                  Row() {
                    SymbolGlyph($r('sys.symbol.square_and_pencil'))
                      .fontSize(10)
                      .fontColor([Color.White])
                  }
                  .width(20)
                  .height(20)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                    (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                  .borderRadius(10)
                  .border({ width: 2, color: $r('app.color.card_background') })
                  .offset({ x: 6, y: 6 })
                }
                .onClick(() => {
                  this.showIconPickerSheet();
                })
                .margin({ right: 16 })

              Column() {
                Text(this.name || "物品名称")
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ bottom: 4 })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.brand ? `${this.brand}${this.purchaseChannel ? ' · ' + this.purchaseChannel : ''}` : "品牌 · 购买渠道")
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ right: 12 })

              Column() {
                Text(`${this.currency === 'USD' ? '$' : '¥'}${this.getTotalPrice()}`)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                    (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              }
              .alignItems(HorizontalAlign.End)
              .flexShrink(0)
            }
            .width('90%')
            .padding(16)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            .margin({ bottom: 20 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({
              duration: this.isAnimationEnabled ? undefined : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }))

            // 保修期表单卡片
            Column({ space: 24 }) {
              Column({ space: 12 }) {
                // 标题行
                Row() {
                  SymbolGlyph($r('sys.symbol.checkmark_shield'))
                    .fontSize(18)
                    .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                    .margin({ right: 8 })
                  Text("保修详情")
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)

                  Blank()

                  Text("建议您先选择物品分类后再填写")
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .justifyContent(FlexAlign.Start)
                .margin({ bottom: 4 })

                // 1. 物品名称
                Row() {
                  Text("物品名称")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ placeholder: '请输入物品名称', text: this.name })
                    .width('60%')
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_secondary'))
                    .backgroundColor(Color.Transparent)
                    .textAlign(TextAlign.End)
                    .onChange((value: string) => {
                      this.name = value;
                      // 实时推断分类并同步图标
                      if (this.recordType === 'warranty' && value) {
                        const matched = matchWarrantyCategory(value);
                        if (matched !== '其他物品') {
                          this.category = matched;
                          this.icon = 'warranty_icon:' + matched;
                        }
                      }
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isNamePressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isNamePressed = true;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isNamePressed = false;
                  }
                })

                // 2. 品牌
                Row() {
                  Text("品牌")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ placeholder: '请输入品牌名称', text: this.brand })
                    .width('60%')
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_secondary'))
                    .backgroundColor(Color.Transparent)
                    .textAlign(TextAlign.End)
                    .onChange((value: string) => {
                      this.brand = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isBrandPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isBrandPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isBrandPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isBrandPressed = true;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isBrandPressed = false;
                  }
                })

                // 3. 购买渠道
                Row() {
                  Text("购买渠道")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  TextInput({ placeholder: '选填', text: this.purchaseChannel })
                    .width('60%')
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_secondary'))
                    .backgroundColor(Color.Transparent)
                    .textAlign(TextAlign.End)
                    .onChange((value: string) => {
                      this.purchaseChannel = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isChannelPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isChannelPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isChannelPressed) ? 0.98 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isChannelPressed = true;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isChannelPressed = false;
                  }
                })

                // 3.1 物品分类
                Row() {
                  Text("物品分类")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row() {
                    Text(this.category || '请选择分类')
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .fontWeight(FontWeight.Medium)
                      .margin({ right: 6 })
                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                  .padding({ left: 12, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(8)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isWarrantyCategoryPressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({ x: this.isWarrantyCategoryPressed ? 0.98 : 1, y: this.isWarrantyCategoryPressed ? 0.98 : 1 })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isWarrantyCategoryPressed = true;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isWarrantyCategoryPressed = false;
                    }
                  })
                  .onClick(() => {
                    this.showWarrantyCategorySheet = true;
                  })
                }
                .width('100%')

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 4. 购买日期 (startDate)
                Row() {
                  Text("购买日期")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row() {
                    Text(DateUtil.formatDate(this.startDate || new Date().getTime()))
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .fontWeight(FontWeight.Medium)
                      .margin({ right: 6 })
                    SymbolGlyph($r('sys.symbol.calendar'))
                      .fontSize(16)
                      .fontColor([this.isNewYearTheme ? '#FFD700' :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                  }
                  .padding({ left: 12, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(8)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isStartDatePressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
                    })
                    .buildEffect())
                  .scale({ x: this.isStartDatePressed ? 0.98 : 1, y: this.isStartDatePressed ? 0.98 : 1 })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isStartDatePressed = true;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isStartDatePressed = false;
                    }
                  })
                  .onClick(() => {
                    DatePickerDialog.show({
                      selected: new Date(this.startDate || new Date().getTime()),
                      selectedTextStyle: {
                        color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                      },
                      onDateAccept: (value: Date) => {
                        this.startDate = value;
                      }
                    });
                  })
                }
                .width('100%')

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 5. 保修到期日期 (nextBillingDate)
                Row() {
                  Text("到期日期")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row() {
                    Text(DateUtil.formatDate(this.nextBillingDate))
                      .fontSize(15)
                      .fontColor($r('app.color.text_primary'))
                      .fontWeight(FontWeight.Medium)
                      .margin({ right: 6 })
                    SymbolGlyph($r('sys.symbol.calendar'))
                      .fontSize(16)
                      .fontColor([this.isNewYearTheme ? '#FFD700' :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                  }
                  .padding({ left: 12, right: 10, top: 6, bottom: 6 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(8)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isDatePressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
                    })
                    .buildEffect())
                  .scale({ x: this.isDatePressed ? 0.98 : 1, y: this.isDatePressed ? 0.98 : 1 })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isDatePressed = true;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isDatePressed = false;
                    }
                  })
                  .onClick(() => {
                    DatePickerDialog.show({
                      selected: this.nextBillingDate,
                      selectedTextStyle: {
                        color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                      },
                      onDateAccept: (value: Date) => {
                        this.nextBillingDate = value;
                      }
                    });
                  })
                }
                .width('100%')

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 6. 购买价格
                Column({ space: 0 }) {
                  Text("购买价格")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .margin({ bottom: 12 })

                  Row({ space: 4 }) {
                    Text(this.currency === 'USD' ? '$' : '¥')
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))

                    TextInput({ placeholder: '0.00', text: this.price })
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderFont({ size: 36, weight: FontWeight.Bold })
                      .placeholderColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.Start)
                      .backgroundColor(Color.Transparent)
                      .type(InputType.NUMBER_DECIMAL)
                      .maxLength(10)
                      .caretColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                      .padding(0)
                      .layoutWeight(1)
                      .onChange((value: string) => {
                        this.price = value;
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Bottom)
                  .margin({ bottom: 12 })

                  Divider().color($r('app.color.divider_color')).strokeWidth(1)
                }
                .width('100%')

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 7. 附加保障服务 (可选 - 多项模式)
                Column({ space: 0 }) {
                  Row() {
                    Text("附加保障服务 (可选)")
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    // 新增按钮
                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.plus'))
                        .fontSize(18)
                        .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                    }
                    .width(28)
                    .height(28)
                    .backgroundColor($r('app.color.page_background'))
                    .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
                    .onClick(() => {
                      animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                        this.extendedWarranties.push(new ExtendedWarrantyItem(
                          util.generateRandomUUID(true),
                          '',
                          '',
                          new Date().getTime()
                        ));
                      })
                    })
                  }
                  .width('100%')
                  .margin({ bottom: 8 })
                  
                  if (this.extendedWarranties.length > 0) {
                    Column({ space: 12 }) {
                      ForEach(this.extendedWarranties, (item: ExtendedWarrantyItem, index: number) => {
                        ExtendedWarrantyItemView({
                          item: item,
                          index: index,
                          currency: this.currency,
                          isNewYearTheme: this.isNewYearTheme,
                          showVipTheme: this.showVipTheme,
                          animationDuration: this.animationDuration,
                          isParentReminderEnabled: this.isReminderEnabled,
                          onDelete: (id: string) => {
                            animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                              this.extendedWarranties = this.extendedWarranties.filter(w => w.id !== id);
                            })
                          }
                        })
                      }, (item: ExtendedWarrantyItem) => item.id)

                    }
                    .width('100%')
                  } else {
                    Text("点击右上角 + 添加保障服务")
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .opacity(0.6)
                      .textAlign(TextAlign.Center)
                      .width('100%')
                      .margin({ top: 4, bottom: 4 })
                  }
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background')) // 使用 card_background 增加层次感
                .borderRadius(16)
                .margin({ bottom: 12 })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 8. 到期提醒
                Column({ space: 12 }) {
                  Row() {
                    Text("到期提醒")
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .layoutWeight(1)

                    Toggle({ type: ToggleType.Switch, isOn: this.isReminderEnabled })
                      .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                      .switchPointColor(Color.White)
                      .onChange((isOn: boolean) => {
                        this.isReminderEnabled = isOn;
                        if (this.isAnimationEnabled) {
                          if (isOn) {
                            animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                              this.isReminderExpanded = true;
                              this.reminderOpacity = 1;
                            })
                          } else {
                            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                              this.reminderOpacity = 0;
                            });
                            setTimeout(() => {
                              animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                                this.isReminderExpanded = false;
                              });
                            }, 200);
                          }
                        } else {
                          this.isReminderExpanded = isOn;
                          this.reminderOpacity = isOn ? 1 : 0;
                        }
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  if (this.isReminderExpanded) {
                    Row() {
                      SymbolGlyph($r('sys.symbol.info_circle'))
                        .fontSize(12)
                        .fontColor([$r('app.color.text_secondary')])
                        .margin({ right: 4 })

                      Text("提示音为系统默认闹钟铃声，可能会出现铃声过大问题，可通过调整系统闹钟音量调整本应用提示音量。请合理设置提醒时间，避免过度滥用提醒功能。本应用不对因提醒失效导致的任何损失承担责任。")
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .margin({ top: -4, bottom: 8 })
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
                      .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
                    .opacity(this.reminderOpacity)
                  }

                  if (this.isReminderExpanded) {
                    Row() {
                      Blank()
                      // 提前天数
                      Row() {
                        Text(`提前 ${this.reminderDaysBefore} 天`)
                          .fontSize(14)
                          .fontColor($r('app.color.text_primary'))
                      }
                      .height(32)
                      .padding({ left: 10, right: 10 })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(8)
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: this.reminderDaysLight,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({
                        x: this.isReminderDaysPressed ? 0.98 : 1,
                        y: this.isReminderDaysPressed ? 0.98 : 1
                      })
                      .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          if (this.isAnimationEnabled && this.isPointLightEnabled) {
                            this.isReminderDaysPressed = true;
                            this.reminderDaysLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isReminderDaysPressed = false;
                          this.reminderDaysLight = hdsEffect.PointLightSourceType.NONE;
                        }
                      })
                      .onClick(() => {
                        TextPickerDialog.show({
                          range: this.reminderDaysOptions,
                          selected: this.reminderDaysOptions.indexOf(this.reminderDaysBefore.toString()),
                          selectedTextStyle: {
                            color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          acceptButtonStyle: {
                            fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          onAccept: (value: TextPickerResult) => {
                            this.reminderDaysBefore = parseInt(value.value as string);
                          }
                        })
                      })
                      .margin({ right: 12 })

                      // 提醒时间
                      Row() {
                        Text(this.reminderTime)
                          .fontSize(14)
                          .fontColor($r('app.color.text_primary'))
                      }
                      .height(32)
                      .padding({ left: 10, right: 10 })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(8)
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: this.reminderTimeLight,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({
                        x: this.isReminderTimePressed ? 0.98 : 1,
                        y: this.isReminderTimePressed ? 0.98 : 1
                      })
                      .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          if (this.isAnimationEnabled && this.isPointLightEnabled) {
                            this.isReminderTimePressed = true;
                            this.reminderTimeLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isReminderTimePressed = false;
                          this.reminderTimeLight = hdsEffect.PointLightSourceType.NONE;
                        }
                      })
                      .onClick(() => {
                        const timeParts = this.reminderTime.split(':');
                        const selectedHour = parseInt(timeParts[0]);
                        const selectedMinute = parseInt(timeParts[1]);
                        const selectedDate = new Date();
                        selectedDate.setHours(selectedHour, selectedMinute);

                        TimePickerDialog.show({
                          selected: selectedDate,
                          selectedTextStyle: {
                            color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          acceptButtonStyle: {
                            fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          onAccept: (value: TimePickerResult) => {
                            const h = value.hour.toString().padStart(2, '0');
                            const m = value.minute.toString().padStart(2, '0');
                            this.reminderTime = `${h}:${m}`;
                          }
                        })
                      })
                    }
                    .width('100%')
                    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
                    .opacity(this.reminderOpacity)
                  }
                }
                .width('100%')
              }
            }
            .padding(20)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(24)
            .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            .width('90%')
            .opacity(this.animStep2 ? 1 : 0)
            .translate({ y: this.animStep2 ? 0 : 20 })
            .margin({ bottom: 32 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({
              duration: this.isAnimationEnabled ? undefined : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }))

          } else {
            // ========== 订阅表单区域 (原有逻辑) ==========

            // OCR 识别结果预览卡片
            if (this.showOCRResult) {
              Row() {
                // 1. 图标区 (可点击自定义)
                Stack({ alignContent: Alignment.Center }) {
                  SubscriptionIcon({
                    icon: this.icon,
                    name: this.name,
                    iconSize: 56,
                    iconRadius: 14, // 保持圆角矩形风格 (56/4 = 14)
                    showGroupBadge: false
                  })

                  // 编辑提示角标 - 移至左下角或右上角，避免与右下角的团购标识重合
                  Stack({ alignContent: Alignment.Center }) {
                    Circle()
                      .width(20)
                      .height(20)
                      .fill(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                    SymbolGlyph($r('sys.symbol.square_and_pencil'))
                      .fontSize(10)
                      .fontColor([Color.White])
                  }
                  .position({ right: -6, bottom: -6 }) // 移至右下角
                }
                .width(56)
                .height(56)
                .margin({ right: 16 })
                .flexShrink(0)
                .onClick(() => {
                  this.showIconPickerSheet();
                })

                // 2. 信息区 (名称 + 到期标签)
                Column() {
                  Text(this.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ bottom: 4 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (this.billingCycle === 'Lifetime') {
                    Text("永久有效")
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .padding({
                        left: 6,
                        right: 6,
                        top: 2,
                        bottom: 2
                      })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(4)
                  } else if (this.ocrExpireDate) {
                    Text(`到期: ${this.ocrExpireDate}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .padding({
                        left: 6,
                        right: 6,
                        top: 2,
                        bottom: 2
                      })
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(4)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ right: 12 })

                // 3. 价格区 (显示当前识别/输入的金额)
                Column() {
                  Text(`${this.currency === 'USD' ? '$' : '¥'}${this.price || '0.00'}`)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))

                  Text(this.getBillingCycleText(this.billingCycle))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.End)
                .flexShrink(0)
              }
              .width('90%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16)
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.ocrCardLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .scale({ x: this.isOCRCardPressed ? 0.98 : 1, y: this.isOCRCardPressed ? 0.98 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => { // Allow interaction on the card wrapper
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isOCRCardPressed = true;
                    this.ocrCardLight = hdsEffect.PointLightSourceType.BRIGHT;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isOCRCardPressed = false;
                  this.ocrCardLight = hdsEffect.PointLightSourceType.NONE;
                }
              })
              .margin({ bottom: 20 })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })),
                TransitionEffect.OPACITY
              )
                .animation({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: Curve.EaseInOut
                }))
            }

            // 3. 订阅详情录入区
            Column({ space: 24 }) {
              Column({ space: 12 }) {
                Row() {
                  SymbolGlyph($r('sys.symbol.paperplane_fill'))
                    .fontSize(18)
                    .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                    .margin({ right: 8 })
                  Text("服务详情")
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))

                  Text("    识别结果含AI生成内容\n    仅供参考，请仔细甄别！")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 4, top: 2 })
                    .opacity(0.8)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .margin({ bottom: 4 })

                // 1. 订阅名称
                Column() {
                  Row() {
                    Text((this.recordType as string) === 'groupBuy' ? "团购名称" : "订阅应用名称")
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))

                    Blank()

                    TextInput({ placeholder: '例如: 华为视频', text: this.name })
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.End)
                      .backgroundColor(Color.Transparent)
                      .padding(0)
                      .height(40)
                      .layoutWeight(1)
                      .onChange((value: string) => {
                        this.name = value;
                        // ... (逻辑保持不变)
                        if (this.skipNextSearch) {
                          this.skipNextSearch = false;
                          return;
                        }
                        if (value.length > 0) {
                          const localResults = searchMemberServices(value);
                          animateTo({
                            duration: this.isAnimationEnabled ? this.animationDuration : 0,
                            curve: Curve.EaseOut
                          }, () => {
                            this.suggestions = localResults;
                            this.showSuggestions = localResults.length > 0;
                          });
                          if (this.searchTimer !== -1) {
                            clearTimeout(this.searchTimer);
                          }
                          this.searchTimer = setTimeout(() => {
                            this.searchHuaweiApps(value);
                          }, 500);
                          const matched: MemberServiceConfig | undefined = matchMemberService(value);
                          if (matched) {
                            this.icon = matched.icon || '';
                            if (matched.category) {
                              this.category = matched.category;
                            }
                            if (matched.validSubCategories) {
                              this.availableSubCategories = matched.validSubCategories;
                            } else {
                              this.availableSubCategories = [];
                            }
                          } else {
                            if (this.icon.startsWith('resource:')) {
                              this.icon = '';
                            }
                          }
                          animateTo({
                            duration: this.isAnimationEnabled ? this.animationDuration : 0,
                            curve: Curve.EaseInOut
                          }, () => {
                            this.showOCRResult = true;
                          })
                        } else {
                          animateTo({
                            duration: this.isAnimationEnabled ? this.animationDuration : 0,
                            curve: Curve.EaseIn
                          }, () => {
                            this.suggestions = [];
                            this.showSuggestions = false;
                            this.showOCRResult = false;
                          });
                        }
                      })
                  }
                  .width('100%')
                  .height(56)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(12)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isNamePressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({
                    x: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1,
                    y: (this.isAnimationEnabled && this.isNamePressed) ? 0.98 : 1
                  })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isNamePressed = true;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isNamePressed = false;
                    }
                  })

                  // 快速选择标签 - 横向滚动
                  if (this.showSuggestions && this.suggestions.length > 0) {
                    Scroll() {
                      Row({ space: 8 }) {
                        ForEach(this.suggestions, (service: MemberServiceConfig) => {
                          Row({ space: 6 }) {
                            if (service.icon && service.icon.startsWith('resource:')) {
                              Image(resolveIcon(service.icon))
                                .width(18)
                                .height(18)
                                .borderRadius(4)
                            } else if (service.icon &&
                              (service.icon.startsWith('http') || service.icon.startsWith('file://'))) {
                              Image(service.icon)
                                .width(18)
                                .height(18)
                                .borderRadius(4)
                            } else {
                              Text(service.name.charAt(0))
                                .fontSize(12)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                                  (this.showVipTheme ? $r('app.color.sub_card_vip_text') :
                                    $r('app.color.brand_color')))
                            }

                            Text(service.name)
                              .fontSize(13)
                              .fontColor($r('app.color.text_primary'))
                              .maxLines(1)
                          }
                          .height(36)
                          .padding({ left: 10, right: 12 })
                          .backgroundColor($r('app.color.card_background'))
                          .borderRadius(18)
                          .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
                          .onClick(() => {
                            this.skipNextSearch = true;
                            this.name = service.name;
                            this.icon = service.icon || '';
                            const matched: MemberServiceConfig | undefined = matchMemberService(service.name);
                            if (matched) {
                              this.category = matched.category || service.category || '其他';
                              this.subCategory = matched.subCategory || '';
                              if (matched.validSubCategories) {
                                this.availableSubCategories =
                                  matched.validSubCategories;
                              }
                            } else {
                              this.category = service.category || '其他';
                              this.subCategory = service.subCategory || '';
                              this.availableSubCategories = [];
                            }
                            this.suggestions = [];
                            this.showSuggestions = false;
                            animateTo({
                              duration: this.isAnimationEnabled ? this.animationDuration : 0,
                              curve: Curve.EaseInOut
                            }, () => {
                              this.showOCRResult = true;
                            });
                          })
                        })
                      }
                      .padding({ top: 4, bottom: 4 })
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .scrollBar(BarState.Off)
                    .width('100%')
                    .margin({ top: 8 })
                  }
                }
                .alignItems(HorizontalAlign.Start)

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 1.5 会员等级
                Column() {
                  Row() {
                    Text("会员等级")
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))

                    Blank()

                    TextInput({ text: this.subCategory, placeholder: '例如: SVIP' })
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.End)
                      .backgroundColor(Color.Transparent)
                      .padding(0)
                      .height(40)
                      .layoutWeight(1)
                      .onChange((value: string) => {
                        this.subCategory = value;
                      })
                  }
                  .width('100%')
                  .height(56)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.page_background'))
                  .borderRadius(12)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isLevelPressed) ?
                        hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({
                    x: (this.isAnimationEnabled && this.isLevelPressed) ? 0.98 : 1,
                    y: (this.isAnimationEnabled && this.isLevelPressed) ? 0.98 : 1
                  })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.isLevelPressed = true;
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isLevelPressed = false;
                    }
                  })

                  // 快速选择标签 - 横向滚动
                  if (this.availableSubCategories.length > 0) {
                    Scroll() {
                      Row({ space: 8 }) {
                        ForEach(this.availableSubCategories, (level: string) => {
                          Text(level)
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                            .height(36)
                            .padding({ left: 12, right: 12 })
                            .backgroundColor($r('app.color.card_background'))
                            .borderRadius(18)
                            .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
                            .onClick(() => {
                              animateTo({
                                duration: this.isAnimationEnabled ? this.animationDuration : 0,
                                curve: Curve.EaseOut
                              }, () => {
                                this.subCategory = level;
                              });
                            })
                        }, (level: string) => level)
                      }
                      .padding({ top: 4, bottom: 4 })
                    }
                    .scrollable(ScrollDirection.Horizontal)
                    .scrollBar(BarState.Off)
                    .width('100%')
                    .margin({ top: 8 })
                  }
                }
                .alignItems(HorizontalAlign.Start)

                Divider().color($r('app.color.divider_color')).opacity(0.3)
                // 2. 订阅分类
                Row() {
                  Text((this.recordType as string) === 'groupBuy' ? "团购分类" : "订阅分类")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))

                  Blank()

                  TextInput({ text: this.category, placeholder: '例如: 影视会员' })
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .placeholderColor($r('app.color.text_secondary'))
                    .textAlign(TextAlign.End)
                    .backgroundColor(Color.Transparent)
                    .padding(0)
                    .height(40)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.category = value;
                    })
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isCategoryPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isCategoryPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isCategoryPressed) ? 0.98 : 1
                })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isCategoryPressed = true;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isCategoryPressed = false;
                  }
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)


                // 3. 付费周期
                Row() {
                  Text("付费周期")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))

                  Blank()

                  Row() {
                    Text(this.getBillingCycleText(this.billingCycle))
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ right: 4 })

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled &&
                      this.pressedCycleValue !== '') ? hdsEffect.PointLightSourceType.BRIGHT :
                      hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.pressedCycleValue !== '') ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.pressedCycleValue !== '') ? 0.98 : 1
                })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.pressedCycleValue = 'Active';
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.pressedCycleValue = '';
                  }
                })
                .onClick(() => {
                  TextPickerDialog.show({
                    range: ['月付', '季付', '年付', '永久', '不定'],
                    selected: ['Monthly', 'Quarterly', 'Yearly', 'Lifetime',
                      'Indefinite'].indexOf(this.billingCycle),
                    selectedTextStyle: {
                      color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    acceptButtonStyle: {
                      fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    onAccept: (result: TextPickerResult) => {
                      const cycles: ('Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite')[] =
                        ['Monthly', 'Quarterly', 'Yearly', 'Lifetime', 'Indefinite'];
                      const value = cycles[result.index as number];

                      animateTo({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0,
                        curve: Curve.Sharp
                      }, () => {
                        this.billingCycle = value;

                        // 根据选择的周期填充对应价格
                        if (value === 'Monthly' && this.ocrMonthlyPrice) {
                          this.price = this.ocrMonthlyPrice;
                        } else if (value === 'Quarterly' && this.ocrQuarterlyPrice) {
                          this.price = this.ocrQuarterlyPrice;
                        } else if (value === 'Yearly' && this.ocrYearlyPrice) {
                          this.price = this.ocrYearlyPrice;
                        } else if (value === 'Lifetime' && this.ocrLifetimePrice) {
                          this.price = this.ocrLifetimePrice;
                        } else {
                          // 没有对应价格时清空
                          this.price = '';
                        }

                        const now = new Date();
                        // 如果没有识别到日期且是新建模式，且是普通订阅，据周期设置默认日期
                        if (!this.ocrExpireDate && this.editId === -1 && this.recordType === 'subscription') {
                          const target = new Date();
                          if (value === 'Monthly') {
                            target.setMonth(target.getMonth() + 1);
                            this.nextBillingDate = target;
                          } else if (value === 'Quarterly') {
                            target.setMonth(target.getMonth() + 3);
                            this.nextBillingDate = target;
                          } else if (value === 'Yearly') {
                            target.setFullYear(target.getFullYear() + 1);
                            this.nextBillingDate = target;
                          } else if (value === 'Lifetime' || value === 'Indefinite') {
                            this.nextBillingDate = target;
                          }
                        }

                        // [Smart Update] 切换周期时，重新推算开始日期
                        if (value !== 'Lifetime' && value !== 'Indefinite') {
                          this.startDate = this.inferStartDate(this.nextBillingDate, value);
                        } else if (value === 'Lifetime') {
                          this.startDate = new Date(this.nextBillingDate);
                        }
                        // Indefinite: Keep existing startDate
                      });
                    }
                  })
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 3.2 支付方式
                Row() {
                  Text("支付方式")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))

                  Blank()

                  Row() {
                    Text(this.paymentMethod)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .margin({ right: 4 })

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(16)
                      .fontColor([$r('app.color.text_secondary')])
                  }
                }
                .width('100%')
                .height(56)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isPaymentPressed) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: (this.isAnimationEnabled && this.isPaymentPressed) ? 0.98 : 1,
                  y: (this.isAnimationEnabled && this.isPaymentPressed) ? 0.98 : 1
                })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isPaymentPressed = true;
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isPaymentPressed = false;
                  }
                })
                .onClick(() => {
                  const paymentMethods =
                    ['现金', '银行卡', '云闪付', '支付宝', '微信支付', '华为支付', '京东支付', '抖音支付',
                      '美团支付', '数字人民币', 'Apple Pay', 'PayPal', '其他支付方式'];
                  TextPickerDialog.show({
                    range: paymentMethods,
                    selected: paymentMethods.indexOf(this.paymentMethod),
                    selectedTextStyle: {
                      color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    acceptButtonStyle: {
                      fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                    },
                    onAccept: (result: TextPickerResult) => {
                      animateTo({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0,
                        curve: Curve.Sharp
                      }, () => {
                        this.paymentMethod = result.value as string;
                      });
                    }
                  })
                })

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 2. 金额输入
                Column({ space: 0 }) {
                  Text((this.recordType as string) === 'groupBuy' ? "实付金额" : "订阅金额")
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .margin({ bottom: 12 })

                  Row({ space: 4 }) {
                    Text(this.currency === 'USD' ? '$' : '¥')
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))

                    TextInput({ placeholder: '0.00', text: this.price })
                      .fontSize(36)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .placeholderFont({ size: 36, weight: FontWeight.Bold })
                      .placeholderColor($r('app.color.text_secondary'))
                      .textAlign(TextAlign.Start)
                      .backgroundColor(Color.Transparent)
                      .type(InputType.NUMBER_DECIMAL)
                      .maxLength(10)
                      .caretColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                      .padding(0)
                      .layoutWeight(1)
                      .onChange((value: string) => {
                        this.price = value;
                        if (this.billingCycle === 'Monthly') {
                          this.ocrMonthlyPrice = value;
                        } else if (this.billingCycle === 'Yearly') {
                          this.ocrYearlyPrice = value;
                        }
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Bottom)
                  .margin({ bottom: 12 })

                  Divider()
                    .color($r('app.color.divider_color'))
                    .strokeWidth(1)


                  Row() {
                    SymbolGlyph($r('sys.symbol.info_circle'))
                      .fontSize(12)
                      .fontColor([$r('app.color.text_secondary')])
                      .opacity(0.6)
                      .margin({ right: 4 })

                    Text("如果您的订阅是免费获得,请在订阅金额栏填写 0。")
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .opacity(0.6)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .margin({ top: 8 })
                }
                .width('100%')

                Divider().color($r('app.color.divider_color')).opacity(0.3)

                // 3.5 自动续费
                if (this.billingCycle !== 'Lifetime' && (this.recordType as string) !== 'groupBuy') {
                  Column({ space: 12 }) {
                    Row() {
                      Text("自动续费")
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)

                      Toggle({ type: ToggleType.Switch, isOn: this.isAutoRenewal })
                        .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                        .switchPointColor(Color.White)
                        .onChange((isOn: boolean) => {
                          if (this.isAnimationEnabled) {
                            animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                              this.isAutoRenewal = isOn;
                            })
                          } else {
                            this.isAutoRenewal = isOn;
                          }
                        })
                    }
                    .width('100%')

                    if (!this.isAutoRenewal) {
                      Row() {
                        SymbolGlyph($r('sys.symbol.info_circle'))
                          .fontSize(12)
                          .fontColor([$r('app.color.text_secondary')])
                          .margin({ right: 4 })

                        Text("关闭后，订阅到期时将不会自动续期。")
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                          .layoutWeight(1)
                      }
                      .width('100%')
                      .margin({ top: -4 })
                      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
                        .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
                    }
                  }
                }
                // 4. 日期选择
                Column({ space: 10 }) {
                  // 4.1 开始日期 (仅非永久会员显示)
                  if (this.billingCycle !== 'Lifetime') {
                    Row() {
                      Text("开通日期")
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))

                      Blank()

                      Row() {
                        Text(DateUtil.formatDate(this.startDate))
                          .fontSize(15)
                          .fontColor($r('app.color.text_primary'))
                          .fontWeight(FontWeight.Medium)
                          .margin({ right: 6 })

                        SymbolGlyph($r('sys.symbol.calendar'))
                          .fontSize(16)
                          .fontColor([this.isNewYearTheme ? '#FFD700' :
                            (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                      }
                      .backgroundColor($r('app.color.page_background'))
                      .padding({
                        left: 12,
                        right: 10,
                        top: 6,
                        bottom: 6
                      })
                      .borderRadius(8)
                      .visualEffect(new hdsEffect.HdsEffectBuilder()
                        .pointLight({
                          sourceType: this.startDateLight,
                          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                        })
                        .buildEffect())
                      .scale({ x: this.isStartDatePressed ? 0.98 : 1, y: this.isStartDatePressed ? 0.98 : 1 })
                      .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                      .onTouch((event: TouchEvent) => {
                        if (event.type === TouchType.Down) {
                          if (this.isAnimationEnabled && this.isPointLightEnabled) {
                            this.isStartDatePressed = true;
                            this.startDateLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                          this.isStartDatePressed = false;
                          this.startDateLight = hdsEffect.PointLightSourceType.NONE;
                        }
                      })
                      .onClick(() => {
                        DatePickerDialog.show({
                          selected: this.startDate,
                          selectedTextStyle: {
                            color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          acceptButtonStyle: {
                            fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                          },
                          onAccept: (value: DatePickerResult) => {
                            this.startDate.setFullYear(value.year, value.month, value.day)
                          }
                        })
                      })
                    }
                    .width('100%')
                    // Container Transition
                    .transition(TransitionEffect.OPACITY
                      .combine(TransitionEffect.translate({ y: -10 }))
                      .combine(TransitionEffect.scale({ y: 0.9 }))
                      .animation({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0,
                        curve: Curve.FastOutSlowIn
                      })
                    )

                    Divider().color($r('app.color.divider_color')).opacity(0.3)
                      .transition(TransitionEffect.OPACITY.animation({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0
                      }))
                  }

                  // 4.2 到期/购买日期
                  Row() {
                    Text(this.billingCycle === 'Lifetime' ? "购买日期" :
                      ((this.recordType as string) === 'groupBuy' ? "过期时间" : "到期日期"))
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                      .transition(TransitionEffect.OPACITY.animation({
                        duration: this.isAnimationEnabled ? this.animationDuration : 0
                      }))

                    Blank()

                    Row() {
                      Text(DateUtil.formatDate(this.nextBillingDate))
                        .fontSize(15)
                        .fontColor($r('app.color.text_primary'))
                        .fontWeight(FontWeight.Medium)
                        .margin({ right: 6 })
                        .transition(TransitionEffect.OPACITY.animation({
                          duration: this.isAnimationEnabled ? this.animationDuration : 0
                        }))

                      SymbolGlyph($r('sys.symbol.calendar'))
                        .fontSize(16)
                        .fontColor([this.isNewYearTheme ? '#FFD700' :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
                    }
                    .transition(TransitionEffect.OPACITY.animation({
                      duration: this.isAnimationEnabled ? this.animationDuration : 0
                    }))
                    .backgroundColor($r('app.color.page_background'))
                    .padding({
                      left: 12,
                      right: 10,
                      top: 6,
                      bottom: 6
                    })
                    .borderRadius(8)
                    .visualEffect(new hdsEffect.HdsEffectBuilder()
                      .pointLight({
                        sourceType: this.dateLight,
                        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                      })
                      .buildEffect())
                    .scale({ x: this.isDatePressed ? 0.98 : 1, y: this.isDatePressed ? 0.98 : 1 })
                    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        if (this.isAnimationEnabled && this.isPointLightEnabled) {
                          this.isDatePressed = true;
                          this.dateLight = hdsEffect.PointLightSourceType.BRIGHT;
                        }
                      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                        this.isDatePressed = false;
                        this.dateLight = hdsEffect.PointLightSourceType.NONE;
                      }
                    })
                    .onClick(() => {
                      DatePickerDialog.show({
                        selected: this.nextBillingDate,
                        selectedTextStyle: {
                          color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                            (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                        },
                        acceptButtonStyle: {
                          fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                            (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                        },
                        onAccept: (value: DatePickerResult) => {
                          this.nextBillingDate.setFullYear(value.year, value.month, value.day)
                          // 用户手动修改到期日期时,不自动修改开通日期
                          // 开通日期和到期日期应该是独立可编辑的字段
                        }
                      })
                    })
                  }
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .transition(TransitionEffect.OPACITY.animation({
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: Curve.EaseInOut
                })
                  .combine(TransitionEffect.translate({ y: -15 })
                    .animation({
                      duration: this.isAnimationEnabled ? this.animationDuration : 0,
                      curve: Curve.EaseInOut
                    })))

                Divider().color($r('app.color.divider_color')).opacity(0.3)
                  .transition(TransitionEffect.OPACITY.animation({
                    duration: this.isAnimationEnabled ? this.animationDuration : 0,
                    curve: Curve.EaseInOut
                  }))

                if (this.billingCycle !== 'Lifetime') {

                  // 5. 提醒设置 - 带开关和动画
                  Column({ space: 12 }) {
                    Row() {
                      Text((this.recordType as string) === 'groupBuy' ? "过期提醒" : "到期提醒")
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .layoutWeight(1)

                      Toggle({ type: ToggleType.Switch, isOn: this.isReminderEnabled })
                        .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                        .switchPointColor(Color.White)
                        .onChange((isOn: boolean) => {
                          this.isReminderEnabled = isOn;
                          if (this.isAnimationEnabled) {
                            if (isOn) {
                              animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                                this.isReminderExpanded = true;
                                this.reminderOpacity = 1;
                              })
                            } else {
                              animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                                this.reminderOpacity = 0;
                              });
                              setTimeout(() => {
                                animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                                  this.isReminderExpanded = false;
                                });
                              }, 200);
                            }
                          } else {
                            this.isReminderExpanded = isOn;
                            this.reminderOpacity = isOn ? 1 : 0;
                          }
                        })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    if (this.isReminderExpanded) {
                      Row() {
                        SymbolGlyph($r('sys.symbol.info_circle'))
                          .fontSize(12)
                          .fontColor([$r('app.color.text_secondary')])
                          .margin({ right: 4 })

                        Text("提示音为系统默认闹钟铃声，可能会出现铃声过大问题，可通过调整系统闹钟音量调整本应用提示音量。请合理设置提醒时间，避免过度滥用提醒功能。本应用不对因提醒失效导致的任何损失承担责任。")
                          .fontSize(11)
                          .fontColor($r('app.color.text_secondary'))
                          .layoutWeight(1)
                      }
                      .width('100%')
                      .margin({ top: -4, bottom: 8 })
                      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
                        .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
                      .opacity(this.reminderOpacity)
                    }

                    if (this.isReminderExpanded) {
                      Row() {
                        Blank()
                        // 提前天数
                        Row() {
                          Text(`提前 ${this.reminderDaysBefore} 天`)
                            .fontSize(14)
                            .fontColor($r('app.color.text_primary'))
                        }
                        .height(32)
                        .padding({ left: 10, right: 10 })
                        .backgroundColor($r('app.color.page_background'))
                        .borderRadius(8)
                        .visualEffect(new hdsEffect.HdsEffectBuilder()
                          .pointLight({
                            sourceType: this.reminderDaysLight,
                            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                          })
                          .buildEffect())
                        .scale({
                          x: this.isReminderDaysPressed ? 0.98 : 1,
                          y: this.isReminderDaysPressed ? 0.98 : 1
                        })
                        .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                        .onTouch((event: TouchEvent) => {
                          if (event.type === TouchType.Down) {
                            if (this.isAnimationEnabled && this.isPointLightEnabled) {
                              this.isReminderDaysPressed = true;
                              this.reminderDaysLight = hdsEffect.PointLightSourceType.BRIGHT;
                            }
                          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                            this.isReminderDaysPressed = false;
                            this.reminderDaysLight = hdsEffect.PointLightSourceType.NONE;
                          }
                        })
                        .onClick(() => {
                          TextPickerDialog.show({
                            range: this.reminderDaysOptions,
                            selected: this.reminderDaysOptions.indexOf(this.reminderDaysBefore.toString()),
                            selectedTextStyle: {
                              color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                            },
                            acceptButtonStyle: {
                              fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                            },
                            onAccept: (value: TextPickerResult) => {
                              this.reminderDaysBefore = parseInt(value.value as string);
                            }
                          })
                        })
                        .margin({ right: 12 })

                        // 提醒时间
                        Row() {
                          Text(this.reminderTime)
                            .fontSize(14)
                            .fontColor($r('app.color.text_primary'))
                        }
                        .height(32)
                        .padding({ left: 10, right: 10 })
                        .backgroundColor($r('app.color.page_background'))
                        .borderRadius(8)
                        .visualEffect(new hdsEffect.HdsEffectBuilder()
                          .pointLight({
                            sourceType: this.reminderTimeLight,
                            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                          })
                          .buildEffect())
                        .scale({
                          x: this.isReminderTimePressed ? 0.98 : 1,
                          y: this.isReminderTimePressed ? 0.98 : 1
                        })
                        .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                        .onTouch((event: TouchEvent) => {
                          if (event.type === TouchType.Down) {
                            if (this.isAnimationEnabled && this.isPointLightEnabled) {
                              this.isReminderTimePressed = true;
                              this.reminderTimeLight = hdsEffect.PointLightSourceType.BRIGHT;
                            }
                          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                            this.isReminderTimePressed = false;
                            this.reminderTimeLight = hdsEffect.PointLightSourceType.NONE;
                          }
                        })
                        .onClick(() => {
                          const timeParts = this.reminderTime.split(':');
                          const selectedHour = parseInt(timeParts[0]);
                          const selectedMinute = parseInt(timeParts[1]);
                          const selectedDate = new Date();
                          selectedDate.setHours(selectedHour, selectedMinute);

                          TimePickerDialog.show({
                            selected: selectedDate,
                            selectedTextStyle: {
                              color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                            },
                            acceptButtonStyle: {
                              fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                            },
                            onAccept: (value: TimePickerResult) => {
                              const h = value.hour.toString().padStart(2, '0');
                              const m = value.minute.toString().padStart(2, '0');
                              this.reminderTime = `${h}:${m}`;
                            }
                          })
                        })
                      }
                      .width('100%')
                      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
                      .opacity(this.reminderOpacity)
                    }
                  }
                  .width('100%')
                }
              }
              .padding(20)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(24)
              .width('90%')
              .shadow({ radius: 20, color: '#08000000', offsetY: 4 })
            }
            .width('100%')
            .margin({ bottom: 16 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })).animation({
              duration: this.isAnimationEnabled ? undefined : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            }))
          } // === 结束订阅表单 else 分支 ===

          // 免责声明勾选区
          Row() {
            Checkbox({ name: 'disclaimer', group: 'disclaimerGroup' })
              .select(this.isDisclaimerAgreed)
              .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .width(18)
              .height(18)
              .onChange((value: boolean) => {
                this.isDisclaimerAgreed = value;
              })

            Text() {
              Span("我已阅读并同意")
                .fontColor($r('app.color.text_secondary'))
              Span("《用户协议》")
                .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .decoration({
                  type: TextDecorationType.Underline,
                  color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                    (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                })
                .onClick(() => {
                  // 跳转或显示用户协议逻辑
                  this.pageStack.pushPathByName('WebView',
                    new WebViewParam($rawfile('user_agreement.html'), '用户协议'));
                })
              Span("及其免责声明，知晓本应用为本地记录工具，数据可能因不可控因素丢失；因我个人保管不当或操作失误导致的财产损失，开发者不承担责任，相关风险由本人自行承担。")
                .fontColor($r('app.color.text_secondary'))
            }
            .fontSize(12)
            .margin({ left: 8 })
            .layoutWeight(1)
          }
          .width('90%')
          .margin({ bottom: 16 })
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
          .opacity(this.animStep2 ? 1 : 0)
          .translate({ y: this.animStep2 ? 0 : 20 })

          // 4. 底部操作栏
          Row({ space: 16 }) {
            if (this.editId !== -1) {
              Button("删除")
                .layoutWeight(1)
                .height(50)
                .backgroundColor('#10FF3B30')
                .fontColor(Color.Red)
                .borderRadius(16)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.deleteLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isDeletePressed ? 0.98 : 1, y: this.isDeletePressed ? 0.98 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isDeletePressed = true;
                      this.deleteLight = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isDeletePressed = false;
                    this.deleteLight = hdsEffect.PointLightSourceType.NONE;
                  }
                })
                .onClick(() => {
                  this.promptAction.showDialog({
                    title: '确认删除',
                    message: '确定要删除这个订阅吗？',
                    buttons: [
                      { text: '取消', color: '#000000' },
                      { text: '删除', color: '#FF0000' }
                    ]
                  }).then(async (resp) => {
                    if (resp.index === 1) {
                      await SubscriptionRepository.getInstance().delete(this.editId);
                      SubscriptionRepository.getInstance().updateWidgetSnapshotSync('delete');
                      this.pageStack.pop();
                    }
                  });
                })
            } else {
              Button("取消")
                .layoutWeight(1)
                .height(50)
                .backgroundColor($r('app.color.page_background'))
                .fontColor($r('app.color.text_secondary'))
                .borderRadius(16)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.cancelLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isCancelPressed ? 0.98 : 1, y: this.isCancelPressed ? 0.98 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isCancelPressed = true;
                      this.cancelLight = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isCancelPressed = false;
                    this.cancelLight = hdsEffect.PointLightSourceType.NONE;
                  }
                })
                .onClick(() => {
                  this.pageStack.pop();
                })
            }

            Button("保存")
              .layoutWeight(1)
              .height(50)
              .linearGradient(this.isNewYearTheme ? {
                angle: 135,
                colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
              } : (this.showVipTheme ? {
                angle: 135,
                colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
              } : {
                angle: 0,
                colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]]
              }))
              .backgroundColor(Color.Transparent)
              .fontColor(this.isNewYearTheme ? '#FFD700' :
                (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
              .borderRadius(16)
              .shadow({
                radius: 10,
                color: this.isNewYearTheme ? '#40FF2400' : (this.showVipTheme ? '#40E6C07B' : '#20007AFF'),
                offsetY: 5
              })
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.saveLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .scale({ x: this.isSavePressed ? 0.98 : 1, y: this.isSavePressed ? 0.98 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isSavePressed = true;
                    this.saveLight = hdsEffect.PointLightSourceType.BRIGHT;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isSavePressed = false;
                  this.saveLight = hdsEffect.PointLightSourceType.NONE;
                }
              })
              .onClick(async () => {
                if (!this.isDisclaimerAgreed) {
                  this.promptAction.showToast({ message: '请先阅读并勾选用户协议' });
                  return;
                }

                if (this.name === '' || this.price === '') {
                  this.promptAction.showToast({ message: '请填写名称和金额' });
                  return;
                }

                if (this.billingCycle !== 'Lifetime' && this.billingCycle !== 'Indefinite') {
                  const s = new Date(this.startDate);
                  s.setHours(0, 0, 0, 0);
                  const e = new Date(this.nextBillingDate);
                  e.setHours(0, 0, 0, 0);
                  if (s.getTime() > e.getTime()) {
                    this.promptAction.showToast({ message: '开通日期不能晚于到期日期' });
                    return;
                  }
                }
                const newSub: SubscriptionModel = {
                  uuid: this.uuid || util.generateRandomUUID(),
                  name: this.name,
                  price: parseFloat(this.price),
                  currency: this.currency,
                  // warranty 类型固定使用 Lifetime 周期（一次性购买，到期日即保修到期日）
                  // 注意：显示逻辑需要根据 recordType 为 warranty 来区分显示“保修”还是“永久”
                  billingCycle: this.recordType === 'warranty' ? 'Lifetime' :
                    (this.billingCycle as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite'),
                  nextBillingDate: this.nextBillingDate.getTime(),
                  startDate: this.recordType === 'warranty' ? (this.startDate ? this.startDate.getTime() : new Date().getTime()) :
                    (this.billingCycle === 'Lifetime' ? this.nextBillingDate.getTime() : this.startDate.getTime()),
                  icon: this.icon,
                  lastModified: new Date().getTime(),
                  isDeleted: false,
                  // warranty 类型支持到期提醒
                  reminderDaysBefore: (!this.isReminderEnabled) ? undefined : this.reminderDaysBefore,
                  reminderTime: (!this.isReminderEnabled) ? undefined : this.reminderTime,
                  category: this.category,
                  subCategory: this.subCategory,
                  isAutoRenewal: this.isAutoRenewal,
                  paymentMethod: this.paymentMethod,
                  // 团购券字段
                  recordType: this.recordType,
                  platform: this.recordType === 'groupBuy' ? this.platform : undefined,
                  couponCode: this.recordType === 'groupBuy' ? this.couponCode : undefined,
                  usageStatus: this.recordType === 'groupBuy' ? this.usageStatus : undefined,
                  merchantName: this.recordType === 'groupBuy' ? this.merchantName : undefined,
                  quantity: this.recordType === 'groupBuy' ? this.quantity : undefined,
                  couponImage: this.recordType === 'groupBuy' ? this.couponImage : undefined,
                  usageTime: this.recordType === 'groupBuy' ? this.usageTime : undefined,
                  realUsageTime: this.recordType === 'groupBuy' ? this.realUsageTime : undefined,
                  // 保修/保质期字段
                  brand: this.recordType === 'warranty' ? this.brand : undefined,
                  purchaseChannel: this.recordType === 'warranty' ? this.purchaseChannel : undefined,
                  extendedWarranties: this.recordType === 'warranty' && this.extendedWarranties.length > 0 ? JSON.stringify(this.extendedWarranties) : undefined
                };

                if (this.editId !== -1) {
                  newSub.id = this.editId;
                  await SubscriptionRepository.getInstance().update(newSub);
                } else {
                  await SubscriptionRepository.getInstance().insert(newSub);
                }
                SubscriptionRepository.getInstance().updateWidgetSnapshotSync('save');
                GlobalBus.publish(EVENT_DATA_CHANGED);
                this.pageStack.clear();
              })
          }
          .width('90%')
          .margin({ bottom: 40 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .opacity(this.animStep2 ? 1 : 0)
        .translate({ y: this.animStep2 ? 0 : 20 })

      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      Column()
        .bindSheet($$this.showCropSheet, this.CropSheetBuilder(), {
          height: '80%',
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,
          backgroundColor: $r('app.color.page_background')

        })
      Column()
        .bindSheet($$this.showExampleSheet, this.ExampleImagesDialog(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          dragBar: true,
          preferType: SheetType.CENTER,
          title: { title: '识别示例', subtitle: '参考以下截图格式' }
        })
      Column()
        .bindSheet($$this.showWarrantyCategorySheet, this.WarrantyCategorySheetBuilder(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          dragBar: true,
          preferType: SheetType.BOTTOM,

        })

    }
  }
  build() {


      HdsNavDestination() {
          this.addBuilder()
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: this.editId !== -1 ? (this.recordType === 'groupBuy' ? "编辑团购" : (this.recordType === 'warranty' ? "编辑保修" : "编辑服务")) :
              (this.recordType === 'groupBuy' ? "添加团购" : (this.recordType === 'warranty' ? "添加保修" : "添加服务"))
          },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.questionmark_circle'),
                  isEnabled: true,
                  action: () => {
                    this.showExampleSheet = true;
                  }
                }
              }
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
        } : undefined
      })
      .backgroundColor($r('app.color.page_background'))
      .onReady((context: NavDestinationContext) => {
        const rawParams = context.pathInfo.param as Record<string, Object>;
        if (rawParams && rawParams['initialType']) {
          this.recordType = rawParams['initialType'] as 'subscription' | 'groupBuy' | 'warranty';

          // 来自市场的预填充数据
          if (rawParams['marketplaceName']) {
            this.name = rawParams['marketplaceName'] as string;
            this.skipNextSearch = true; // 防止触发搜索覆盖
          }
          if (rawParams['marketplaceIcon']) {
            this.icon = rawParams['marketplaceIcon'] as string;
          }
          if (rawParams['marketplaceCategory']) {
            this.category = rawParams['marketplaceCategory'] as string;
          }
          if (rawParams['marketplaceSubCategory']) {
            this.subCategory = rawParams['marketplaceSubCategory'] as string;
          }
          if (rawParams['marketplaceCycle']) {
            this.billingCycle =
              rawParams['marketplaceCycle'] as 'Monthly' | 'Quarterly' | 'Yearly' | 'Lifetime' | 'Indefinite';
          }
          // 显示预览卡片（与 OCR 识别共用同一标志位）
          if (rawParams['marketplaceName']) {
            this.showOCRResult = true;
          }
          return;
        }

        const params = context.pathInfo.param as SubscriptionModel;
        if (params && (params.id || params.uuid)) {
          // 防止初始化时的名称设置触发 onChange 导致图标被重置
          this.skipNextSearch = true;
          this.editId = params.id || -1;
          this.uuid = params.uuid;
          this.name = params.name;
          this.price = params.price.toString();
          this.currency = params.currency;
          this.billingCycle = params.billingCycle;
          this.nextBillingDate = new Date(params.nextBillingDate);
          if (params.startDate) {
            this.startDate = new Date(params.startDate);
          }
          this.isAutoRenewal = params.isAutoRenewal !== undefined ? params.isAutoRenewal : true;
          this.icon = params.icon || '';

          // 加载提醒设置
          if (params.reminderDaysBefore !== undefined) {
            this.isReminderEnabled = true;
            this.isReminderExpanded = true;
            this.reminderOpacity = 1;
            this.reminderDaysBefore = params.reminderDaysBefore;
            this.reminderTime = params.reminderTime || '09:00';
          }

          this.category = params.category || '其他';
          this.subCategory = params.subCategory || '';
          this.paymentMethod = params.paymentMethod || '其他支付方式';

          // 加载团购券特有字段
          this.recordType = params.recordType || 'subscription';
          if (this.recordType === 'groupBuy') {
            this.platform = params.platform || 'meituan';
            this.couponCode = params.couponCode || '';
            this.usageStatus = params.usageStatus || 'unused';
            this.merchantName = params.merchantName || '';
            this.quantity = params.quantity || 1;
            this.couponImage = params.couponImage || '';
            this.usageTime = params.usageTime || '';
            this.realUsageTime = params.realUsageTime;
          } else if (this.recordType === 'warranty') {
            // 加载保修/保质期专属字段
            this.brand = params.brand || '';
            this.purchaseChannel = params.purchaseChannel || '';
            if (params.extendedWarranties) {
               try {
                 const rawList = JSON.parse(params.extendedWarranties) as ExtendedWarrantyItem[];
                 this.extendedWarranties = rawList.map(item => new ExtendedWarrantyItem(
                   item.id,
                   item.name,
                   item.price,
                   item.date,
                   item.isReminderEnabled
                 ));
               } catch (e) {
                 hilog.error(0x0000, 'AddSubscription', `Failed to parse extendedWarranties: ${e.message}`);
                 this.extendedWarranties = [];
               }
            }
          }

          if (this.recordType === 'subscription') {
            // 自动修正旧数据的分类 (订阅)
            if (this.category === '其他' && this.name) {
              const matched = matchMemberService(this.name);
              if (matched?.category) {
                this.category = matched.category;
              }
            }
            // 加载可用的会员等级选项
            const service = matchMemberService(this.name);
            if (service && service.validSubCategories) {
              this.availableSubCategories = service.validSubCategories;
            }
          } else if (this.recordType === 'warranty') {
            // 自动修正旧数据的分类 (保修)
            if (this.category === '其他' && this.name) {
              this.category = matchWarrantyCategory(this.name);
              if (this.category !== '其他物品') {
                this.icon = 'warranty_icon:' + this.category;
              }
            }
          }

          // 显示信息卡片
          this.showOCRResult = true;
          this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
          // 注意：编辑模式下我们没有 ocrMonthlyPrice/ocrYearlyPrice 的原始数据，
          // 如果需要显示价格，可以用 params.price 填充其中一个，或者留空只显示名称和日期
          if (this.recordType === 'subscription') {
            if (this.billingCycle === 'Monthly') {
              this.ocrMonthlyPrice = this.price;
            } else if (this.billingCycle === 'Quarterly') {
              this.ocrQuarterlyPrice = this.price;
            } else if (this.billingCycle === 'Yearly') {
              this.ocrYearlyPrice = this.price;
            } else if (this.billingCycle === 'Lifetime') {
              this.ocrLifetimePrice = this.price;
            }
          }
        }
      })
      .onBackPressed(() => {
        this.pageStack.pop();
        return true;
      })
      .onShown(async () => {
        // 页面显示时（包括从配置页返回），重新检查 API Key 状态，确保及时隐藏提示文字
        this.hasApiKey = !!(await PreferenceUtil.getInstance().getAIKey());

        // 页面显示时，如果处于截图模式，说明用户手动切换回应用了
        // 只有在检测到截图并正在处理时才自动关闭，如果只是切换回来什么都没做，保留闪控球
      })




  }

  @Builder
  WarrantyCategorySheetBuilder() {
    WarrantyCategorySheet({
      selectedCategory: this.category,
      onSelect: (category: WarrantyCategory) => {
        animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: curves.springMotion() }, () => {
          this.category = category.name;
          this.icon = 'warranty_icon:' + category.name;
        })
        this.showWarrantyCategorySheet = false;
        this.promptAction.showToast({ message: `已选择: ${category.name}` });
      },
      onClose: () => {
        this.showWarrantyCategorySheet = false;
      }
    })
  }

  @Builder
  RecentPhotoSheetBuilder() {
    Column() {
      Text('点击下方的截图进行识别')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 16 })

      RecentPhotoComponent({
        recentPhotoOptions: this.recentPhotoOptions,
        onRecentPhotoClick: (info: BaseItemInfo): boolean => this.onRecentPhotoClick(info),
        onRecentPhotoCheckResult: (exists: boolean) => this.onRecentPhotoCheckResult(exists)
      })
        .width('100%')
        .layoutWeight(1) // 让其充满剩余空间
    }
    .width('100%')
    .height('100%') // 确保 Column 撑满 Sheet
    .padding(16)
  }


  // CycleButton has been replaced by TextPickerDialog selector logic

  // 缓存的应用图标 PixelMap
  private iconPixelMap: image.PixelMap | undefined = undefined;

  getTotalPrice(): string {
    let total = parseFloat(this.price) || 0;
    if (this.recordType === 'warranty' && this.extendedWarranties.length > 0) {
      this.extendedWarranties.forEach(item => {
        total += parseFloat(item.price) || 0;
      });
    }
    return total.toFixed(2);
  }

  /**
   * 启动截图识别模式
   * 1. 创建闪控球并显示"请截图"
   * 2. 注册截屏状态监听
   * 3. 最小化应用到桌面
   * 4. 检测到截屏后更新闪控球为"已捕获"
   * 5. 用户点击闪控球返回并选择截图
   */
  /**
   * 启动截图识别模式
   * 1. Check permission
   * 2. 创建闪控球
   * 3. 最小化应用
   * 4. 点击闪控球 -> 截屏 -> 恢复 -> 识别
   */
  async startScreenshotCapture(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const manager = FloatingBallManager.getInstance();

    // 检查设备是否支持闪控球
    if (!manager.isSupported()) {
      this.promptAction.showToast({ message: '当前设备不支持闪控球功能' });
      return;
    }

    // 1. 检查权限
    const atManager = abilityAccessCtrl.createAtManager();
    const permission: Permissions = 'ohos.permission.CUSTOM_SCREEN_CAPTURE' as Permissions;

    try {
      const grantStatus = await atManager.checkAccessToken(context.applicationInfo.accessTokenId, permission);

      if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        // 申请权限
        const result = await atManager.requestPermissionsFromUser(context, [permission]);
        if (result.authResults[0] !== 0) {
          // 权限被拒绝，引导用户去设置开启
          this.promptAction.showDialog({
            title: '需要截屏权限',
            message: '闪控球功能需要“截屏录屏”权限才能工作。请在设置中手动开启该权限。',
            buttons: [
              { text: '取消', color: $r('app.color.text_secondary') },
              { text: '去设置', color: $r('app.color.brand_color') }
            ]
          }).then((dialogResult) => {
            if (dialogResult.index === 1) {
              // 跳转到应用设置详情页
              const want: Want = {
                bundleName: 'com.huawei.hmos.settings',
                abilityName: 'com.huawei.hmos.settings.MainAbility',
                uri: 'application_info_entry',
                parameters: {
                  pushParams: 'com.xxtstudio.accountDL' // 你的包名
                }
              };
              context.startAbility(want);
            }
          });
          return;
        }
      }
    } catch (err) {
      console.error('[Screenshot] Permission check failed:', err);
      this.promptAction.showToast({ message: '权限校验失败' });
      return;
    }

    // 创建闪控球控制器
    const created = await manager.create(context);
    if (!created) {
      this.promptAction.showToast({ message: '闪控球创建失败' });
      return;
    }

    // 加载应用图标
    if (!this.iconPixelMap) {
      try {
        const resourceMgr = context.resourceManager;
        const arrayBuffer = await resourceMgr.getMediaContent($r('app.media.foreground'));
        const imageSource = image.createImageSource(arrayBuffer.buffer as ArrayBuffer);
        // 缩放图标以避免超过闪控球大小限制 (1MB)
        const decodingOptions: image.DecodingOptions = {
          desiredSize: { width: 100, height: 100 }
        };
        this.iconPixelMap = await imageSource.createPixelMap(decodingOptions);
      } catch (e) {
        console.error('[Screenshot] Failed to load app icon:', e);
      }
    }

    // 重置状态
    this.isScreenshotMode = true;
    this.hasDetectedScreenshot = false;
    this.showRecentPhotoSheet = false;

    // 启动闪控球
    // 左侧文本: 点击截取 | 右侧文本: 屏幕识别
    const started = await manager.start(
      '点我',
      '截屏识别',
      this.iconPixelMap,
      async () => {
        // --- 闪控球点击回调 (此时应用在后台) ---
        // 标记是从球返回的，防止 EntryAbility 触发自动清理
        manager.setReturningFromBall(true);
        try {
          // 1. 尝试截取当前屏幕
          // 注意: 需要 ohos.permission.CAPTURE_SCREEN 权限
          console.info('[Screenshot] Capturing screen...');

          // 获取默认屏幕截图
          // API 21+ 支持 Phone/Tablet, 需 CAPTURE_SCREEN 权限
          const pixelMap = await screenshot.capture({ displayId: 0 });

          // 2. 恢复应用窗口
          await manager.restoreMainWindow('com.xxtstudio.accountDL', 'EntryAbility');

          // 3. 停止闪控球
          await manager.stop();

          // 4. 处理截屏结果
          if (pixelMap) {
            this.recognizePixelMap(pixelMap);
          } else {
             throw new Error('PixelMap is empty');
          }

        } catch (err) {
          console.error('[Screenshot] Capture failed:', err);

          // 失败处理: 恢复窗口并提示
          await manager.restoreMainWindow('com.xxtstudio.accountDL', 'EntryAbility');
          await manager.stop();

          let msg = '自动截屏失败';
          if (err.code === 201) {
             msg = '请授予截屏权限';
          } else if (err.code === 801) {
             msg = '当前设备不支持截屏';
          }
          this.promptAction.showToast({ message: msg });
        }
      },
      () => {
        // 闪控球被关闭/取消
        this.isScreenshotMode = false;
        this.hasDetectedScreenshot = false;
      }
    );

    if (!started) {
      this.promptAction.showToast({ message: '闪控球启动失败' });
      this.isScreenshotMode = false;
      return;
    }

    // 最小化应用到桌面
    try {
      const windowStage = await window.getLastWindow(context);
      await windowStage.minimize();
    } catch (e) {
      console.error('Minimize window failed:', e);
    }
  }

  /**
   * 启动二维码专项识别模式
   * 独立的闪控球实例，仅用于识别二维码
   */
  async startQRCodeCapture(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const manager = FloatingBallManager.getInstance();

    // 检查设备是否支持闪控球
    if (!manager.isSupported()) {
      this.promptAction.showToast({ message: '当前设备不支持闪控球功能' });
      return;
    }

    // 1. 检查权限
    const atManager = abilityAccessCtrl.createAtManager();
    const permission: Permissions = 'ohos.permission.CUSTOM_SCREEN_CAPTURE' as Permissions;

    try {
      const grantStatus = await atManager.checkAccessToken(context.applicationInfo.accessTokenId, permission);

      if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        // 申请权限
        const result = await atManager.requestPermissionsFromUser(context, [permission]);
        if (result.authResults[0] !== 0) {
          // 权限被拒绝，引导用户去设置开启
          this.promptAction.showDialog({
            title: '需要截屏权限',
            message: '闪控球功能需要“截屏录屏”权限才能工作。请在设置中手动开启该权限。',
            buttons: [
              { text: '取消', color: $r('app.color.text_secondary') },
              { text: '去设置', color: $r('app.color.brand_color') }
            ]
          }).then((dialogResult) => {
            if (dialogResult.index === 1) {
              // 跳转到应用设置详情页
              const want: Want = {
                bundleName: 'com.huawei.hmos.settings',
                abilityName: 'com.huawei.hmos.settings.MainAbility',
                uri: 'application_info_entry',
                parameters: {
                  pushParams: 'com.xxtstudio.accountDL' // 你的包名
                }
              };
              context.startAbility(want);
            }
          });
          return;
        }
      }
    } catch (err) {
      console.error('[QR Capture] Permission check failed:', err);
      this.promptAction.showToast({ message: '权限检查失败' });
      return;
    }

    // 加载应用图标（如果尚未加载）
    if (!this.iconPixelMap) {
      try {
        const resourceMgr = context.resourceManager;
        const arrayBuffer = await resourceMgr.getMediaContent($r('app.media.foreground'));
        const imageSource = image.createImageSource(arrayBuffer.buffer as ArrayBuffer);
        // 缩放图标以避免超过闪控球大小限制 (1MB)
        const decodingOptions: image.DecodingOptions = {
          desiredSize: { width: 100, height: 100 }
        };
        this.iconPixelMap = await imageSource.createPixelMap(decodingOptions);
      } catch (e) {
        console.error('[QR Capture] Failed to load app icon:', e);
      }
    }

    // 2. 创建闪控球控制器
    const qrCreated = await manager.create(context);
    if (!qrCreated) {
      this.promptAction.showToast({ message: '闪控球控制器创建失败' });
      return;
    }

    // 3. 启动闪控球（二维码专用）
    const started = await manager.start(
      '点我',
      '识别二维码',
      this.iconPixelMap,
      async () => {
        // --- 闪控球点击回调 ---
        // 标记是从球返回的，防止 EntryAbility 触发自动清理
        manager.setReturningFromBall(true);
        try {
          console.info('[QR Capture] Capturing screen for QR code...');

          // 1. 截取屏幕
          const pixelMap = await screenshot.capture({ displayId: 0 });

          // 2. 恢复应用窗口
          await manager.restoreMainWindow('com.xxtstudio.accountDL', 'EntryAbility');

          // 3. 停止闪控球
          await manager.stop();

          // 4. 专项处理：仅识别二维码
          if (pixelMap) {
            this.isQROnly = true;
            await this.processPixelMap(pixelMap);
            this.isQROnly = false;
          } else {
            throw new Error('PixelMap is empty');
          }

        } catch (err) {
          console.error('[QR Capture] Failed:', err);

          // 失败处理
          await manager.restoreMainWindow('com.xxtstudio.accountDL', 'EntryAbility');
          await manager.stop();

          let msg = '二维码识别失败';
          if (err.code === 201) {
            msg = '请授予截屏权限';
          } else if (err.code === 801) {
            msg = '当前设备不支持截屏';
          }
          this.promptAction.showToast({ message: msg });
        }
      },
      () => {
        // 闪控球被关闭/取消
        console.info('[QR Capture] Floating ball cancelled');
      }
    );

    if (!started) {
      this.promptAction.showToast({ message: '闪控球启动失败' });
      return;
    }

    // 最小化应用到桌面
    try {
      const windowStage = await window.getLastWindow(context);
      await windowStage.minimize();
    } catch (e) {
      console.error('Minimize window failed:', e);
    }
  }

  /**
   * 识别 PixelMap (复用识别逻辑)
   */
  async recognizePixelMap(pixelMap: image.PixelMap): Promise<void> {
      // 1. 清空旧数据
      animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: Curve.EaseInOut }, () => {
        this.ocrMonthlyPrice = '';
        this.ocrQuarterlyPrice = '';
        this.ocrYearlyPrice = '';
        this.ocrLifetimePrice = '';
        this.showOCRResult = false;
        this.ocrExpireDate = '';
        this.icon = '';
        this.price = '';
        this.name = '';
        this.category = '其他';
        this.subCategory = '';
        this.couponImage = ''; // Clear image
        this.usageTime = ''; // Clear usage time
      });

      this.isOCRLoading = true;

      try {
          // 2. 获取文字
          const rawText = await OCRManager.getInstance().recognizeText(pixelMap);
          if (!rawText) throw new Error('本地OCR未识别到文字');

          // 3. 自动匹配模式
          // const couponKeywords = ['券码', '券号', '验证码', '待到店使用', '核销', '有效期为', '实付¥', '任选', '套餐'];
          // const isCoupon = couponKeywords.some(kw => rawText.includes(kw));

          let result: OCRResult;
          let qrCodePromise: Promise<QRCodeResult | undefined> | undefined = undefined;

          if (this.recordType === 'groupBuy') {
             const context = getContext(this) as common.UIAbilityContext;
             qrCodePromise = GroupBuyOCRManager.getInstance().extractQRCode(context, pixelMap);
             result = GroupBuyOCRManager.getInstance().parseText(rawText);
          } else {
             // 订阅模式优先使用 AI
             try {
                result = await AIVisionManager.getInstance().recognizeSubscription(pixelMap);
             } catch (e) {
                console.error('AI Vision failed, fallback to local:', e);
                result = OCRManager.getInstance().parseText(rawText);
             }
          }

          // 3. 更新 UI
          // 等待 QR 码结果 (如果是团购模式)
          // 等待 QR 码结果 (如果是团购模式)
          let qrCodeResult: QRCodeResult | undefined = undefined;
          if (qrCodePromise) {
             try {
                qrCodeResult = await qrCodePromise;
             } catch (e) {
                console.error('QR Scan failed:', e);
             }
          }

          animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: Curve.FastOutSlowIn }, () => {
            if (this.recordType === 'groupBuy') {
               if (result.merchantName) this.merchantName = result.merchantName;
               if (result.appName) this.name = result.appName;

               // 优先使用二维码提取的券码
               if (qrCodeResult && qrCodeResult.code) {
                   this.couponCode = qrCodeResult.code;

                   // 如果有裁剪的二维码图片，可以考虑显示 specific handling (Future TODO)
                   if (qrCodeResult.codeImageUri) {
                       this.couponImage = qrCodeResult.codeImageUri;
                       hilog.info(0x0000, 'AddSubscription', `Coupon Image Saved: ${qrCodeResult.codeImageUri}`);
                   }
               } else if (result.couponCode) {
                   this.couponCode = result.couponCode;
               }

               if (result.platform) this.platform = result.platform;
               if (result.price) this.price = result.price.toString();

               hilog.info(0x0000, 'AddSubscription', `OCR Result usageTime (PixelMap): ${result.usageTime}`);
               this.usageTime = result.usageTime || '';

               if (result.date) {
                  this.nextBillingDate = new Date(result.date);
                  this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
                  this.startDate = new Date();
               }
               return;
            }

            // Subscription Logic
            if (result.monthlyPrice) this.ocrMonthlyPrice = result.monthlyPrice.toString();
            if (result.yearlyPrice) this.ocrYearlyPrice = result.yearlyPrice.toString();

            if (result.billingCycle) {
              this.billingCycle = result.billingCycle;
            } else if (result.yearlyPrice && !result.monthlyPrice) {
               this.billingCycle = 'Yearly';
            } else if (result.monthlyPrice && !result.yearlyPrice) {
               this.billingCycle = 'Monthly';
            }

            // 当前价格
            if (this.billingCycle === 'Monthly' && this.ocrMonthlyPrice) {
              this.price = this.ocrMonthlyPrice;
            } else if (this.billingCycle === 'Quarterly' && this.ocrQuarterlyPrice) {
               this.price = this.ocrQuarterlyPrice;
            } else if (this.billingCycle === 'Yearly' && this.ocrYearlyPrice) {
              this.price = this.ocrYearlyPrice;
            } else if (this.billingCycle === 'Lifetime' && this.ocrLifetimePrice) {
               this.price = this.ocrLifetimePrice;
            } else if (result.price) {
              this.price = result.price.toString();
            }

            // 名称与分类
            if (result.appName) {
              this.name = result.appName;
              this.icon = result.serviceIcon || '';
              this.showOCRResult = true;

              const service = matchMemberService(this.name);
              if (service && service.validSubCategories) {
                this.availableSubCategories = service.validSubCategories;
              } else {
                this.availableSubCategories = [];
              }
            } else {
               this.showOCRResult = false;
               this.availableSubCategories = [];
            }

            if (result.category) {
              this.category = result.category;
            }
            if (result.subCategory) {
               this.subCategory = result.subCategory;
            } else {
               this.subCategory = '';
            }

            // 日期
            if (result.date) {
               this.nextBillingDate = new Date(result.date);
               this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);

               // [Smart Inference] 根据到期日反推开始日期
               this.startDate = this.inferStartDate(this.nextBillingDate, this.billingCycle);

            } else {
               const target = new Date();
               this.startDate = new Date(); // Default today if no date found
               target.setDate(target.getDate() + 31);
               this.nextBillingDate = target;
               this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
            }
          });

          this.promptAction.showToast({ message: '识别完成' });

      } catch (e) {
          console.error('识别失败:', e);
          this.promptAction.showToast({ message: '识别失败，请重试' });
      } finally {
          this.isOCRLoading = false;
          // 记得释放 pixelMap
          pixelMap.release();
      }
  }

  /**
   * 处理最近截图
   * 显示 RecentPhotoComponent 让用户选择最新的截图
   */
  async processRecentScreenshot(): Promise<void> {
    // 只有在检测到截图操作后才自动弹出
    if (this.hasDetectedScreenshot) {
      // 配置 RecentPhotoOptions 只显示截图
      this.recentPhotoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      this.recentPhotoOptions.photoSource = PhotoSource.SCREENSHOT;  // 只显示截图
      this.recentPhotoOptions.isAutoRefreshSupported = true;  // 自动刷新显示最新截图

      // 显示最近截图选择面板
      this.showRecentPhotoSheet = true;
    } else {
      this.promptAction.showToast({ message: '未检测到新截图' });
    }

    // 重置模式状态 (showRecentPhotoSheet 需要保持 true 直到 Sheet 关闭)
    this.isScreenshotMode = false;
    this.hasDetectedScreenshot = false;
  }

  /**
   * 处理用户点击最近截图的回调
   */
  private onRecentPhotoClick(recentPhotoInfo: BaseItemInfo): boolean {
    if (!recentPhotoInfo || !recentPhotoInfo.uri) {
      return false;
    }

    // 关闭面板并开始 OCR 识别
    this.showRecentPhotoSheet = false;
    this.recognizeScreenshot(recentPhotoInfo.uri);

    return true;  // 返回 true 表示授权读取
  }

  /**
   * 检查是否存在截图的回调
   */
  private onRecentPhotoCheckResult(recentPhotoExists: boolean): void {
    if (!recentPhotoExists) {
      this.promptAction.showToast({ message: '未找到最近的截图' });
    }
  }

  /**
   * 识别截图
   * @param uri file://media/... 格式的 URI
   */
  async recognizeScreenshot(uri: string): Promise<void> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      console.info(`[Screenshot] Recognizing screenshot from URI: ${uri}`);

      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const fileSource = image.createImageSource(file.fd);
      pixelMap = await fileSource.createPixelMap();
      fileIo.closeSync(file);
    } catch (e) {
      console.error('Screenshot capture failed:', e);
      return;
    }

    if (!pixelMap) return;

    await this.processPixelMap(pixelMap);
  }

  /**
   * 仅识别二维码
   */
  async recognizeQRCodeOnly() {
    await this.startQRCodeCapture();
  }

  /**
   * 统一处理 PixelMap
   */
  private async processPixelMap(pixelMap: image.PixelMap) {
    try {
      if (!this.isQROnly) {
        // 1. 清空数据 (仅在非专项模式下)
        animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: Curve.EaseInOut }, () => {
          this.ocrMonthlyPrice = '';
          this.ocrQuarterlyPrice = '';
          this.ocrYearlyPrice = '';
          this.ocrLifetimePrice = '';
          this.showOCRResult = false;
          this.ocrExpireDate = '';
          this.icon = '';
          this.price = '';
          this.name = '';

          this.category = '其他';
          this.subCategory = '';
          this.couponImage = '';
          this.usageTime = '';
        });
      }

       this.isOCRLoading = true;

      // 1. 获取原始 OCR 文本 (仅执行一次)
      const rawText = await OCRManager.getInstance().recognizeText(pixelMap);
      if (!rawText) throw new Error('本地OCR未识别到文字');

      // 2. 自动识别类型：如果包含券相关关键词，或者用户已经手动切换到团购模式
      // const couponKeywords = ['券码', '券号', '验证码', '待到店使用', '核销', '有效期为', '实付¥', '任选', '套餐'];
      // const isCoupon = couponKeywords.some(kw => rawText.includes(kw));

      let result: OCRResult = { fullText: '' };
      let qrCodePromise: Promise<QRCodeResult | undefined> | undefined = undefined;

      if (this.isQROnly) {
         // 专项模式：仅执行二维码识别
         const context = getContext(this) as common.UIAbilityContext;
         qrCodePromise = GroupBuyOCRManager.getInstance().extractQRCode(context, pixelMap);
      } else {
         // 正常模式：全量识别
         if (this.recordType === 'groupBuy') {
            const context = getContext(this) as common.UIAbilityContext;
            qrCodePromise = GroupBuyOCRManager.getInstance().extractQRCode(context, pixelMap);
            result = GroupBuyOCRManager.getInstance().parseText(rawText);
         } else {
            result = OCRManager.getInstance().parseText(rawText);
         }
      }

      // 3. 等待 QR 结果
      let qrCodeResult: QRCodeResult | undefined = undefined;
      if (qrCodePromise) {
         try { qrCodeResult = await qrCodePromise; } catch (e) {}
      }

      animateTo({ duration: this.isAnimationEnabled ? this.animationDuration : 0, curve: Curve.FastOutSlowIn }, () => {
         // Update UI
         if (this.isQROnly) {
            // === 专项模式：仅更新券码和券码图片 ===
            if (qrCodeResult && qrCodeResult.code) {
               this.couponCode = qrCodeResult.code;
               if (qrCodeResult.codeImageUri) {
                  this.couponImage = qrCodeResult.codeImageUri;
               }
               hilog.info(0x0000, 'AddSubscription', `QR-Only: Updated coupon code: ${qrCodeResult.code}`);
            }
            // 不修改其他任何字段
            return;
         }

         // === 正常模式：完整更新 ===
         if (this.recordType === 'groupBuy') {
            if (result.merchantName) this.merchantName = result.merchantName;
            if (result.appName) this.name = result.appName;

            if (qrCodeResult && qrCodeResult.code) {
                this.couponCode = qrCodeResult.code;
                if (qrCodeResult.codeImageUri) {
                   this.couponImage = qrCodeResult.codeImageUri;
                }
            } else if (result.couponCode) {
                this.couponCode = result.couponCode;
            }

            if (result.platform) this.platform = result.platform;
            if (result.price) this.price = result.price.toString();

            hilog.info(0x0000, "AddSubscription", `OCR Result usageTime: ${result.usageTime}`);
            this.usageTime = result.usageTime || '';

            if (result.date) {
               this.nextBillingDate = new Date(result.date);
               this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
               this.startDate = new Date();
            } else {
               // 团购券未识别到日期时，保持今日，不自动加一个月
               this.nextBillingDate = new Date();
               this.startDate = new Date();
               this.ocrExpireDate = '';
            }
            return; // Skip subscription logic
         }

            // Subscription Logic
            if (result.monthlyPrice) this.ocrMonthlyPrice = result.monthlyPrice.toString();
            if (result.yearlyPrice) this.ocrYearlyPrice = result.yearlyPrice.toString();

            if (result.billingCycle) {
              this.billingCycle = result.billingCycle;
            } else if (result.yearlyPrice && !result.monthlyPrice) {
               this.billingCycle = 'Yearly';
            } else if (result.monthlyPrice && !result.yearlyPrice) {
               this.billingCycle = 'Monthly';
            }

            if (this.billingCycle === 'Monthly' && result.monthlyPrice) {
              this.price = result.monthlyPrice.toString();
            } else if (this.billingCycle === 'Quarterly' && result.quarterlyPrice) {
               this.price = result.quarterlyPrice.toString();
            } else if (this.billingCycle === 'Yearly' && result.yearlyPrice) {
              this.price = result.yearlyPrice.toString();
            } else if (this.billingCycle === 'Lifetime' && result.lifetimePrice) {
               this.price = result.lifetimePrice.toString();
            } else if (result.price) {
              this.price = result.price.toString();
            }

            if (result.appName) {
              this.name = result.appName;
              this.icon = result.serviceIcon || '';
              this.showOCRResult = true;

              const service = matchMemberService(this.name);
              if (service && service.validSubCategories) {
                this.availableSubCategories = service.validSubCategories;
              } else {
                this.availableSubCategories = [];
              }
            } else {
                this.showOCRResult = false;
                this.availableSubCategories = [];
            }

            if (result.category) {
              this.category = result.category;
            }
            if (result.subCategory) {
               this.subCategory = result.subCategory;
            } else {
               this.subCategory = '';
            }

            if (result.date) {
              this.nextBillingDate = new Date(result.date);
              this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);

              // [Smart Inference] 根据到期日反推开始日期
              this.startDate = this.inferStartDate(this.nextBillingDate, this.billingCycle);

            } else {
              const target = new Date();
              this.startDate = new Date(); // Default today if no date found
              target.setDate(target.getDate() + 31);
              this.nextBillingDate = target;
              this.ocrExpireDate = DateUtil.formatDate(this.nextBillingDate);
            }
      });

      this.isOCRLoading = false;
      this.promptAction.showToast({ message: '扫描完成' });

    } catch (e) {
      this.isOCRLoading = false;
      console.error('[Screenshot] Recognition failed:', JSON.stringify(e));
      this.promptAction.showToast({ message: '识别失败，请手动输入' });
    } finally {
       if (pixelMap) {
          pixelMap.release();
       }
    }
  }

  /**
   * 显示图标选择菜单
   */
  private showIconPickerSheet(): void {
    promptAction.showActionMenu({
      title: '选择图标',
      buttons: [
        { text: '使用默认图标', color: $r('app.color.text_primary') },
        { text: '从相册选择', color: $r('app.color.brand_color') }
      ]
    }).then((result) => {
      if (result.index === 0) {
        this.resetToDefaultIcon();
      } else if (result.index === 1) {
        this.pickCustomIcon();
      }
    }).catch(() => {
      // 用户取消
    });
  }

  /**
   * 重置为默认图标
   */
  private resetToDefaultIcon(): void {
    const matched = matchMemberService(this.name);
    this.icon = matched?.icon || '';
    this.promptAction.showToast({ message: '已重置为默认图标' });
  }

  /**
   * 输入 Emoji 图标
   */
  private showEmojiInput(): void {
    this.promptAction.showDialog({
      title: '输入 Emoji',
      message: '请输入一个 Emoji 作为图标（如 🎬、🎵、📦）',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '确定', color: $r('app.color.brand_color') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        // HarmonyOS 暂不支持在 Dialog 中输入文本，这里用 Toast 提示
        this.promptAction.showToast({ message: 'Emoji 输入功能开发中' });
      }
    });
  }

  /**
   * 从相册选择自定义图标
   */
  private async pickCustomIcon(): Promise<void> {
    try {
      // 使用 PhotoViewPicker 选择图片
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });

      if (result.photoUris && result.photoUris.length > 0) {
        // 打开裁剪 Sheet
        this.cropSourceUri = result.photoUris[0];
        this.showCropSheet = true;
      }
    } catch (e) {
      console.error('[CustomIcon] Pick failed:', e);
      this.promptAction.showToast({ message: '选择图片失败' });
    }
  }

  /**
   * 智能推算开始日期
   * 规则：
   * 1. 自动回溯：如果根据周期推算的日期在未来(相对于今天)，则继续向前回溯，直到找到一个 <= 今天的起始日。
   *    这解决了"一次性预付多年"或"识别到远期订阅"时，开始日期被错误推算为未来的问题。
   *    例如：到期 2029-10-15, 今天 2026-01-29, 周期月付。
   *    逻辑：2029-09-15 (未来) -> ... -> 2026-02-15 (未来) -> 2026-01-15 (过去, 选中)
   */
  private inferStartDate(endDate: Date, cycle: string): Date {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    let current = new Date(endDate);

    // Safety break to prevent infinite loops (e.g. invalid cycle or massive date difference)
    const maxIterations = 1200; // 100 years of months
    let iteration = 0;

    // 首次回溯：至少往前推一个周期
    if (cycle === 'Monthly') current = DateUtil.safeSubtractMonth(current, 1);
    else if (cycle === 'Quarterly') current = DateUtil.safeSubtractMonth(current, 3);
    else if (cycle === 'Yearly') current = DateUtil.safeSubtractYear(current, 1);
    else {
      // Lifetime/Warranty/GroupBuy：如果没有计费周期，默认开始日期为今天
      // 除非到期日已经在过去，则设为到期日
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const end = new Date(endDate);
      end.setHours(0, 0, 0, 0);
      
      return end < today ? new Date(end) : new Date(today);
    }

    // 持续回溯：只要当前计算出的开始日期还在未来，就继续往前推
    // 我们比较的是 00:00:00 时间戳
    while (current.getTime() > today.getTime() && iteration < maxIterations) {
       if (cycle === 'Monthly') current = DateUtil.safeSubtractMonth(current, 1);
       else if (cycle === 'Quarterly') current = DateUtil.safeSubtractMonth(current, 3);
       else if (cycle === 'Yearly') current = DateUtil.safeSubtractYear(current, 1);
       else break;

       iteration++;
    }

    // 如果回溯了1200次还没找到（极地异常），或者出错，就返回今天
    if (iteration >= maxIterations) {
       return new Date();
    }

    return current;
  }

  @Builder
  CropSheetBuilder() {
    ImageCropSheet({
      sourceUri: this.cropSourceUri,
      onComplete: (croppedUri: string) => {
        this.icon = croppedUri;
        this.showCropSheet = false;
        this.promptAction.showToast({ message: '图标已更新' });
      },
      onCancel: () => {
        this.showCropSheet = false;
      }
    })
  }

  private getBillingCycleText(cycle: string): string {
    switch (cycle) {
      case 'Monthly': return '月付';
      case 'Quarterly': return '季付';
      case 'Yearly': return '年付';
      case 'Lifetime': return '永久';
      case 'Indefinite': return '不定';
      default: return '月付';
    }
  }

  /**
   * 裁剪图片为1:1并保存到沙箱
   */
  private async cropAndSaveIcon(sourceUri: string, context: common.UIAbilityContext): Promise<string> {
    try {
      // 读取源图片
      const sourceFile = await fileIo.open(sourceUri, fileIo.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(sourceFile.fd);
      const imageInfo = await imageSource.getImageInfo();

      // 计算 1:1 裁剪区域 (居中)
      const size = Math.min(imageInfo.size.width, imageInfo.size.height);
      const x = Math.floor((imageInfo.size.width - size) / 2);
      const y = Math.floor((imageInfo.size.height - size) / 2);

      // 创建裁剪后的 PixelMap
      const pixelMap = await imageSource.createPixelMap({
        desiredRegion: { x, y, size: { width: size, height: size } },
        desiredSize: { width: 128, height: 128 }  // 缩放到 128x128
      });

      await fileIo.close(sourceFile);

      // 保存到沙箱
      const iconDir = `${context.filesDir}/icons`;
      try {
        await fileIo.mkdir(iconDir);
      } catch (e) {
        // 目录可能已存在
      }

      const fileName = `icon_${Date.now()}.png`;
      const targetPath = `${iconDir}/${fileName}`;
      const targetFile = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

      // 编码为 PNG 并写入
      const imagePacker = image.createImagePacker();
      const packData = await imagePacker.packing(pixelMap, { format: 'image/png', quality: 90 });
      await fileIo.write(targetFile.fd, packData);
      await fileIo.close(targetFile);

      return `file://${targetPath}`;
    } catch (e) {
      console.error('[CustomIcon] Crop failed:', e);
      return '';
    }
  }

}

