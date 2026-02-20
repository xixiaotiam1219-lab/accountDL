import { SubscriptionModel } from '../model/SubscriptionModel';
import { promptAction, curves, LengthMetrics } from '@kit.ArkUI';
import { hdsEffect,
  hdsMaterial,
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigation, HdsNavigationTitleMode,
  ScrollEffectType } from '@kit.UIDesignKit';
import { SubscriptionIcon } from './SubscriptionIcon';
import { deviceInfo } from '@kit.BasicServicesKit';

@Component
export struct ReminderSetupPanel {
  @Link subscriptions: SubscriptionModel[];
  @Watch('onSetupVisibleChange') @Link isSetupVisible: boolean;
  @Watch('onActiveItemChange') @Link activeItem: SubscriptionModel | null;
  @Link sheetWidth: number;
  
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
      // 如果关闭动画，则直接显示状态（true），避免 0->1 的状态变化
      // 如果开启动画，则先设为 false，通过 onAppear 触发动画
      this.isDetailVisible = !this.isAnimationEnabled;
      this.refreshData();
      if (this.activeItem) {
          // If the stack is empty, it means we are in the list view or just opening, so push the details page
          if (this.navStack.size() === 0) {
              setTimeout(() => {
                  this.navStack.pushPath({ name: 'ReminderDetails' });
              }, 0);
          }
          if (!this.isSetupVisible) {
              this.isSetupVisible = true;
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
    .padding({ bottom: 60 })
  }

  @Builder navDestination(name: string) {
    if (name === 'ReminderDetails') {
      if (deviceInfo.distributionOSApiVersion >= 60100&&this.isHdsTabsEnabled) {
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
                  Button('关闭提醒')
                    .backgroundColor($r('app.color.tag_bg'))
                    .fontColor(Color.Red)
                    .fontSize(16)
                    .height(50)
                    .borderRadius(25)
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
                        this.onRemove(this.activeItem);
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

                    // Validation
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
                    this.onSave(this.activeItem, this.selectedDays, timeStr);
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
            title: { mainTitle: this.activeItem ? this.activeItem.name : '设置提醒' },
            menu: {
              value: [
                {
                  content: {
                    icon: $r('sys.symbol.xmark'),
                    action: () => {
                      this.onCancel();
                    }
                  }
                }
              ]
            }
          },
          style: {
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
          }
        })
        .titleMode(HdsNavDestinationTitleMode.MODAL)
        .onBackPressed(() => {
          this.navStack.pop();
          this.isSetupVisible = false;
          return true;
        })
      } else {
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
                  Button('关闭提醒')
                    .backgroundColor($r('app.color.tag_bg'))
                    .fontColor(Color.Red)
                    .fontSize(16)
                    .height(50)
                    .borderRadius(25)
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
                        this.onRemove(this.activeItem);
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

                    // Validation
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
                    this.onSave(this.activeItem, this.selectedDays, timeStr);
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
            title: { mainTitle: this.activeItem ? this.activeItem.name : '设置提醒' },
            menu: {
              value: [
                {
                  content: {
                    icon: $r('sys.symbol.xmark'),
                    action: () => {
                      this.onCancel();
                    }
                  }
                }
              ]
            }
          },
        })
        .titleMode(HdsNavDestinationTitleMode.MODAL)
        .onBackPressed(() => {
          this.navStack.pop();
          this.isSetupVisible = false;
          return true;
        })
      }
    }
  }
  @Builder reminderBuilder(){
    Column() {
      Column() {
        if (this.subscriptions.filter(s => s.billingCycle !== 'Lifetime' || s.recordType === 'warranty').length === 0) {
          this.ReminderEmptyState()
        } else {
          List() {
            ForEach(this.subscriptions.filter(s => s.billingCycle !== 'Lifetime' || s.recordType === 'warranty'),
              (item: SubscriptionModel, idx) => {
                ListItem() {
                  Row() {
                    SubscriptionIcon({
                      icon: item.recordType === 'groupBuy' ? this.getGroupBuyIcon(item) : item.icon,
                      name: item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name,
                      iconSize: 40,
                      iconRadius: 10,
                      showGroupBadge: item.recordType === 'groupBuy'
                    })
                      .margin({ right: 12 })

                    Column() {
                      Text(item.name)
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
                    // 仅修改 activeItem，由于设置了 @Watch，它会自动处理导航 push
                    this.activeItem = item;
                  })
                }
                .opacity(this.areItemsVisible ? 1 : 0)
                .translate({ y: this.areItemsVisible ? 0 : 20 })
                .animation({
                  delay: (this.isAnimationEnabled && idx) ? idx * 50 : 0,
                  duration: this.isAnimationEnabled ? this.animationDuration : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })
              }, (item: SubscriptionModel) => `${item.uuid}_reminder_${item.reminderDaysBefore}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16 })
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Off)
        }
      }
      .padding({ top: 56 }) // TopSafeContainer simulation
    }
    .width('100%')
    .height('100%')
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  build() {
    if (deviceInfo.distributionOSApiVersion >= 60100&&this.isHdsTabsEnabled) {
      HdsNavigation(this.navStack) {
          this.reminderBuilder()
      }
      .backgroundColor(Color.Transparent)
      .titleBar({
        content: {
          title: { mainTitle: "提醒管理" },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.xmark'),
                  action: () => {
                    this.onCancel();
                  }
                }
              }
            ]
          }
        },
        style: {
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
        }
      })
      .titleMode(HdsNavigationTitleMode.MODAL)
      .navDestination(this.navDestination)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    } else {
      HdsNavigation(this.navStack) {
        this.reminderBuilder()
      }
      .backgroundColor(Color.Transparent)
      .titleBar({
        content: {
          title: { mainTitle: "提醒管理" },
          menu: {
            value: [
              {
                content: {
                  icon: $r('sys.symbol.xmark'),
                  action: () => {
                    this.onCancel();
                  }
                }
              }
            ]
          }
        },
      })
      .titleMode(HdsNavigationTitleMode.MODAL)
      .navDestination(this.navDestination)
      .mode(NavigationMode.Stack)
      .hideBackButton(true)
      .backgroundColor($r('app.color.page_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
    }
  }

}
