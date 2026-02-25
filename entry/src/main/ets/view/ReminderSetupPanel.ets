import { SubscriptionModel, ExtendedWarrantyItem } from '../model/SubscriptionModel';
import { promptAction, curves, LengthMetrics } from '@kit.ArkUI';
import { hdsEffect,
  hdsMaterial,
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigation, HdsNavigationTitleMode,
  ScrollEffectType } from '@kit.UIDesignKit';
import { SubscriptionIcon } from './SubscriptionIcon';
import { deviceInfo } from '@kit.BasicServicesKit';

const TITLE_BAR_HEIGHT_MINI: number = 76;

interface DisplayItem {
  key: string;
  displayName: string;
  type: 'subscription' | 'groupBuy' | 'warranty' | 'warranty_sub' | 'card';
  raw: SubscriptionModel;
  warrantyRaw?: ExtendedWarrantyItem;
  reminderDaysBefore?: number;
  reminderTime?: string;
  parentIcon?: string;
  parentName?: string;
}

@Component
export struct ReminderSetupPanel {
  @Link subscriptions: SubscriptionModel[];
  @Watch('onSetupVisibleChange') @Link isSetupVisible: boolean;
  @Watch('onActiveItemChange') @Link activeItem: SubscriptionModel | null;
  @Link sheetWidth: number;

  @State activeWarrantyItem: ExtendedWarrantyItem | undefined = undefined;
  @State activeParentForWarranty: SubscriptionModel | null = null;
  
  @Provide('navPathStack') navStack: NavPathStack = new NavPathStack();
  
  onSave: (item: SubscriptionModel, days: number, time: string) => void = () => {};
  onCancel: () => void = () => {};
  onRemove: (item: SubscriptionModel) => void = () => {};
  
  // Local state for editing
  @State selectedDays: number = 1;
  @State selectedTime: Date = new Date();
  
  // Theme & Animation System
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('animationDamping') animationDamping: number = 0.5;

  @State saveLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  
  @State pressedDay: number = -1; // For tracking press animation on days
  @State isSavePressed: boolean = false;
  @State isRemovePressed: boolean = false; // Add state for remove button
  @State removeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @StorageLink('topRectHeight') topRectHeight: number = 0;
  private reminderDaysOptions: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30'];

  aboutToAppear() {
    this.refreshData();
    if (this.isAnimationEnabled) {
      setTimeout(() => {
          this.areItemsVisible = true;
      }, 100);
    } else {
      this.areItemsVisible = true;
    }
  }

  @State areItemsVisible: boolean = false;
  @State isDetailVisible: boolean = false;

  // Allow Parent to force refresh if item changes
  refreshData() {
    if (!this.activeItem) return;
    this.selectedDays = this.activeItem.reminderDaysBefore !== undefined ? this.activeItem.reminderDaysBefore : 1;
    const timeStr = this.activeItem.reminderTime || '09:00';
    const parts = timeStr.split(':');
    const date = new Date();
    // Default to 09:00 if invalid
    if (parts.length >= 2) {
        date.setHours(parseInt(parts[0]), parseInt(parts[1]), 0, 0);
    } else {
        date.setHours(9, 0, 0, 0);
    }
    this.selectedTime = date;
  }
  
  onActiveItemChange() {
      // 只有在 activeItem 存在时才处理进入逻辑
      if (this.activeItem) {
          this.isDetailVisible = !this.isAnimationEnabled;
          this.refreshData();
          // 如果栈为空，则推入详情页
          if (this.navStack.size() === 0) {
              this.navStack.pushPath({ name: 'ReminderDetails' });
          }
      }
  }

  onSetupVisibleChange() {
      // 当外部或内部关闭设置视图时，同步清理栈和 activeItem
      if (!this.isSetupVisible) {
          // if (this.navStack.size() > 0) {
          //     this.navStack.clear();
          // }
          // if (this.activeItem) {
          //     this.activeItem = null;
          // }
      }
  }

  // Helper to get brand color based on theme
  private getThemeColor(): ResourceColor {
    if (this.isNewYearTheme) {
        return $r('app.color.new_year_red_start');
    }
    if (this.showVipTheme) {
        return $r('app.color.vip_gold_start');
    }
    return $r('app.color.brand_color');
  }
  
  private getThemeTextColor(): ResourceColor {
      if (this.isNewYearTheme) return '#FFD700';
      if (this.showVipTheme) return $r('app.color.vip_text_on_gold');
      return Color.White;
  }

  getGroupBuyIcon(sub: SubscriptionModel): string {
    if (sub.platform === 'meituan') return 'resource:meituan_logo';
    if (sub.platform === 'douyin') return 'resource:douyin_logo';
    if (sub.platform === 'dianping') return 'resource:dianping_logo';
    return sub.icon ?? '';
  }

  private getReminderCount(): number {
    let count = this.subscriptions.filter(s => s.reminderDaysBefore !== undefined).length;
    // 累加延保子项提醒
    this.subscriptions.forEach(s => {
      if (s.extendedWarranties) {
        try {
          const items: ExtendedWarrantyItem[] = JSON.parse(s.extendedWarranties);
          count += items.filter(i => i.isReminderEnabled).length;
        } catch (e) {}
      }
    });
    return count;
  }

  private getDisplayList(): DisplayItem[] {
    const list: DisplayItem[] = [];
    this.subscriptions.forEach(s => {
      // 1. 添加主项目 (如果是永久订阅且不是保修或卡证，则忽略)
      if (s.billingCycle !== 'Lifetime' || s.recordType === 'warranty' || s.recordType === 'card') {
        list.push({
          key: `${s.uuid}_main`,
          displayName: s.name,
          type: s.recordType || 'subscription',
          raw: s,
          reminderDaysBefore: s.reminderDaysBefore,
          reminderTime: s.reminderTime
        });
      }

      // 2. 添加延保子项
      if (s.extendedWarranties) {
        try {
          const items: ExtendedWarrantyItem[] = JSON.parse(s.extendedWarranties);
          items.forEach(item => {
            // 只有开启了提醒的才显示在管理列表中
            if (item.isReminderEnabled) {
              list.push({
                key: `${s.uuid}_warranty_${item.id}`,
                displayName: `${s.name} - ${item.name}`,
                type: 'warranty_sub',
                raw: s,
                warrantyRaw: item,
                reminderDaysBefore: s.reminderDaysBefore, // 子项目前复用父项的时间设置逻辑（根据原有 AddSubscription 逻辑）
                reminderTime: s.reminderTime,
                parentIcon: s.icon,
                parentName: s.name
              });
            }
          });
        } catch (e) {}
      }
    });
    return list;
  }

  private closePanel() {
    this.isSetupVisible = false;
    this.onCancel();
  }

  private refreshWarrantyData() {
    if (this.activeParentForWarranty) {
      this.selectedDays = this.activeParentForWarranty.reminderDaysBefore || 1;
      const timeStr = this.activeParentForWarranty.reminderTime || '09:00';
      const hours = parseInt(timeStr.split(':')[0]);
      const minutes = parseInt(timeStr.split(':')[1]);
      this.selectedTime.setHours(hours, minutes, 0, 0);
    }
  }

  @Builder ReminderEmptyState() {
    Column() {
      SymbolGlyph($r('sys.symbol.bell_slash'))
        .fontSize(64)
        .fontColor([$r('app.color.text_hint')])
        .margin({ bottom: 16 })
      Text('暂无需要提醒的订阅')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
      Text('只有非永久订阅或保修物品才支持到期提醒')
        .fontSize(13)
        .fontColor($r('app.color.text_hint'))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
  
  @Builder
  limitTag() {
    Row() {
      Text('已达上限')
        .fontSize(10)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.warning_color'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(6)
    }
    .margin({ left: 8 })
  }

  @Builder
  pageMap(name: string) {
    if (name === 'ReminderDetails') {
        HdsNavDestination() {
          if (this.activeItem) {
            Column() {
              // Card Container for Settings
              Column() {
                // Days Selection Section
                Text('提醒日期')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 12 })

                Row() {
                  Text(`提前 ${this.selectedDays} 天`)
                    .fontSize(15)
                    .fontColor(this.getThemeColor())
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([$r('app.color.text_hint')])
                }
                .width('100%')
                .height(48)
                .padding({ left: 16, right: 12 })
                .backgroundColor($r('app.color.tag_bg'))
                .borderRadius(14)
                .margin({ bottom: 16 })
                .onClick(() => {
                  TextPickerDialog.show({
                    range: this.reminderDaysOptions,
                    selected: this.reminderDaysOptions.indexOf(this.selectedDays.toString()),
                    onAccept: (value: TextPickerResult) => {
                      this.selectedDays = parseInt(value.value as string);
                    }
                  })
                })

                // Time Selection Section
                Text('提醒时间')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })

                TimePicker({ selected: this.selectedTime })
                  .useMilitaryTime(true)
                  .onChange((value: TimePickerResult) => {
                    this.selectedTime.setHours(value.hour, value.minute);
                  })
                  .height(140)
                  .margin({ bottom: 12 })
                  .selectedTextStyle({ color: this.getThemeColor(), font: { size: '18fp', weight: FontWeight.Bold } })
              }
              .width('100%')
              .padding(20)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(24)
              .margin({ bottom: 24 })
              .shadow({ radius: 30, color: 'rgba(0,0,0,0.08)', offsetY: 12 })

              // Buttons Footer
              Row() {
                if (this.activeItem.reminderDaysBefore !== undefined) {
                  Button() {
                    Column() {
                      Text(this.activeWarrantyItem ? '关闭该项提醒' : '关闭提醒')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.Red)

                      Text(this.activeWarrantyItem ? `不再提醒 ${this.activeParentForWarranty?.name} 的 [${this.activeWarrantyItem.name}] 额外保障。` : (this.activeItem?.billingCycle === 'Lifetime' || this.activeItem?.recordType === 'warranty' ? '关闭该项目的到期提醒。' : '关闭后，您将不再收到该订阅的续费和到期提醒通知。'))
                        .fontSize(12)
                        .fontColor($r('app.color.text_hint'))
                        .margin({ top: 4 })
                        .textAlign(TextAlign.Center)
                    }
                  }
                  .backgroundColor($r('app.color.tag_bg'))
                  .padding({ left: 16, right: 16 })
                  .height(60)
                  .borderRadius(16)
                  .margin({ right: 12 })
                    .scale({ x: this.isRemovePressed ? 0.95 : 1, y: this.isRemovePressed ? 0.95 : 1 })
                    .animation({
                      duration: this.isAnimationEnabled ? 150 : 0,
                      curve: curves.springMotion(this.animationResponse, this.animationDamping)
                    })
                    .visualEffect(new hdsEffect.HdsEffectBuilder()
                      .pointLight({
                        sourceType: this.removeLight,
                        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                      })
                      .buildEffect())
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        if (this.isAnimationEnabled) {
                          this.isRemovePressed = true;
                          if (this.isPointLightEnabled) {
                            this.removeLight = hdsEffect.PointLightSourceType.BRIGHT;
                          }
                        }
                      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                        this.isRemovePressed = false;
                        this.removeLight = hdsEffect.PointLightSourceType.NONE;
                      }
                    })
                    .onClick(() => {
                      if (this.activeItem) {
                        if (this.activeWarrantyItem && this.activeParentForWarranty) {
                            // 关闭延保子项提醒逻辑
                            try {
                                const items: ExtendedWarrantyItem[] = JSON.parse(this.activeParentForWarranty.extendedWarranties || '[]');
                                const index = items.findIndex(i => i.id === this.activeWarrantyItem!.id);
                                if (index !== -1) {
                                    items[index].isReminderEnabled = false;
                                    this.activeParentForWarranty.extendedWarranties = JSON.stringify(items);
                                    // 重新保存父项以同步数据库
                                    const timeStr = `${this.selectedTime.getHours().toString().padStart(2, '0')}:${this.selectedTime.getMinutes().toString().padStart(2, '0')}`;
                                    this.onSave(this.activeParentForWarranty, this.selectedDays, timeStr);
                                }
                            } catch (e) {}
                        } else {
                            this.onRemove(this.activeItem);
                        }
                        this.navStack.pop();
                      }
                    })
                }

                Button('保存设置')
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
                  .fontColor(this.getThemeTextColor())
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(25)
                  .shadow({
                    radius: 10,
                    color: this.isNewYearTheme ? '#40FF2400' : (this.showVipTheme ? '#40E6C07B' : '#40007AFF'),
                    offsetY: 5
                  })
                  .scale({ x: this.isSavePressed ? 0.98 : 1, y: this.isSavePressed ? 0.98 : 1 })
                  .animation({
                    duration: this.isAnimationEnabled ? 150 : 0,
                    curve: curves.springMotion(this.animationResponse, this.animationDamping)
                  })
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: this.saveLight,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
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
                  .onClick(() => {
                    if (!this.activeItem) {
                      return;
                    }

                    // 1. Limit Check
                    if (!this.activeWarrantyItem) {
                        if (this.activeItem.reminderDaysBefore === undefined && this.getReminderCount() >= 30) {
                            promptAction.showToast({ message: '提醒数量已达上限 (30个)' });
                            return;
                        }
                    }

                    // 2. Validation
                    const targetDate = new Date(this.activeItem.nextBillingDate);
                    targetDate.setDate(targetDate.getDate() - this.selectedDays);
                    targetDate.setHours(this.selectedTime.getHours(), this.selectedTime.getMinutes(), 0, 0);

                    if (targetDate.getTime() < new Date().getTime()) {
                      promptAction.showToast({ message: '设置的提醒时间已过期，请调整' });
                      return;
                    }

                    const timeStr =
                      `${this.selectedTime.getHours().toString().padStart(2, '0')}:${this.selectedTime.getMinutes()
                        .toString()
                        .padStart(2, '0')}`;

                    if (this.activeWarrantyItem && this.activeParentForWarranty) {
                        // 更新延保子项逻辑
                        try {
                            const items: ExtendedWarrantyItem[] = JSON.parse(this.activeParentForWarranty.extendedWarranties || '[]');
                            const index = items.findIndex(i => i.id === this.activeWarrantyItem!.id);
                            if (index !== -1) {
                                items[index].isReminderEnabled = true;
                                this.activeParentForWarranty.extendedWarranties = JSON.stringify(items);
                                // 根据原有逻辑，提醒时间可能存储在父项或子项？
                                // 查看 AddSubscription 逻辑，提醒时间目前全局共享在父项。
                                this.onSave(this.activeParentForWarranty, this.selectedDays, timeStr);
                            }
                        } catch (e) {}
                    } else {
                        this.onSave(this.activeItem, this.selectedDays, timeStr);
                    }
                    this.navStack.pop();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Bottom)
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
            }
            .width('100%')
            .height('100%')
            .padding({
              left: 24,
              right: 24,
              bottom: 32,
              top: 84
            }) // Adjusted for Safe Area
            .opacity(this.isDetailVisible ? 1 : 0)
            .translate({ y: this.isDetailVisible ? 0 : 20 })
            .animation({
              duration: this.isAnimationEnabled ? this.animationDuration : 0,
              curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) :
                Curve.Linear
            })
            .onAppear(() => {
              if (this.isAnimationEnabled) {
                setTimeout(() => {
                  this.isDetailVisible = true;
                }, 50);
              } else {
                this.isDetailVisible = true;
              }
            })

          }
        }
        .titleBar({
          content: {
            title: { 
              mainTitle: this.activeWarrantyItem ? this.activeWarrantyItem.name : (this.activeItem ? this.activeItem.name : '设置提醒'),
              subTitle: this.activeWarrantyItem ? `来自: ${this.activeParentForWarranty?.name}` : ''
            },
            menu: {
              value: [
                {
                  content: {
                    icon: $r('sys.symbol.xmark'),
                    action: () => {
                      this.closePanel();
                    }
                  }
                }
              ]
            }
          },
          style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ?{
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
          }:undefined
        })
        .titleMode(HdsNavDestinationTitleMode.MODAL)
        .onBackPressed(() => {
          this.navStack.pop();
          return true;
        })

    }
  }
  @Builder reminderBuilder(){
    Column() {
      Column() {
        if (this.subscriptions.filter(s => s.billingCycle !== 'Lifetime' || s.recordType === 'warranty').length === 0) {
          this.ReminderEmptyState()
        } else {
          List() {
            ListItem() {
              Column() {
                Blank()
                  .height(TITLE_BAR_HEIGHT_MINI)
              }
            }

            ForEach(this.getDisplayList(), (item: DisplayItem, idx) => {
              ListItem() {
                Row() {
                  SubscriptionIcon({
                    icon: item.type === 'groupBuy' ? this.getGroupBuyIcon(item.raw) : (item.type === 'warranty_sub' ? item.parentIcon : item.raw.icon),
                    name: item.type === 'warranty_sub' ? (item.parentName) : (item.type === 'groupBuy' ? (item.raw.merchantName || item.raw.name) : item.raw.name),
                    iconSize: 40,
                    iconRadius: 10,
                    showGroupBadge: item.type === 'groupBuy'
                  })
                    .margin({ right: 12 })

                  Column() {
                    Text(item.displayName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    if (item.reminderDaysBefore !== undefined) {
                      Text(`提醒: 提前${item.reminderDaysBefore}天 ${item.reminderTime || '09:00'}`)
                        .fontSize(13).fontColor($r('app.color.text_secondary')).margin({ top: 4 })
                    } else {
                      Text('未设置提醒')
                        .fontSize(13).fontColor($r('app.color.text_hint')).margin({ top: 4 })
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1)

                  Button() {
                    SymbolGlyph($r('sys.symbol.square_and_pencil'))
                      .fontSize(18)
                      .fontColor([$r('app.color.text_hint')])
                  }
                  .backgroundColor(Color.Transparent)
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
                .onClick(() => {
                  if (item.type === 'warranty_sub') {
                    this.activeWarrantyItem = item.warrantyRaw;
                    this.activeParentForWarranty = item.raw;
                    this.activeItem = item.raw; // 借用 activeItem 触发 UI 跳转
                    this.refreshWarrantyData();
                  } else {
                    this.activeWarrantyItem = undefined;
                    this.activeParentForWarranty = null;
                    this.activeItem = item.raw;
                    this.refreshData();
                  }
                })
              }
              .opacity(this.areItemsVisible ? 1 : 0)
              .translate({ y: this.areItemsVisible ? 0 : 20 })
              .animation({
                delay: (this.isAnimationEnabled && idx) ? idx * 50 : 0,
                duration: this.isAnimationEnabled ? this.animationDuration : 0,
                curve: curves.springMotion(this.animationResponse, this.animationDamping)
              })
            }, (item: DisplayItem) => item.key)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
        }
      }
    }
    .width('100%')
    .height('100%')
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  build() {
    HdsNavigation(this.navStack) {
      this.reminderBuilder()
    }
    .backgroundColor($r('app.color.page_background'))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .titleBar({
      content: {
        title: { mainTitle: "提醒管理", subTitle: `已设置 ${this.getReminderCount()}/30 个提醒` },
        stackBuilder: this.getReminderCount() >= 30 ? () => {
          this.limitTag()
        } : undefined,
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.xmark'),
                action: () => {
                  this.closePanel();
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
  }

}
