import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hdsEffect, hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { curves, LengthMetrics } from '@kit.ArkUI';
import { FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { SubscriptionCard } from './SubscriptionCard';

@Component
export struct QueryResultsOverlay {
  @StorageLink('isQueryResultsVisible') isVisible: boolean = false;
  @StorageLink('queryResultData') resultData: Record<string, Object> = {};
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  
  // Agent Props
  private controller: FunctionController = new FunctionController();
  // TODO: Replace with real Agent ID from platform
  private agentId: string = 'agent0244e963799347bdb18995e6416726ea';
  @State dualEdgeLightController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();
  
  // HdsNavigation requirements
  private navStack: NavPathStack = new NavPathStack();
  @State resultTitle: string = '查询结果';

  @State isClosePressed: boolean = false;
  @State closeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Shader Controller for Dual Edge Flow Light
  @State shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  @State isAskPressed: boolean = false;
  @State isOkPressed: boolean = false;
  @State askLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State okLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @Builder
  RecordItem(item: SubscriptionModel) {
    Row() {
      // 左侧：图标 + 名称 + 日期
      Row() {
        SubscriptionIcon({
          icon: item.recordType === 'groupBuy' ?
            (item.platform === 'meituan' ? 'resource:meituan_logo' :
              (item.platform === 'douyin' ? 'resource:douyin_logo' :
                (item.platform === 'dianping' ? 'resource:dianping_logo' : item.icon))) :
            item.icon,
          name: item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name,
          iconSize: 46,
          iconRadius: 12,
          showGroupBadge: item.recordType === 'groupBuy'
        })
          .margin({ right: 14 })

        Column() {
          Text(item.name)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
             if (item.recordType === 'warranty') {
                 if (item.nextBillingDate < new Date().getTime()) {
                     Text('已过期 ' + DateUtil.formatDate(item.nextBillingDate))
                       .fontSize(12)
                       .fontColor('#E64340')
                 } else {
                     Text('保修至 ' + DateUtil.formatDate(item.nextBillingDate))
                       .fontSize(12)
                       .fontColor($r('app.color.text_secondary'))
                 }
             } else {
                 Text(DateUtil.formatDate(item.nextBillingDate))
                   .fontSize(12)
                   .fontColor($r('app.color.text_secondary'))
             }
          }
          .opacity(0.8)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)

      Column() {
        if (item.recordType === 'warranty') {
           if (item.nextBillingDate < new Date().getTime()) {
               Text('已过保')
                 .fontSize(14)
                 .fontColor($r('app.color.text_secondary'))
                 .fontWeight(FontWeight.Medium)
                 .opacity(0.6)
           } else {
               Text('保修中')
                 .fontSize(14)
                 .fontColor($r('app.color.success_color'))
                 .fontWeight(FontWeight.Medium)
           }
        } else {
            Text() {
              Span(item.currency === 'USD' ? '$' : '¥')
                .fontSize(14)
                .fontColor('#E64340')
                .fontWeight(FontWeight.Medium)
              Span(item.price.toFixed(2))
                .fontSize(20)
                .fontColor('#E64340')
                .fontWeight(FontWeight.Bold)
            }
        }
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 0.5 }, color: '#1A000000' }) 
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder QueryBuilder(){
    Column() {
      // --- 摘要胶囊 ---
      if (this.resultData['resultText']) {
        Row() {
          SymbolGlyph($r('sys.symbol.AI'))
            .fontSize(24)
            .fontColor(['#FF9F0A'])
            .margin({ right: 12 })
            .alignSelf(ItemAlign.Start)
            .margin({ top: 2 })

          Text(this.resultData['resultText'] as string)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(24)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_bg_enhanced'))
        .borderRadius(12)
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
        .margin({ bottom: 20 })
      }

      // --- 列表区域 ---
      if (this.resultData['records']) {
        List() {
          ForEach(JSON.parse(this.resultData['records'] as string),
            (item: SubscriptionModel, index: number) => {
              ListItem() {
                this.RecordItem(item)
              }
              .transition(
                TransitionEffect.asymmetric(
                  TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 }))
                    .animation({ curve: curves.springMotion(0.5, 0.8), delay: index * 50 }),
                  TransitionEffect.OPACITY.animation({ duration: 200 })
                )
              )
            })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(56)
            .fontColor([$r('app.color.text_secondary')])
            .opacity(0.15)
            .margin({ bottom: 16 })
          Text('没找到相关记录')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }

      // --- 操作区域 ---
      Row({ space: 12 }) {
        Stack() {
          FunctionComponent({
            agentId: this.agentId,
            onError: (err: BusinessError) => {
              console.error(`Agent err: ${JSON.stringify(err)}`)
            },
            options: {
              title: '继续提问',
              queryText: '',
              backgroundColor: Color.Transparent
            },
            controller: this.controller
          })
        }
        .layoutWeight(1)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .clip(true)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .shaderEffect({
            effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
            animation: {
              duration: 4000,
              iterations: -1,
              autoPlay: true
            },
            controller: this.dualEdgeLightController,
            params: {
              firstEdgeFlowLight: { startPos: 0, endPos: 1.0, color: '#1AD0F1' },
              secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: '#FFA4E5' }
            }
          })
          .pointLight({
            sourceType: this.askLight,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .scale({ x: this.isAskPressed ? 0.95 : 1, y: this.isAskPressed ? 0.95 : 1 })
        .animation({
          duration: this.isAnimationEnabled ? 150 : 0,
          curve: curves.springMotion(0.4, 0.6)
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            if (this.isAnimationEnabled) {
              this.isAskPressed = true;
              if (this.isPointLightEnabled) {
                this.askLight = hdsEffect.PointLightSourceType.BRIGHT;
              }
            }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isAskPressed = false;
            this.askLight = hdsEffect.PointLightSourceType.NONE;
          }
        })

        Button('知道了')
          .height(44)
          .type(ButtonType.Capsule)
          .stateEffect(false) // 禁用默认反馈
          .linearGradient(
            this.isNewYearTheme ? {
              direction: GradientDirection.Right,
              colors: [['#FF4D4F', 0.0], ['#FF7875', 1.0]]
            } : (this.showVipTheme ? {
              direction: GradientDirection.Right,
              colors: [[$r('app.color.vip_gold'), 0.0], ['#FFD700', 1.0]]
            } : {
              direction: GradientDirection.Right,
              colors: [[$r('app.color.brand_color'), 0.0], ['#60A5FA', 1.0]]
            })
          )
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.2)', offsetY: 4 })
          .layoutWeight(1)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.okLight,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .scale({ x: this.isOkPressed ? 0.95 : 1, y: this.isOkPressed ? 0.95 : 1 })
          .animation({
            duration: this.isAnimationEnabled ? 150 : 0,
            curve: curves.springMotion(0.4, 0.6)
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              if (this.isAnimationEnabled) {
                this.isOkPressed = true;
                if (this.isPointLightEnabled) {
                  this.okLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              }
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isOkPressed = false;
              this.okLight = hdsEffect.PointLightSourceType.NONE;
            }
          })
          .onClick(() => {
            animateTo({
              duration: this.isAnimationEnabled ? this.animationDuration : 0,
              curve: Curve.EaseOut
            }, () => {
              this.isVisible = false;
            })
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 20,
      right: 20,
      bottom: 24,
      top: 64
    })
  }
  build() {
    Stack() {
      if (this.isVisible) {
        // 1. 遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .backgroundBlurStyle(BlurStyle.Regular)
          .onClick(() => {
            animateTo({
              duration: this.isAnimationEnabled ? this.animationDuration : 0,
              curve: Curve.EaseOut
            }, () => {
              this.isVisible = false;
            })
          })
          .transition(TransitionEffect.OPACITY.animation({
            curve: curves.springMotion(0.6, 0.8)
          }))

        // 2. 结果展示卡片 (使用 HdsNavigation 重构)
        Column() {

            HdsNavigation(this.navStack) {
                this.QueryBuilder()
            }
            .backgroundColor(Color.Transparent)
            .titleBar({
              content: {
                title: { mainTitle: this.resultTitle },
                menu: {
                  value: [
                    {
                      content: {
                        icon: $r('sys.symbol.xmark'),
                        action: () => {
                          this.isVisible = false;
                        }
                      }
                    }
                  ]
                }
              },
              style:(deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
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
            .titleMode(HdsNavigationTitleMode.MODAL)
            .mode(NavigationMode.Stack)
            .hideBackButton(true)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius({ topLeft: 24, topRight: 24 })
            .width('100%')
            .height('100%')
        }
        .width('90%')
        .height('75%')
        .clip(true)
        .borderRadius(28)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
            .shaderEffect({
              effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
              animation: { duration: 4000, iterations: -1, autoPlay: true },
              controller: this.shaderController,
              params: {
                firstEdgeFlowLight: { startPos: 0, endPos: 1.0, color: '#1AD0F1' },
                secondEdgeFlowLight: { startPos: 0.5, endPos: 1.5, color: '#FFA4E5' }
              }
            })
            .buildEffect()
        )
        .shadow({ radius: 50, color: 'rgba(0,0,0,0.25)', offsetY: 20 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
            .combine(TransitionEffect.translate({ y: 40 }))
            .animation({ curve: curves.springMotion(0.4, 0.6) }),
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
            .combine(TransitionEffect.translate({ y: 20 }))
            .animation({ duration: 300, curve: Curve.FastOutSlowIn })
        ))
      }
    }
    .width('100%')
    .height('100%')
  }
}
