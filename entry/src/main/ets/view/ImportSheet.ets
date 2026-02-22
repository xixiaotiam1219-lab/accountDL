import { SubscriptionModel } from '../model/SubscriptionModel';
import { CustomIconItem } from '../utils/HarmonyShareManager';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hdsEffect,   HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { curves, LengthMetrics } from '@kit.ArkUI';
import { LocalIconManager } from '../utils/LocalIconManager';
import { util, buffer } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';

const TITLE_BAR_HEIGHT_MINI: number = 76;

@Observed
export class ImportItem {
  data: SubscriptionModel;
  localData: SubscriptionModel | null; // For comparison
  isSelected: boolean;
  status: 'new' | 'update' | 'duplicate' | 'restore'; // Analysis result

  constructor(data: SubscriptionModel, localData: SubscriptionModel | null, isSelected: boolean, status: 'new' | 'update' | 'duplicate' | 'restore') {
    this.data = data;
    this.localData = localData;
    this.isSelected = isSelected;
    this.status = status;
  }
}

@Component
struct ImportSheetItem {
  @ObjectLink item: ImportItem;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  index: number = 0;
  @Prop pressedIndex: number = -1;
  onSelectChange: (value: boolean) => void = () => {};

  build() {
    Row() {
      // Checkbox
      Checkbox({ name: `item_${this.index}` })
        .select(this.item.isSelected)
        .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_color')))
        .width(20)
        .height(20)
        .margin({ right: 12 })
        .enabled(this.item.status !== 'duplicate')
        .opacity(this.item.status === 'duplicate' ? 0.3 : 1)
        .onChange((value: boolean) => {
          if (this.item.status !== 'duplicate') {
            this.item.isSelected = value;
            this.onSelectChange(value);
          }
        })

      // Icon with Badge
      SubscriptionIcon({
        name: this.item.data.name,
        icon: this.item.data.icon,
        iconSize: 40,
        iconRadius: 8,
        showGroupBadge: this.item.data.recordType === 'groupBuy',
        showWarrantyBadge: this.item.data.recordType === 'warranty'
      })
      .margin({ right: 12 })
      .opacity(this.item.status === 'duplicate' ? 0.6 : 1)

      // Name & Info
      Column() {
        Row() {
          Text(this.item.data.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.item.status === 'duplicate' ? $r('app.color.text_secondary') : $r('app.color.text_primary'))

          // Status Badge
          this.BuildBadge()
        }

        // 信息展示区 (两行布局)
        Column({ space: 4 }) {
          // 第一行：周期标签 + 会员等级标签
          Row({ space: 4 }) {
            Text(this.getCycleText(this.item.data))
              .fontSize(10)
              .fontColor($r('app.color.brand_color'))
              .backgroundColor('#1A0A59F7')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(4)
            
            if (this.item.data.subCategory) {
              Text(this.item.data.subCategory)
                .fontSize(10)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor('#1A000000')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
            }
          }

          // 第二行：续费状态 · 分类
          Row({ space: 4 }) {
            if (this.item.data.recordType === 'warranty') {
              Text(this.item.data.brand || '保修')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            } else if (this.item.data.recordType === 'groupBuy') {
              Text(this.item.data.merchantName || '团购')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            } else {
              Text(this.item.data.isAutoRenewal !== false ? '自动续费' : '到期停止')
                .fontSize(11)
                .fontColor(this.item.data.isAutoRenewal !== false ? $r('app.color.success_color') : $r('app.color.text_secondary'))
            }

            Text('·')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))

            Text(this.item.data.category || '未分类')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Price & Date
      Column() {
        Text(`${this.item.data.currency === 'USD' ? '$' : (this.item.data.currency === 'CNY' || this.item.data.currency === 'RMB' ? '¥' : (this.item.data.currency === 'EUR' ? '€' : (this.item.data.currency === 'GBP' ? '£' : '¥')))}${this.item.data.price}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.item.status === 'duplicate' ? $r('app.color.text_secondary') : $r('app.color.text_primary'))

        Text(DateUtil.formatDate(this.item.data.nextBillingDate))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.End)
      .opacity(this.item.status === 'duplicate' ? 0.6 : 1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(12)
    .margin({ bottom: 8 })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressedIndex === this.index ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.pressedIndex === this.index ? 0.98 : 1, y: this.pressedIndex === this.index ? 0.98 : 1 })
    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
  }

  private getCycleText(item: SubscriptionModel): string {
    if (item.recordType === 'groupBuy') {
       return '团购券';
    }
    if (item.recordType === 'warranty') {
       return '保修';
    }
    const cycle = item.billingCycle;
    switch (cycle) {
      case 'Monthly': return '月付';
      case 'Quarterly': return '季付';
      case 'Yearly': return '年付';
      case 'Lifetime': return '永久';
      case 'Indefinite': return '不定';
      default: return '月付';
    }
  }

  @Builder BuildBadge(): void {
    if (this.item.status === 'new') {
      Text("NEW")
        .fontSize(10)
        .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
        .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_color')))
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .margin({ left: 8 })
    } else if (this.item.status === 'restore') {
      Text("恢复")
        .fontSize(10)
        .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
        .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_color')))
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .margin({ left: 8 })
    } else if (this.item.status === 'update') {
      Text("变更")
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.warning_color'))
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .margin({ left: 8 })
    } else if (this.item.status === 'duplicate') {
      Text("已存在")
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor('#1A000000')
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .margin({ left: 8 })
    }
  }
}

@Component
export struct ImportSheet {
  @Link isShow: boolean;
  @Link @Watch('onDataChange') importData: SubscriptionModel[];
  private navStack: NavPathStack = new NavPathStack();
  onImport: () => void = (): void => {};
  onCancel: () => void = (): void => {};
  @State items: ImportItem[] = [];
  @State isAllSelected: boolean = true;
  @State isLoading: boolean = true;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @State pressedIndex: number = -1;
  @StorageLink('importFileContent') importFileContent: string = ''; // 确保注入此属性以便恢复图标库
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;

  async onDataChange(): Promise<void> {
    // 只有在数据真正为空或第一次加载时才显示全屏Loading，减少切换闪烁
    if (this.items.length === 0) {
      this.isLoading = true;
    }
    
    // --- 关键增强：在显示面板时立即尝试恢复图标库本身的数据 ---
    if (this.importFileContent) {
      try {
        const fullData = JSON.parse(this.importFileContent) as Record<string, Object>;
        const customIcons = fullData['customIcons'] as CustomIconItem[];
        if (customIcons && customIcons.length > 0) {
          hilog.info(0x0000, 'ImportSheet', `预览阶段：预恢复库图标: ${customIcons.length}个`);
          for (const icon of customIcons) {
             // 静默恢复图标库索引，不覆盖已有的
             await LocalIconManager.getInstance().registerBase64Icon(icon.base64, icon.name, icon.category, false);
          }
        }
      } catch (e) {
        hilog.error(0x0000, 'ImportSheet', `预恢复异常: ${JSON.stringify(e)}`);
      }
    }

    const repo = SubscriptionRepository.getInstance();
    const iconManager = LocalIconManager.getInstance();

    // 并行分析所有项，显著提升速度
    const promises = this.importData.map(async (item: SubscriptionModel): Promise<ImportItem> => {
      // 0. Auto-Calibration: Ensure start date is valid
      if (!item.recordType) {
        if (item.brand) {
          item.recordType = 'warranty';
        } else if (item.merchantName || item.couponCode) {
          item.recordType = 'groupBuy';
        }
      }
      this.calibrateStartDate(item);

      // --- 核心改进：在预览阶段就执行图标修复 ---
      if (item.name) {
        // 对于 builtin://、旧路径或失效链接，直接尝试通过库找回
        const info = await iconManager.getAppInfo(item.name);
        if (info && info.icon) {
          // 策略调整：如果是精确匹配，直接使用；如果是模糊匹配，仅在原图标无效或为空时使用
          if (info.name === item.name) {
            item.icon = info.icon;
          } else if (!item.icon || item.icon.startsWith('builtin://') || item.icon.startsWith('app.media.')) {
            // 模糊匹配结果仅作为兜底
            item.icon = info.icon;
          }
        } else if (item.icon && item.icon.startsWith('app.media.')) {
          if (item.icon.includes('meituan')) item.icon = 'resource:meituan_logo';
          else if (item.icon.includes('douyin')) item.icon = 'resource:douyin_logo';
          else if (item.icon.includes('dianping')) item.icon = 'resource:dianping_logo';
        }
      }

      if (!item.uuid) {
        return new ImportItem(item, null, true, 'new');
      }

      try {
        const local = await repo.findByUuid(item.uuid);
        if (!local) {
          return new ImportItem(item, null, true, 'new');
        } else if (local.isDeleted) {
          return new ImportItem(item, local, true, 'restore');
        } else {
          if (this.isIdentical(item, local)) {
            return new ImportItem(item, local, false, 'duplicate');
          } else {
            return new ImportItem(item, local, true, 'update');
          }
        }
      } catch (e) {
        return new ImportItem(item, null, true, 'update');
      }
    });

    this.items = await Promise.all(promises);
    this.checkSelectAll();
    this.isLoading = false;
  }

  isIdentical(a: SubscriptionModel, b: SubscriptionModel): boolean {
    return a.name === b.name &&
      Math.abs((a.price || 0) - (b.price || 0)) < 0.0001 &&
      a.currency === b.currency &&
      a.billingCycle === b.billingCycle &&
      a.nextBillingDate === b.nextBillingDate &&
      (a.recordType || 'subscription') === (b.recordType || 'subscription') &&
      (a.startDate || 0) === (b.startDate || 0) &&
      (a.category || '') === (b.category || '') &&
      (a.subCategory || '') === (b.subCategory || '') &&
      this.isIconIdentical(a.icon, b.icon) &&
      a.reminderDaysBefore === b.reminderDaysBefore &&
      (a.reminderTime || '') === (b.reminderTime || '');
  }

  isIconIdentical(a: string | undefined, b: string | undefined): boolean {
    const iconA = a || '';
    const iconB = b || '';
    if (iconA === iconB) return true;

    // Normalize builtin icons
    const getIdentity = (uri: string): string => {
      if (uri.startsWith('builtin://')) return uri.substring(10);
      if (uri.includes('/local_icons/')) {
        const parts = uri.split('/');
        return parts[parts.length - 1];
      }
      return uri;
    };

    return getIdentity(iconA) === getIdentity(iconB);
  }

  // 自动校对开通日期
  // 如果导入数据缺失开通日期，则基于下个扣款日反推
  calibrateStartDate(item: SubscriptionModel) {
    if (item.startDate && item.startDate > 0) return;
    if (!item.nextBillingDate) return;

    const nextBilling = new Date(item.nextBillingDate);
    const billingCycle = item.billingCycle;

    // 反推逻辑：StartDate = NextBilling - CycleDuration
    // 简单处理：月付-1月，年付-1年
    const startDate = new Date(nextBilling);

    if (item.recordType === 'warranty') {
      // 保修记录缺失开始时间，默认为当前时间 (避免被误设为过期时间)
      item.startDate = new Date().getTime();
      return;
    }

    switch (billingCycle) {
      case 'Monthly':
        startDate.setMonth(startDate.getMonth() - 1);
        break;
      case 'Quarterly':
        startDate.setMonth(startDate.getMonth() - 3);
        break;
      case 'Yearly':
        startDate.setFullYear(startDate.getFullYear() - 1);
        break;
      case 'Indefinite':
      case 'Lifetime':
        // 永久/不定会员默认当天购买
        // 也可以不处理，因为永久会员的时间轴是从 purchaseDate (nextBillingDate) 开始的
        startDate.setTime(nextBilling.getTime());
        break;
      default:
        // 默认为月付
        startDate.setMonth(startDate.getMonth() - 1);
        break;
    }

    item.startDate = startDate.getTime();
  }

  aboutToAppear(): void {
    LocalIconManager.getInstance().init(getContext(this));
    this.onDataChange();
  }

  toggleAll(value: boolean): void {
    this.isAllSelected = value;
    this.items.forEach((item: ImportItem) => {
      if (item.status !== 'duplicate') {
        item.isSelected = value;
      }
    });
  }

  checkSelectAll(): void {
    const electable = this.items.filter((i: ImportItem) => i.status !== 'duplicate');
    if (electable.length === 0) {
      this.isAllSelected = false;
      return;
    }
    this.isAllSelected = electable.every((item: ImportItem) => item.isSelected);
  }

  build() {
    HdsNavigation(this.navStack) {
      if (this.isLoading) {
        Column() {
          Stack() {
            Column().width(80).height(80).borderRadius(40)
              .backgroundColor(this.isNewYearTheme ? '#40FF2400' : (this.showVipTheme ? '#40302008' : '#1A0A59F7'))
            LoadingProgress().width(36).height(36)
              .color(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_color')))
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItem() {
            Column() {
              Blank()
                .height(TITLE_BAR_HEIGHT_MINI)
            }
          }

          // Select All Header
          ListItem() {
            Row() {
              Checkbox({ name: 'selectAll' })
                .select(this.isAllSelected)
                .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_color')))
                .width(20)
                .height(20)
                .margin({ right: 12 })
                .onChange((value: boolean) => {
                  this.toggleAll(value);
                })

              Text('全选 (仅新数据/更新)')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding({ bottom: 16, left: 4 })
          }

          // Import Items Container
          if (this.items.length > 0) {
            ListItem() {
              Column() {
                ForEach(this.items, (item: ImportItem, index: number) => {
                  ImportSheetItem({
                    item: item,
                    index: index,
                    pressedIndex: this.pressedIndex,
                    onSelectChange: (val: boolean): void => {
                      this.checkSelectAll();
                    }
                  })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      if (this.isAnimationEnabled && this.isPointLightEnabled) {
                        this.pressedIndex = index;
                      }
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedIndex = -1;
                    }
                  })
                }, (item: ImportItem) => JSON.stringify((item.data.uuid || '') + item.status + item.isSelected))
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(20)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 0, bottom: 80 }) 
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)

        // Footer Actions
        Column() {
          Button(`导入 (${this.items.filter((i: ImportItem) => i.isSelected).length})`)
            .width('100%')
            .height(48)
            .linearGradient({
              angle: 135,
              colors: [
                [this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold_start') : $r('app.color.brand_gradient_start')), 0.0],
                [this.isNewYearTheme ? $r('app.color.new_year_red_end') : (this.showVipTheme ? $r('app.color.vip_gold_end') : $r('app.color.brand_gradient_end')), 1.0]
              ]
            })
            .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .borderRadius(24)
            .shadow({
              radius: 20,
              color: this.isNewYearTheme ? '#40FF2400' : (this.showVipTheme ? '#40E6C07B' : '#40007AFF'),
              offsetY: 8
            })
            .enabled(this.items.some((i: ImportItem) => i.isSelected))
            .opacity(this.items.some((i: ImportItem) => i.isSelected) ? 1 : 0.5)
            .onClick(() => {
              this.handleImport();
            })
        }
        .padding(16)
        .width('100%')
        .backgroundColor(Color.Transparent)
        .position({ x: 0, y: '100%' })
        .translate({ y: -80 }) // Floating footer to allow content scroll behind
      }
    }
    .backgroundColor($r('app.color.page_background'))
    .titleBar({
      content: {
        title: { 
          mainTitle: '导入订阅数据',
          subTitle: this.isLoading ? '正在分析数据...' : `共检测到 ${this.items.length} 条数据`
        },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.xmark'),
                action: () => {
                  this.isShow = false;
                  this.onCancel();
                }
              }
            }
          ]
        }
      },
      // style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
      //   systemMaterialEffect: {
      //     materialType: hdsMaterial.MaterialType.IMMERSIVE,
      //     materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      //   },
      //   scrollEffectOpts: {
      //     enableScrollEffect: true,
      //     scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      //     blurEffectiveStartOffset: LengthMetrics.vp(0),
      //     blurEffectiveEndOffset: LengthMetrics.vp(20)
      //   }
      // } : undefined
    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
  }

  async handleImport(): Promise<void> {
    const selected = this.items.filter((i: ImportItem) => i.isSelected).map((i: ImportItem) => i.data);

    // Process icons: 如果是特定 Base64 图标则保存
    for (const item of selected) {
      if (item.icon && item.icon.startsWith('data:')) {
        try {
          const savedUri = await this.saveBase64Image(item.icon, 'imported', 'icons');
          if (savedUri) {
            item.icon = savedUri;
            hilog.info(0x0000, 'ImportSheet', `Saved imported icon for ${item.name} to ${savedUri}`);
          }
        } catch (e) {
          hilog.error(0x0000, 'ImportSheet', `Failed to save imported icon for ${item.name}: ${e}`);
        }
      }
      
      // 注意：builtin:// 或其他库图标已经在 onDataChange 预览阶段通过 getAppInfo 修复过了
      // 此处 handleImport 主要负责最终的 Subscription 持久化存储准备

      // Save couponImage from base64 (团购券截图恢复)
      if (item.couponImage && item.couponImage.startsWith('data:')) {
         try {
           const savedUri = await this.saveBase64Image(item.couponImage, 'coupon_code');
           if (savedUri) {
             item.couponImage = savedUri;
             hilog.info(0x0000, 'ImportSheet', `Saved imported coupon image for ${item.name} to ${savedUri}`);
           }
         } catch (e) {
           hilog.error(0x0000, 'ImportSheet', `Failed to save imported coupon image for ${item.name}: ${e}`);
         }
      }
    }

    this.importData.length = 0;
    for (let i = 0; i < selected.length; i++) {
      this.importData.push(selected[i]);
    }
    this.onImport();
  }

  private async saveBase64Image(base64Data: string, prefix: string = 'imported', subDir: string = ''): Promise<string> {
    try {
      const parts = base64Data.split(',');
      if (parts.length !== 2) return '';
      
      const base64Str = parts[1];
      const mimeMatch = parts[0].match(/data:(image\/[a-zA-Z+]+);base64/);
      let ext = 'png';
      if (mimeMatch && mimeMatch[1]) {
        const mime = mimeMatch[1];
        if (mime === 'image/jpeg') ext = 'jpg';
        else if (mime === 'image/webp') ext = 'webp';
      }

      const uint8Array = new util.Base64Helper().decodeSync(base64Str);
      const arrayBuffer = buffer.from(uint8Array).buffer;

      const context = getContext(this) as common.UIAbilityContext;
      let targetDir = context.filesDir;
      if (subDir) {
          targetDir = `${targetDir}/${subDir}`;
      }
      
      if (!fs.accessSync(targetDir)) {
        fs.mkdirSync(targetDir);
      }

      const fileName = `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1000)}.${ext}`;
      const filePath = `${targetDir}/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, arrayBuffer);
      fs.closeSync(file);

      return `file://${filePath}`;
    } catch (e) {
      hilog.error(0x0000, 'ImportSheet', `saveBase64Image error: ${e}`);
      return '';
    }
  }
}
