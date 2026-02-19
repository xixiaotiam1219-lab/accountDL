import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionIcon } from './SubscriptionIcon';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { promptAction } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { GlobalBus, EVENT_DATA_CHANGED, EVENT_SYNC_COMPLETED } from '../utils/GlobalBus';
import { LocalNotificationManager } from '../manager/LocalNotificationManager';
import { commonEventManager } from '@kit.BasicServicesKit';

@Component
export struct SubscriptionDetailOverlay {
  @Prop data: SubscriptionModel;
  @StorageLink('isDetailVisible') isDetailVisible: boolean = false;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  // Interaction States
  @State isEditPressed: boolean = false;
  @State editLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isDeletePressed: boolean = false;
  @State deleteLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isMarkUsedPressed: boolean = false;
  @State isDataStable: boolean = false; // 用于控制平稳渲染，避免数据跳变
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  async aboutToAppear() {
    this.subscriber = await GlobalBus.subscribe(EVENT_SYNC_COMPLETED, () => {
      this.refreshData();
    });
    // 立即刷新一次数据，确保从卡片进入时显示最新内容
    this.refreshData();
  }

  aboutToDisappear() {
    if (this.subscriber) {
      GlobalBus.unsubscribe(this.subscriber);
      this.subscriber = null;
    }
  }

  private async refreshData() {
    if (!this.data) return;

    const uuid = this.data.uuid;
    const id = this.data.id;

    if (uuid || id) {
      let latest: SubscriptionModel | null = null;
      if (uuid) {
        latest = await SubscriptionRepository.getInstance().findByUuid(uuid);
      }
      if (!latest && id) {
        latest = await SubscriptionRepository.getInstance().findById(id);
      }

      if (latest) {
        this.data = latest;
      }
      // 无论是否查到，只要执行完查询就认为处于“稳定”状态
      animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        this.isDataStable = true;
      });
    } else {
      this.isDataStable = true;
    }
  }

  getBillingCycleShortText(): string {
    switch (this.data.billingCycle) {
      case 'Monthly':
        return '月付';
      case 'Quarterly':
        return '季付';
      case 'Yearly':
        return '年付';
      case 'Lifetime':
        return '永久';
      case 'Indefinite':
        return '不定';
      default:
        return '';
    }
  }

  @Builder
  LanternDecoration() {
    Text('🏮')
      .fontSize(100)
      .opacity(0.12)
      .rotate({ angle: -15 })
      .position({ right: -20, bottom: -20 })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      // 1. 模糊背景/遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent) // 透明背景，完全依赖毛玻璃
        .backgroundBlurStyle(BlurStyle.Regular) // 常规毛玻璃，或者 COMPONENT_THICK
        .onClick(() => {
          // 点击空白处关闭
          AppStorage.setOrCreate('isDetailClosing', true);
          animateTo({
            duration: this.isAnimationEnabled ? this.animationDuration : 0,
            curve: this.isAnimationEnabled ? Curve.FastOutSlowIn : Curve.Linear
          }, () => {
            this.isDetailVisible = false;
          })
          setTimeout(() => {
            AppStorage.setOrCreate('isDetailClosing', false);
          }, this.isAnimationEnabled ? this.animationDuration + 50 : 50);
        })
        .transition(TransitionEffect.OPACITY.animation({
          duration: this.isAnimationEnabled ? this.animationDuration : 0,
          curve: Curve.EaseOut
        }))

      // 2. 详情卡片 (放大的主体)
      // 使用 flex 布局或者 alignContent: Center 让卡片居中
      Column() {
        Stack() {
          if (this.isNewYearTheme) {
            this.LanternDecoration()
          }

          Column() {
            Row() {
              SubscriptionIcon({
                icon: this.data.recordType === 'groupBuy' ?
                  (this.data.platform === 'meituan' ? 'resource:meituan_logo' :
                    (this.data.platform === 'douyin' ? 'resource:douyin_logo' : 'resource:dianping_logo')) :
                  this.data.icon,
                name: this.data.recordType === 'groupBuy' ? (this.data.merchantName || this.data.name) : this.data.name,
                iconSize: 72,
                iconRadius: 20,
                showGroupBadge: this.data.recordType === 'groupBuy'
              })
                .margin({ right: 16 })

              Column() {
                Text(this.data.name)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_title') :
                    (this.showVipTheme ? $r('app.color.sub_card_vip_title') : $r('app.color.text_primary')))
                  .margin({ bottom: 8 })

                Text(this.data.recordType === 'groupBuy' ?
                  ((this.data.merchantName ? this.data.merchantName + ' · ' : '') +
                    (this.data.platform === 'meituan' ? '美团' :
                      (this.data.platform === 'dianping' ? '大众点评' : '抖音'))) :
                  (this.data.recordType === 'warranty' ?
                    ((this.data.brand || '保修期') + (this.data.purchaseChannel ? ` · ${this.data.purchaseChannel}` : '')) :
                    (this.getBillingCycleShortText() + (this.data.category ? ` · ${this.data.category}` : ''))))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .opacity(0.8)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 24 })

            Divider().opacity(0.1).margin({ bottom: 20 })

            // 中部：详细属性与按钮（在数据稳定后再显示，避免跳变）
            Column() {
              Column({ space: 16 }) {
                // 价格详情
                Row() {
                  Text(this.data.recordType === 'groupBuy' ? '支付金额' : (this.data.recordType === 'warranty' ? '购买价格' : '价格'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Row() {
                    Text(this.data.currency === 'USD' ? '$' : '¥')
                      .fontSize(14)
                      .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.text_primary')))
                      .margin({ right: 4, top: 2 })
                    Text((this.data.price || 0).toFixed(2))
                      .fontSize(24)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                        (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.text_primary')))
                  }
                  .alignItems(VerticalAlign.Bottom)
                }
                .width('100%')

                if (this.data.recordType === 'groupBuy') {
                  // 团购券码
                  if (this.data.couponCode) {
                    Row() {
                      Text('团购券码')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.couponCode)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }

                  // 团购券码图片/截图
                  if (this.data.couponImage) {
                    Image(this.data.couponImage)
                      .width('100%')
                      .height(160)
                      .objectFit(ImageFit.Contain)
                      .backgroundColor($r('app.color.page_background'))
                      .borderRadius(12)
                      .margin({ top: 12, bottom: 4 })
                      .onClick(() => {
                        // TODO: Implement full screen view if needed
                      })
                  }

                  // 团购数量
                  Row() {
                    Text('购买数量')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(`${this.data.quantity || 1} 张`)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                  }
                  .width('100%')

                  // 有效期至
                  Row() {
                    Text('有效期至')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(DateUtil.formatDate(this.data.nextBillingDate) || '未设置')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 3
                        ? (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                          (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')))
                        : $r('app.color.text_primary'))
                  }
                  .width('100%')

                  // 使用状态
                  Row() {
                    Text('使用状态')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(this.data.usageStatus === 'used' ? '已使用' :
                      this.data.usageStatus === 'expired' ? '已过期' : '未使用')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.data.usageStatus === 'used' ? '#9E9E9E' :
                        this.data.usageStatus === 'expired' ? '#F44336' : '#4CAF50')
                  }
                  .width('100%')

                } else if (this.data.recordType === 'warranty') {
                  // ========== 保修/保质期详情 ==========
                  // 品牌
                  if (this.data.brand) {
                    Row() {
                      Text('品牌')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.brand)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }

                  // 购买渠道
                  if (this.data.purchaseChannel) {
                    Row() {
                      Text('购买渠道')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.purchaseChannel)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }

                  // 购买日期
                  if (this.data.startDate) {
                    Row() {
                      Text('购买日期')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(DateUtil.formatDate(this.data.startDate) || '未设置')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }

                  // 保修到期日
                  Row() {
                    Text('保修到期')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(DateUtil.formatDate(this.data.nextBillingDate) || '未设置')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 30
                        ? (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                          (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')))
                        : $r('app.color.text_primary'))
                  }
                  .width('100%')

                  // 保修剩余天数
                  Row() {
                    Text('剩余天数')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 0 ? '已过保修期' :
                      `${DateUtil.getDaysUntil(this.data.nextBillingDate)} 天`)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 0 ? '#F44336' :
                        (DateUtil.getDaysUntil(this.data.nextBillingDate) <= 30
                          ? (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                            (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')))
                          : $r('app.color.text_primary')))
                  }
                  .width('100%')

                } else {
                  // 原有订阅详情
                  // 下次扣费
                  if (this.data.billingCycle !== 'Lifetime') {
                    Row() {
                      Text('下次扣费')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(DateUtil.formatDate(this.data.nextBillingDate) || '未设置')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.text_primary')))
                    }
                    .width('100%')

                    // 剩余天数
                    Row() {
                      Text('剩余天数')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(`${DateUtil.getDaysUntil(this.data.nextBillingDate)} 天`)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 3
                          ? (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                            (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')))
                          : $r('app.color.text_primary'))
                    }
                    .width('100%')

                    // 续费方式
                    Row() {
                      Text('续费方式')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.isAutoRenewal !== false ? '自动续费' : '手动续费')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.text_primary')))
                    }
                    .width('100%')
                  } else {
                    Row() {
                      Text('状态')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.billingCycle === 'Lifetime' ? '永久会员' : '不定周期')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                          (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                    }
                    .width('100%')
                  }

                  // 分类 / 子分类
                  if (this.data.subCategory) {
                    Row() {
                      Text('会员等级')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(this.data.subCategory)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                  }
                }

                // 支付方式
                if (this.data.paymentMethod) {
                  Row() {
                    Text('支付方式')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Blank()
                    Text(this.data.paymentMethod)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                        (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.text_primary')))
                  }
                  .width('100%')
                }
              }
              .width('100%')

              // Action Buttons
              Divider().opacity(0.1).margin({ top: 20, bottom: 20 })

              Row({ space: 12 }) {
                if (this.data.recordType === 'groupBuy' && this.data.usageStatus === 'unused') {
                  Button() {
                    Row() {
                      Text('已使用')
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.White)
                    }
                  }
                  .type(ButtonType.Capsule)
                  .backgroundColor('#4CAF50') // Green for positive action
                  .layoutWeight(1)
                  .height(48)
                  .visualEffect(new hdsEffect.HdsEffectBuilder()
                    .pointLight({
                      sourceType: this.isMarkUsedPressed ? hdsEffect.PointLightSourceType.BRIGHT :
                        hdsEffect.PointLightSourceType.NONE,
                      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                    })
                    .buildEffect())
                  .scale({ x: this.isMarkUsedPressed ? 0.95 : 1, y: this.isMarkUsedPressed ? 0.95 : 1 })
                  .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) this.isMarkUsedPressed = true; else if (event.type ===
                    TouchType.Up || event.type === TouchType.Cancel) this.isMarkUsedPressed = false;
                  })
                  .onClick(async () => {
                    // Mark as used
                    const repo = SubscriptionRepository.getInstance();
                    if (this.data.id) {
                      // Clone and update
                      const updatedSub = JSON.parse(JSON.stringify(this.data)) as SubscriptionModel;
                      updatedSub.usageStatus = 'used';
                      updatedSub.realUsageTime = new Date().getTime();
                      await repo.update(updatedSub);

                      // Update local data to reflect change immediately (though repo update might trigger refresh)
                      // Update global data for immediate UI reflection in overlay
                      this.data = updatedSub;
                      AppStorage.setOrCreate('detailSubscriptionData', updatedSub);

                      // Notify other views to refresh
                      GlobalBus.publish(EVENT_DATA_CHANGED);

                      // Cancel Reminder
                      if (this.data.id) {
                        await LocalNotificationManager.getInstance().cancelReminder(this.data.id);
                      }

                      // Optionally close overlay or just show success
                      promptAction.showToast({ message: '已标记为使用，且已取消过期提醒' });

                      // Auto close overlay after short delay
                      setTimeout(() => {
                        AppStorage.setOrCreate('isDetailClosing', true);
                        animateTo({
                          duration: this.isAnimationEnabled ? 300 : 0,
                          curve: this.isAnimationEnabled ? Curve.FastOutSlowIn : Curve.Linear
                        }, () => {
                          this.isDetailVisible = false;
                        });
                        setTimeout(() => {
                          AppStorage.setOrCreate('isDetailClosing', false);
                        }, this.isAnimationEnabled ? 350 : 50);
                      }, 500);
                    }
                  })
                }

                // Edit Button
                Button() {
                  Row() {
                    Text('编辑')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isNewYearTheme ? '#FFD700' :
                        (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                  }
                }
                .type(ButtonType.Capsule)
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
                .layoutWeight(1)
                .height(48)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.editLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isEditPressed ? 0.95 : 1, y: this.isEditPressed ? 0.95 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isEditPressed = true;
                      this.editLight = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isEditPressed = false;
                    this.editLight = hdsEffect.PointLightSourceType.NONE;
                  }
                })
                .onClick((event: ClickEvent) => {
                  // Close detail overlay and navigate to edit page
                  AppStorage.setOrCreate('isDetailClosing', true);
                  animateTo({
                    duration: this.isAnimationEnabled ? this.animationDuration : 0,
                    curve: this.isAnimationEnabled ? Curve.FastOutSlowIn : Curve.Linear
                  }, () => {
                    this.isDetailVisible = false;
                  })
                  setTimeout(() => {
                    AppStorage.setOrCreate('isDetailClosing', false);
                    // Navigate to edit page
                    const pageStack = AppStorage.get<NavPathStack>('pageStack') as NavPathStack;
                    if (pageStack) {
                      pageStack.pushPathByName('EditSubscription', this.data);
                    }
                  }, this.isAnimationEnabled ? this.animationDuration + 50 : 50);
                })

                // Delete Button
                Button() {
                  Row() {
                    Text('删除')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.Red)
                  }
                }
                .type(ButtonType.Capsule)
                .backgroundColor($r('app.color.card_bg_enhanced'))
                .layoutWeight(1)
                .height(48)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.deleteLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isDeletePressed ? 0.95 : 1, y: this.isDeletePressed ? 0.95 : 1 })
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
                  // Show delete confirmation
                  AlertDialog.show({
                    title: '确认删除',
                    message: `确定要删除订阅"${this.data.name}"吗？`,
                    autoCancel: true,
                    alignment: DialogAlignment.Center,
                    primaryButton: {
                      value: '取消',
                      action: () => {
                      }
                    },
                    secondaryButton: {
                      value: '删除',
                      fontColor: Color.Red,
                      action: () => {
                        // Close detail overlay
                        AppStorage.setOrCreate('isDetailClosing', true);
                        animateTo({
                          duration: this.isAnimationEnabled ? this.animationDuration : 0,
                          curve: this.isAnimationEnabled ? Curve.FastOutSlowIn : Curve.Linear
                        }, () => {
                          this.isDetailVisible = false;
                        });
                        setTimeout(() => {
                          AppStorage.setOrCreate('isDetailClosing', false);
                        }, this.isAnimationEnabled ? this.animationDuration + 50 : 50);

                        // Delete subscription
                        if (this.data.id) {
                          SubscriptionRepository.getInstance().delete(this.data.id);
                        }
                      }
                    }
                  });
                })
              }
              .width('100%')
              .opacity(this.isDataStable ? 1 : 0) // 数据稳定后再显示核心内容
              .animation({ duration: 300, curve: Curve.EaseInOut })
            }
            .width('100%')
          }
        }
        .width('85%')
        .padding(24)
        .linearGradient(this.isNewYearTheme ? {
          angle: 135,
          colors: [[$r('app.color.sub_card_ny_start'), 0.0], [$r('app.color.sub_card_ny_end'), 1.0]]
        } : (this.showVipTheme ? {
          angle: 135,
          colors: [[$r('app.color.sub_card_vip_start'), 0.0], [$r('app.color.sub_card_vip_end'), 1.0]]
        } : {
          angle: 0,
          colors: [['rgba(0,0,0,0)', 0.0], ['rgba(0,0,0,0)', 1.0]]
        }))
        .backgroundColor(this.isNewYearTheme || (this.showVipTheme) ? Color.Transparent :
          $r('app.color.card_bg_enhanced'))
        .borderRadius(32)
        .shadow({ radius: 40, color: 'rgba(0,0,0,0.2)', offsetY: 10 })
        .clip(true)
        // 这里的 ID 必须与 SubscriptionCard 中的一致
        .geometryTransition('card_expand_' + (this.data.uuid || ''))
        .transition(TransitionEffect.OPACITY.animation({
          duration: this.isAnimationEnabled ? this.animationDuration : 0,
          curve: this.isAnimationEnabled ? Curve.FastOutSlowIn : Curve.Linear
        }))
        .onClick(() => {
          AppStorage.setOrCreate('isDetailClosing', true);
          animateTo({
            duration: this.isAnimationEnabled ? this.animationDuration : 0,
            curve: this.isAnimationEnabled ? Curve.EaseOut : Curve.Linear
          }, () => {
            this.isDetailVisible = false;
          })
          setTimeout(() => {
            AppStorage.setOrCreate('isDetailClosing', false);
          }, this.isAnimationEnabled ? this.animationDuration + 50 : 50);
        })
      }
    }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
      .zIndex(999) // 确保在最上层
    }
  }
