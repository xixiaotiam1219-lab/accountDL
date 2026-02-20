import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { resolveIcon } from '../utils/MemberServiceConfig';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hdsEffect } from '@kit.UIDesignKit';
import { vibrator } from '@kit.SensorServiceKit';
import { curves } from '@kit.ArkUI';

@Component
export struct SubscriptionCard {
  @Prop data: SubscriptionModel;
  @Prop index: number = 0; // 用于级联动画延迟

  // 按压状态 - 用于点光源发光
  @State lightSourceType: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  // 按压缩放动画
  @State isPressed: boolean = false;

  // 统一动画系统
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  // 全局详情页状态
  @StorageLink('isDetailVisible') isDetailVisible: boolean = false;
  @StorageLink('detailSubscriptionData') @Watch('onDetailDataChange') detailData: SubscriptionModel | undefined = undefined;

  onDetailDataChange() {
    if (this.detailData && this.data && this.detailData.uuid === this.data.uuid) {
      // 当详情页数据变化时（例如标记为已使用），立即同步到列表卡片
      // 解决列表刷新延迟导致的 UI 状态不一致问题
      this.data = this.detailData;
    }
  }

  // Theme States
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;

  getBillingCycleShortText(): string {
    if (this.data.recordType === 'groupBuy') {
      return '团购';
    }
    if (this.data.recordType === 'warranty') {
      const days = DateUtil.getDaysUntil(this.data.nextBillingDate);
      return days < 0 ? '过保' : '在保';
    }
    switch (this.data.billingCycle) {
      case 'Monthly': return '月付';
      case 'Quarterly': return '季付';
      case 'Yearly': return '年付';
      case 'Lifetime': return '永久';
      case 'Indefinite': return '不定';
      default: return '';
    }
  }

  getUsageStatusColor(): ResourceColor {
    if (this.data.usageStatus === 'used') return '#9E9E9E'; // 已使用 - 灰色
    if (this.data.usageStatus === 'expired') return '#F44336'; // 已过期 - 红色

    // 未使用状态，根据剩余天数提醒
    const days = DateUtil.getDaysUntil(this.data.nextBillingDate);
    if (days <= 0) return '#F44336'; // 今日到期或已过期
    if (days <= 3) return this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')); // 即将到期 - 警告色/主题色
    return $r('app.color.text_secondary'); // 充足 - 默认灰色 (Unified with Subscription)
  }

  getGroupBuyIcon(): string {
    if (this.data.platform === 'meituan') return 'resource:meituan_logo';
    if (this.data.platform === 'douyin') return 'resource:douyin_logo';
    if (this.data.platform === 'dianping') return 'resource:dianping_logo';
    return this.data.icon ?? '';
  }

  @Builder LanternDecoration() {
    Text('🏮')
      .fontSize(60)
      .opacity(0.12)
      .rotate({ angle: -15 })
      .position({ right: -10, bottom: -10 })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    // 判断当前卡片是否正在展示详情
    // 只有当详情页可见，且显示的卡片UUID与当前卡片一致时，才隐藏当前卡片
    // 这样能确保 geometryTransition 的“一进一出”
    Stack() {
      // 占位符，保持列表布局高度，防止塌陷
      Row()
        .width('100%')
        .height(80) // 基础高度
        .visibility(Visibility.Hidden)

      if (!(this.isDetailVisible && this.detailData?.uuid === this.data.uuid)) {
        Stack() {
          // Background Decoration
          if (this.isNewYearTheme) {
            this.LanternDecoration()
          }

          // Content Row
          Row() {
            // 1. 图标部分
            SubscriptionIcon({
              icon: this.data.recordType === 'groupBuy' ? this.getGroupBuyIcon() : this.data.icon,
              name: this.data.recordType === 'groupBuy' ?
                (this.data.merchantName || this.data.name) :
                this.data.name,
              iconSize: 52,
              iconRadius: 14,
              showGroupBadge: this.data.recordType === 'groupBuy',
              showWarrantyBadge: this.data.recordType === 'warranty'
            })
              .margin({ right: 14 })
              .flexShrink(0)

            // 2. 中间信息区
            Column() {
              Text(this.data.recordType === 'groupBuy' ? (this.data.merchantName || this.data.name) : this.data.name)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_title') : (this.showVipTheme ? $r('app.color.sub_card_vip_title') : $r('app.color.text_primary')))
                .margin({ bottom: 6 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text() {
                if (this.data.recordType === 'groupBuy') {
                  Span(this.data.platform === 'meituan' ? '美团' : (this.data.platform === 'dianping' ? '大众点评' : '抖音'))
                  if (this.data.merchantName && this.data.name) {
                    Span(' · ')
                    Span(this.data.name)
                  }
                  if (this.data.quantity && this.data.quantity > 1) {
                    Span(' · ')
                    Span(`${this.data.quantity}张`)
                  }
                } else if (this.data.recordType === 'warranty') {
                  // 保修类型：显示品牌和购买渠道
                  Span(this.data.brand || '保修期')
                  if (this.data.purchaseChannel) {
                    Span(' · ')
                    Span(this.data.purchaseChannel)
                  }
                } else {
                  Span(this.getBillingCycleShortText())

                  if (this.data.subCategory) {
                    Span(' · ')
                    Span(this.data.subCategory)
                  }

                  if (this.data.category && this.data.category !== '其他') {
                    Span(' · ')
                    Span(this.data.category)
                  }
                }
              }
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.MARQUEE })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ right: 8 })

            // 3. 右侧价格与状态区
            Column() {
              Row() {
                Text(this.data.currency === 'USD' ? '$' : '¥')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ right: 2, top: 2 })
                Text(`${(this.data.price || 0).toFixed(2)}`)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.text_primary')))
              }
              .alignItems(VerticalAlign.Bottom)
              .margin({ bottom: 4 })

              if (this.data.recordType !== 'groupBuy' && this.data.recordType !== 'warranty' && (this.data.billingCycle === 'Yearly' || this.data.billingCycle === 'Quarterly')) {
                Text(`≈ ¥${(this.data.billingCycle === 'Yearly' ? (this.data.price || 0) / 12 : (this.data.price || 0) / 3).toFixed(2)}/月`)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .opacity(0.8)
                  .margin({ bottom: 4 })
              }

              if (this.data.recordType === 'groupBuy' || this.data.recordType === 'warranty' || this.data.billingCycle !== 'Lifetime') {
                Row() {
                  if (this.data.recordType === 'groupBuy') {
                    // 团购券状态显示
                    Text(this.data.usageStatus === 'used' ? '已使用' : this.data.usageStatus === 'expired' ? '已过期' :
                      (DateUtil.getDaysUntil(this.data.nextBillingDate) === 0 ? '今日到期' : `剩 ${DateUtil.getDaysUntil(this.data.nextBillingDate)} 天`))
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.getUsageStatusColor())
                  } else if (this.data.recordType === 'warranty') {
                    // 保修到期状态显示
                    Text(DateUtil.getDaysUntil(this.data.nextBillingDate) < 0 ? '过保' :
                      `在保 (剩 ${DateUtil.getDaysUntil(this.data.nextBillingDate) + 1} 天)`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) < 0 ? '#F44336' :
                        (DateUtil.getDaysUntil(this.data.nextBillingDate) < 30 ?
                          (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') :
                            (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color'))) :
                          $r('app.color.text_secondary')))
                  } else {
                    if (this.data.isAutoRenewal !== false) {
                      SymbolGlyph($r('sys.symbol.repeat'))
                        .fontSize(10)
                        .fontColor(this.isNewYearTheme ? [$r('app.color.sub_card_ny_text')] : (this.showVipTheme ? [$r('app.color.sub_card_vip_text')] : [$r('app.color.brand_color')]))
                        .margin({ right: 4 })
                    }

                    Text(`${this.data.isAutoRenewal !== false ? '自动 · ' : ''}${DateUtil.getDaysUntil(this.data.nextBillingDate) === 0 ? '今日到期' : `剩 ${DateUtil.getDaysUntil(this.data.nextBillingDate)} 天`}`)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DateUtil.getDaysUntil(this.data.nextBillingDate) <= 3
                        ? (this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.warning_color')))
                        : $r('app.color.text_secondary'))
                  }
                }
                .opacity(this.data.recordType === 'groupBuy' || this.data.recordType === 'warranty' || DateUtil.getDaysUntil(this.data.nextBillingDate) <= 3 ? 1 : 0.8)
              }
            }
            .alignItems(HorizontalAlign.End)
            .flexShrink(0)

            // 4. 结尾箭头
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(14)
              .fontColor([$r('app.color.text_secondary')])
              .opacity(0.3)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        }
        .width('100%')
        .clip(true)
        .linearGradient(this.isNewYearTheme ? {
          angle: 135,
          colors: [[$r('app.color.sub_card_ny_start'), 0.0], [$r('app.color.sub_card_ny_end'), 1.0]]
        } : (this.showVipTheme ? {
          angle: 135,
          colors: [[$r('app.color.sub_card_vip_start'), 0.0], [$r('app.color.sub_card_vip_end'), 1.0]]
        } : {
          angle: 0,
          colors: [[ 'rgba(0,0,0,0)', 0.0 ], [ 'rgba(0,0,0,0)', 1.0 ]]
        }))
        .backgroundColor(this.isNewYearTheme || (this.showVipTheme) ? Color.Transparent : $r('app.color.card_bg_enhanced'))
        .borderRadius(24)
        .shadow({
          radius: 15,
          color: this.isNewYearTheme ? '#1AFF0000' : (this.showVipTheme ? '#1AFFE57F' : '#08000000'),
          offsetY: 6
        })
        .border({
          width: this.isNewYearTheme || (this.showVipTheme) ? 1 : 0,
          color: this.isNewYearTheme ? 'rgba(255, 0, 0, 0.1)' : (this.showVipTheme ? 'rgba(212, 175, 55, 0.2)' : Color.Transparent)
        })
        .geometryTransition('card_expand_' + this.data.uuid)
        .scale({ x: this.isPressed ? 0.95 : 1, y: this.isPressed ? 0.95 : 1 })
        .animation({ curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear, duration: this.isAnimationEnabled ? undefined : 0 })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.lightSourceType,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                // 震动反馈
                try {
                  vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
                } catch (e) {
                  // ignore
                }

                // 手动重置按压状态，防止卡片隐藏导致 onTouch Up 无法触发，从而导致按压态残留
                this.isPressed = false;
                this.lightSourceType = hdsEffect.PointLightSourceType.NONE;

                // 设置全局数据，触发 Index 页面的 Overlay 显示
                this.detailData = this.data;
                animateTo({
                  curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear,
                  duration: this.isAnimationEnabled ? undefined : 0
                }, () => {
                  this.isDetailVisible = true;
                })
              })
          )
        )
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            if (this.isAnimationEnabled && this.isPointLightEnabled) {
              this.lightSourceType = hdsEffect.PointLightSourceType.BRIGHT;
              this.isPressed = true;
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.lightSourceType = hdsEffect.PointLightSourceType.NONE;
            this.isPressed = false;
          }
        })
      }
    }
  }
}

