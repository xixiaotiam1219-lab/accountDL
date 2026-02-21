import { SubscriptionModel } from '../model/SubscriptionModel';
import { resolveIcon } from '../utils/MemberServiceConfig';
import { SubscriptionIcon } from './SubscriptionIcon';
import { componentSnapshot, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { ImageUtils } from '../utils/ImageUtils';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { hdsEffect, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { curves, LengthMetrics } from '@kit.ArkUI';
import { BackgroundWatermark } from './BackgroundWatermark';

interface ReportItem {
  sub: SubscriptionModel;
  monthlyCost: number; // Amortized cost
}

interface CategoryInfo {
  name: string;
  amount: number;
  percent: number;
}

interface ReportSummary {
  totalForecast: number;
  totalMonthlyItems: number; // Sum of Monthly cycle items
  totalYearlyAmortized: number; // Sum of Yearly items / 12
  items: ReportItem[];
  categoryList: CategoryInfo[];
  maxSpender: ReportItem | null;
}

const REPORT_List_ID = 'REPORT_SCROLL_ID';

@Component
export struct MonthlyReportSheet {
  @Prop subscriptions: SubscriptionModel[] = [];
  @State reportData: ReportSummary | null = null;
  private navStack: NavPathStack = new NavPathStack();
  @Prop showCloseButton: boolean = false;
  onClose: () => void = () => {};

  // Snapshot related state
  private scroller: Scroller = new Scroller();
  @State isSnapshotting: boolean = false; // To hide UI elements during snapshot
  @State componentMaskImage: PixelMap | undefined = undefined; // Overlay image during scrolling
  private listComponentWidth: number = 0;
  private listComponentHeight: number = 0;
  private curYOffset: number = 0;
  @Builder SnapshotOverlay() {
    if (this.componentMaskImage) {
      Image(this.componentMaskImage)
        .width('100%')
        .height('100%')
        .syncLoad(true)
        .backgroundColor($r('app.color.page_background'))
    }
  }

  getGroupBuyIcon(sub: SubscriptionModel): string {
    if (sub.platform === 'meituan') return 'resource:meituan_logo';
    if (sub.platform === 'douyin') return 'resource:douyin_logo';
    if (sub.platform === 'dianping') return 'resource:dianping_logo';
    return sub.icon ?? '';
  }
  private scrollYOffsets: number[] = [];
  private areaArray: image.PositionArea[] = [];
  
  // Animation States
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  @State animStep1: boolean = false; // Overview
  @State animStep2: boolean = false; // Distribution
  @State animStep3: boolean = false; // Detail List

  // Interaction State
  @State isOverviewPressed: boolean = false;
  @State overviewLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isCategoryPressed: boolean = false;
  @State categoryLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isMaxSpenderPressed: boolean = false;
  @State maxSpenderLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State pressedItemIndex: number = -1; // For list items

  @State isSharePressed: boolean = false;
  @State shareLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isClosePressed: boolean = false;
  @State closeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  // Theme States
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('vipTheme') vipTheme: string = 'default';
  @StorageLink('showVipTheme') showVipTheme: boolean = false;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageProp('currentColorMode') currentColorMode: number = 0; // 0: Auto, 1: Light, 2: Dark

  // Helper for graphical assets (Icons, Progress Bars) to match theme
  // Text should ALWAYS use system resources (text_primary/secondary) for readability
  private getThemeAccent(): ResourceColor {
    if (this.isNewYearTheme) return $r('app.color.new_year_red_start');
    if (this.showVipTheme) return $r('app.color.vip_gold');
    return $r('app.color.brand_color');
  }

  triggerAnimations() {
       if (this.isAnimationEnabled) {
          const duration = this.animationDuration;
          const interval = duration * 0.15;
          const springCurve = curves.springMotion(this.animationResponse, this.animationDamping);
          
          setTimeout(() => { animateTo({ duration: duration, curve: springCurve }, () => { this.animStep1 = true }) }, 0);
          setTimeout(() => { animateTo({ duration: duration, curve: springCurve }, () => { this.animStep2 = true }) }, interval);
          setTimeout(() => { animateTo({ duration: duration, curve: springCurve }, () => { this.animStep3 = true }) }, interval * 2);
      } else {
          this.animStep1 = true;
          this.animStep2 = true;
          this.animStep3 = true;
      }
  }
  
  aboutToAppear() {
    this.reportData = this.getReportData();
    // Delay slightly to ensure layout is ready
    setTimeout(() => {
      this.triggerAnimations();
    }, 50);
  }

  private getReportData(): ReportSummary {
    let totalForecast = 0;
    let totalMonthlyItems = 0;
    let totalYearlyAmortized = 0;
    let items: ReportItem[] = [];
    let categories: Map<string, number> = new Map();

    this.subscriptions.forEach(sub => {
      let monthlyCost = Number(sub.price);
      
      // Group Buy: checking usage time first
      if (sub.recordType === 'groupBuy') {
        if (sub.usageStatus === 'used' && sub.realUsageTime) {
          const uDate = new Date(sub.realUsageTime);
          // Only count if used in current month
          if (uDate.getFullYear() !== new Date().getFullYear() || uDate.getMonth() !== new Date().getMonth()) {
            return;
          }
        } else {
          // Unused or expired coupons in current month view
          const billingDate = new Date(sub.nextBillingDate);
          if (billingDate.getFullYear() !== new Date().getFullYear() || billingDate.getMonth() !== new Date().getMonth()) {
             return;
          }
        }
        totalMonthlyItems += monthlyCost;
      } else if (sub.recordType === 'warranty') {
          // 保修记录：通常是一次性支出，按购买日期 (startDate) 判断是否计入本月
          const startDate = new Date(sub.startDate || 0);
          const isCurrentMonth = startDate.getFullYear() === new Date().getFullYear() && 
                                 startDate.getMonth() === new Date().getMonth();
          if (isCurrentMonth) {
            monthlyCost = Number(sub.price);
            totalMonthlyItems += monthlyCost;
          } else {
            // 非本月购买的保修，不计入月度支出
            return;
          }
      } else if (sub.billingCycle === 'Lifetime' || sub.billingCycle === 'Indefinite') {
        const billingDate = new Date(sub.nextBillingDate);
        const isCurrentMonth = billingDate.getFullYear() === new Date().getFullYear() && 
                               billingDate.getMonth() === new Date().getMonth();
        if (isCurrentMonth) {
          monthlyCost = Number(sub.price);
          totalMonthlyItems += monthlyCost; // 作为本月一次性大额支出计入
        } else {
          monthlyCost = 0; // 非本月购买的永久项目不计入当月预估
        }
      } else if (sub.billingCycle === 'Yearly') {
        monthlyCost = monthlyCost / 12;
        totalYearlyAmortized += monthlyCost;
      } else if (sub.billingCycle === 'Quarterly') {
        monthlyCost = monthlyCost / 3;
        totalMonthlyItems += monthlyCost;
      } else {
        totalMonthlyItems += monthlyCost;
      }

      totalForecast += monthlyCost;
      
      items.push({ sub: sub, monthlyCost: monthlyCost } as ReportItem);
      
      const cat = sub.recordType === 'groupBuy' ? (sub.category || '券类') : (sub.category || '其他');
      categories.set(cat, (categories.get(cat) || 0) + monthlyCost);
    });

    items.sort((a, b) => b.monthlyCost - a.monthlyCost);

    let categoryList: CategoryInfo[] = [];
    if (totalForecast > 0) {
      categories.forEach((val, key) => {
        categoryList.push({ 
          name: key, 
          amount: val, 
          percent: (val / totalForecast) * 100 
        } as CategoryInfo);
      });
      categoryList.sort((a, b) => b.amount - a.amount);
    }

    return {
      totalForecast,
      totalMonthlyItems,
      totalYearlyAmortized,
      items,
      categoryList,
      maxSpender: items.length > 0 ? items[0] : null
    } as ReportSummary;
  }

  getItemInfo(sub: SubscriptionModel): string {
    if (sub.recordType === 'groupBuy') {
      return (sub.subCategory ? `团购券 · ${sub.subCategory}` : '团购券');
    }

    if (sub.recordType === 'warranty') {
      return (sub.brand ? `保修 · ${sub.brand}` : '保修');
    }

    let cycleText = '';
    switch (sub.billingCycle) {
      case 'Monthly':
        cycleText = '月付';
        break;
      case 'Quarterly':
        cycleText = '季付';
        break;
      case 'Yearly':
        cycleText = '年付';
        break;
      case 'Lifetime':
        cycleText = '永久';
        break;
      case 'Indefinite':
        cycleText = '不定';
        break;
    }
    
    if (sub.subCategory) {
      return `${cycleText} · ${sub.subCategory}`;
    }
    return cycleText;
  }

  //--- Snapshot Logic Start ---

  async startSnapshot() {
    if (this.isSnapshotting) return;
    promptAction.showToast({ message: '正在生成月报长截图...', duration: 2000 });
    try {
      // 1. Capture current screen as mask FIRST (before modifying UI state)
      // This prevents the "flash" because the mask will look exactly like the current screen
      const snapshot = await this.getUIContext().getComponentSnapshot().get(REPORT_List_ID);
      this.componentMaskImage = snapshot;
      
      // Delay to ensure mask is rendered BEFORE we hide the button
      await new Promise<number>(r => setTimeout(r, 100));

      // 2. Hide UI elements (button) under the mask
      this.isSnapshotting = true;
      
      // 3. Prepare for scrolling capture
      this.scrollYOffsets = [];
      this.areaArray = [];
      
      // Scroll to top
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 0 } });
      await new Promise<number>(r => setTimeout(r, 100)); // Wait for scroll/render
      
      // 4. Start recursive snapshot loop
      await this.snapAndMerge();
      
      // 5. Save result
      if (this.areaArray.length > 0) {
         // Merge
         const lastOffset = this.scrollYOffsets[this.scrollYOffsets.length - 1] || 0;
         const mergedPixelMap = await ImageUtils.mergeImage(this.getUIContext(), this.areaArray, lastOffset, this.listComponentHeight);
         
         await this.shareSnapshot(mergedPixelMap);
         
         mergedPixelMap.release();
      }

    } catch (err) {
      console.error('Snapshot failed', JSON.stringify(err));
      promptAction.showToast({ message: '截图失败: ' + JSON.stringify(err) });
    } finally {
      // 6. Cleanup
      // Restore scroll to top
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 0 } });
      
      this.componentMaskImage = undefined;
      this.isSnapshotting = false;
      this.scrollYOffsets = [];
      this.areaArray = [];
    }
  }

  async snapAndMerge() {
    try {
      this.scrollYOffsets.push(this.curYOffset);
      
      // Capture
      const pixelMap = await this.getUIContext().getComponentSnapshot().get(REPORT_List_ID);
      
      // Process area
      const area = await ImageUtils.getSnapshotArea(
        this.getUIContext(), 
        pixelMap, 
        this.scrollYOffsets, 
        this.listComponentWidth, 
        this.listComponentHeight
      );
      this.areaArray.push(area);
      
      // Check if At End
      if (!this.scroller.isAtEnd()) {
        // Scroll down by one page height
        this.scroller.scrollBy(0, this.listComponentHeight);
        
        // Wait for scroll and render
        await new Promise<number>(r => setTimeout(r, 300));
        
        await this.snapAndMerge();
      }
    } catch (err) {
       console.error('snapAndMerge error', JSON.stringify(err));
       throw new Error(JSON.stringify(err));
    }
  }

  async shareSnapshot(pm: PixelMap) {
      // Pack to JPEG
      const imagePacker = image.createImagePacker();
      const packingOptions: image.PackingOption = { format: 'image/jpeg', quality: 100 };
      const buffer = await imagePacker.packing(pm, packingOptions);

      // Write temp file
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
          throw new Error("Context not found");
      }

      const fileName = `report_${new Date().getTime()}.jpg`;
      const filePath = context.cacheDir + `/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, buffer);
      fs.closeSync(file);

      // Construct Share Data
      const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.jpg', utd.UniformDataType.IMAGE);
      const uri = fileUri.getUriFromPath(filePath);
      
      const shareData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: uri,
        title: '订阅月报',
        description: '我的订阅月报'
      });

      // Show Share Panel
      const controller = new systemShare.ShareController(shareData);
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      }).then(() => {
        console.info('ShareController show success.');
      }).catch((error: BusinessError) => {
        console.error(`ShareController show error. code: ${error.code}, message: ${error.message}`);
        promptAction.showToast({ message: '分享调起失败' });
      });

      imagePacker.release();
  }

  // --- Snapshot Logic End ---

  @Builder
  ReportContent(data: ReportSummary) {
      Column() {
        if (data) {
           // 1. 顶部总览卡片
           Column() {
             Text('月度支出预估 (均摊)')
               .fontSize(14)
                                              .fontColor($r('app.color.text_secondary'))

             Text(`¥${data.totalForecast.toFixed(2)}`)
               .fontSize(36)
               .fontWeight(FontWeight.Bold)
                                              .fontColor($r('app.color.text_primary'))

               .margin({ top: 8 })

             Row() {
               Column() {
                 Text("月付项目")
                   .fontSize(12)
                                                  .fontColor($r('app.color.text_secondary'))

                 Text(`¥${data.totalMonthlyItems.toFixed(2)}`)
                   .fontSize(18)
                   .fontWeight(FontWeight.Bold)
                   .fontColor($r('app.color.text_primary'))
                   .margin({ top: 4 })
               }.layoutWeight(1).alignItems(HorizontalAlign.Start)

               Column() {
                 Text("年付均摊")
                   .fontSize(12)
                                                  .fontColor($r('app.color.text_secondary'))

                 Text(`¥${data.totalYearlyAmortized.toFixed(2)}`)
                   .fontSize(18)
                   .fontWeight(FontWeight.Bold)
                                                  .fontColor($r('app.color.text_primary'))

                   .margin({ top: 4 })
               }.layoutWeight(1).alignItems(HorizontalAlign.End)
             }
             .width('100%')
             .margin({ top: 20 })

             // 进度条
             Row({ space: 4 }) {
                 if (data.totalForecast > 0) {
                     if (data.totalMonthlyItems > 0) {
                         Rect()
                             .height(8)
                             .layoutWeight(data.totalMonthlyItems)
                             .fill(this.getThemeAccent())
                             .borderRadius(4)
                     }
                     if (data.totalYearlyAmortized > 0) {
                         Rect()
                             .height(8)
                             .layoutWeight(data.totalYearlyAmortized)
                             .fill($r('app.color.text_secondary'))
                             .opacity(0.3)
                             .borderRadius(4)
                     }
                 }
             }
             .width('100%')
             .margin({ top: 12 })
             
           }
           .width('100%')
           .padding(20)
           .backgroundColor($r('app.color.card_background'))
           .borderRadius(20)
           .margin({ bottom: 16 })
           .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.overviewLight,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.isOverviewPressed ? 0.98 : 1, y: this.isOverviewPressed ? 0.98 : 1 })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isOverviewPressed = true;
                    this.overviewLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isOverviewPressed = false;
                this.overviewLight = hdsEffect.PointLightSourceType.NONE;
              }
            })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .opacity(this.animStep1 ? 1 : 0)
            .translate({ y: this.animStep1 ? 0 : 20 })

           // 2. 支出分类占比
           if (data.categoryList.length > 0) {
             Column() {
               Text("预估分布")
                 .fontSize(16)
                 .fontWeight(FontWeight.Bold)
                                                .fontColor($r('app.color.text_primary'))

                 .width('100%')
                 .margin({ bottom: 16 })

               ForEach(data.categoryList, (cat: CategoryInfo) => {
                 Column() {
                   Row() {
                     Text(cat.name)
                       .fontSize(14)
                                                      .fontColor($r('app.color.text_primary'))

                     Blank()
                     Text(`¥${cat.amount.toFixed(2)} (${cat.percent.toFixed(1)}%)`)
                       .fontSize(14)
                                                      .fontColor($r('app.color.text_secondary'))

                   }
                   .width('100%')
                   
                   Progress({ value: cat.percent, total: 100, type: ProgressType.Linear })
                     .width('100%')
                     .height(4)
                     .color(this.getThemeAccent())
                     .opacity(0.6)
                     .margin({ top: 8, bottom: 12 })
                 }
               })
             }
             .width('100%')
             .padding(20)
             .backgroundColor($r('app.color.card_background'))
             .borderRadius(20)
             .margin({ bottom: 16 })
             .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.categoryLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .scale({ x: this.isCategoryPressed ? 0.98 : 1, y: this.isCategoryPressed ? 0.98 : 1 })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isCategoryPressed = true;
                      this.categoryLight = hdsEffect.PointLightSourceType.BRIGHT;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isCategoryPressed = false;
                  this.categoryLight = hdsEffect.PointLightSourceType.NONE;
                }
              })
              .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
             .opacity(this.animStep2 ? 1 : 0)
             .translate({ y: this.animStep2 ? 0 : 20 })
           }

           // 3. 最大占比发现
           if (data.maxSpender) {
               Row() {
                    Column() {
                        SubscriptionIcon({
                           icon: data.maxSpender.sub.recordType === 'groupBuy' ? this.getGroupBuyIcon(data.maxSpender.sub) : data.maxSpender.sub.icon,
                           name: data.maxSpender.sub.recordType === 'groupBuy' ? (data.maxSpender.sub.merchantName || data.maxSpender.sub.name) : data.maxSpender.sub.name,
                           iconSize: 44,
                           iconRadius: 10,
                           showGroupBadge: data.maxSpender.sub.recordType === 'groupBuy'
                        })
                    }
                    .padding({ right: 12 })

                   Column() {
                       Text("最大开销")
                           .fontSize(14)
                           .fontWeight(FontWeight.Bold)
                                                          .fontColor($r('app.color.text_primary'))

                       Text(`"${data.maxSpender.sub.name}" 是您最高的月均支出项，每月均摊 ¥${data.maxSpender.monthlyCost.toFixed(2)}。`)
                           .fontSize(13)
                                                          .fontColor($r('app.color.text_secondary'))

                           .margin({ top: 4 })
                   }
                   .layoutWeight(1)
                   .alignItems(HorizontalAlign.Start)
               }
               .width('100%')
               .padding(16)
               .backgroundColor($r('app.color.card_background')) // Use theme-adaptive card background
               .borderRadius(16)
               .margin({ bottom: 16 })
               .visualEffect(new hdsEffect.HdsEffectBuilder()
                 .pointLight({
                   sourceType: this.maxSpenderLight,
                   illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                 })
                 .buildEffect())
               .scale({ x: this.isMaxSpenderPressed ? 0.98 : 1, y: this.isMaxSpenderPressed ? 0.98 : 1 })
               .onTouch((event: TouchEvent) => {
                 if (event.type === TouchType.Down) {
                   if (this.isAnimationEnabled && this.isPointLightEnabled) {
                       this.isMaxSpenderPressed = true;
                       this.maxSpenderLight = hdsEffect.PointLightSourceType.BRIGHT;
                   }
                 } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                   this.isMaxSpenderPressed = false;
                   this.maxSpenderLight = hdsEffect.PointLightSourceType.NONE;
                 }
               })
               .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
               .opacity(this.animStep2 ? 1 : 0)
               .translate({ y: this.animStep2 ? 0 : 20 })
           }

           // 4. 预估明细列表
           Column() {
             Text("预估明细 (月均)")
               .fontSize(16)
               .fontWeight(FontWeight.Bold)
                                              .fontColor($r('app.color.text_primary'))

               .width('100%')
               .margin({ bottom: 16 })

             if (data.items.length === 0) {
               Text("暂无订阅")
                 .fontSize(14)
                                                .fontColor($r('app.color.text_secondary'))

                 .padding({ top: 20, bottom: 20 })
             }

              ForEach(data.items, (item: ReportItem, index: number) => {
                Row() {
                     SubscriptionIcon({
                        icon: item.sub.recordType === 'groupBuy' ? this.getGroupBuyIcon(item.sub) : item.sub.icon,
                        name: item.sub.recordType === 'groupBuy' ? (item.sub.merchantName || item.sub.name) : item.sub.name,
                        iconSize: 40,
                        iconRadius: 8,
                        showGroupBadge: item.sub.recordType === 'groupBuy'
                     })
 
                    Column() {
                      Text(item.sub.recordType === 'groupBuy' ? (item.sub.merchantName || item.sub.name) : item.sub.name)
                      .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))

                     Text(this.getItemInfo(item.sub))
                       .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))

                       .margin({ top: 2 })
                   }
                   .margin({ left: 12 })
                   .layoutWeight(1)
                   .alignItems(HorizontalAlign.Start)

                   Column() {
                      Text(`¥${item.monthlyCost.toFixed(2)}`)
                         .fontSize(15)
                         .fontWeight(FontWeight.Bold)
                                                       .fontColor($r('app.color.text_primary'))

                      Text(item.sub.recordType === 'warranty' ? '一次性' : (item.sub.billingCycle === 'Lifetime' || item.sub.billingCycle === 'Indefinite' || item.sub.recordType === 'groupBuy' ? '一次性' : '/月'))
                         .fontSize(11)
                                                        .fontColor($r('app.color.text_secondary'))

                   }
               }
               .width('100%')
               .padding(12)
               .backgroundColor($r('app.color.page_background'))
               .borderRadius(12)
               .margin({ bottom: 8 })
               .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.pressedItemIndex === index ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
               .scale({ x: this.pressedItemIndex === index ? 0.98 : 1, y: this.pressedItemIndex === index ? 0.98 : 1 })
               .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                        this.pressedItemIndex = index;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.pressedItemIndex = -1;
                  }
               })
               .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
             }, (item: ReportItem, index: number) => item?.sub?.id ? item.sub.id.toString() : index.toString())
           }
            .width('100%')
            .padding(20)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(20)
            .margin({ bottom: 40 })
            .opacity(this.animStep3 ? 1 : 0)
            .translate({ y: this.animStep3 ? 0 : 20 })

           // 5. 底部 Logo
           Row() {
             Image($r('app.media.startIcon'))
               .width(20)
               .height(20)
               .borderRadius(4)
             Text($r('app.string.EntryAbility_label'))
               .fontSize(12)
               .fontWeight(FontWeight.Medium)
               .fontColor($r('app.color.text_secondary'))

               .margin({ left: 8 })
           }
           .width('100%')
           .justifyContent(FlexAlign.Center)
           .padding({ bottom: 32 })
           .opacity(0.6)

        } else {
           LoadingProgress().width(48).height(48).color($r('app.color.brand_color'))
        }
      }
      .width('100%')
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder MonthlyBuilder(){
    if (this.reportData) {
      Scroll(this.scroller) {
        Column() {
          // 额外顶部留白，以便内容在滚动时进入标题栏模糊区
          Column().height(64).width('100%') 
          
          this.ReportContent(this.reportData)
        }
        .padding({ bottom: 40, left: 16, right: 16 })
      }
      .id(REPORT_List_ID)
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        this.curYOffset = this.scroller.currentOffset().yOffset;
      })
      .onAreaChange((oldValue, newValue) => {
        this.listComponentWidth = newValue.width as number;
        this.listComponentHeight = newValue.height as number;
      })
      .overlay(this.SnapshotOverlay())
    } else {
      Column() {
        LoadingProgress().width(48).height(48).color($r('app.color.brand_color'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  build() {
    HdsNavigation(this.navStack) {
      this.MonthlyBuilder()
    }
    .backgroundColor($r('app.color.page_background'))
    .titleBar({
      content: {
        title: { mainTitle: '订阅月报' },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.share'),
                action: () => {
                  this.startSnapshot();
                }
              }
            },
            {
              content: {
                icon: $r('sys.symbol.xmark'),
                action: () => {
                  this.onClose();
                }
              }
            }
          ]
        }
      },

    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
  }
}
