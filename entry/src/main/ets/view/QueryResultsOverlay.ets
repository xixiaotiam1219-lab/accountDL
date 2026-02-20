import { SubscriptionModel } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';
import { SubscriptionIcon } from './SubscriptionIcon';
import { hdsEffect } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';

@Component
export struct QueryResultsOverlay {
  @StorageLink('isQueryResultsVisible') isVisible: boolean = false;
  @StorageLink('queryResultData') resultData: Record<string, Object> = {};
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  
  @State isClosePressed: boolean = false;
  @State closeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Shader Controller for Dual Edge Flow Light
  @State shaderController: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  @Builder
  RecordItem(item: SubscriptionModel) {
    // ... existing RecordItem implementation ...
    Row() {
      // 左侧：图标 + 名称 + 日期
      Row() {
        SubscriptionIcon({
          icon: item.recordType === 'groupBuy' ?
            (item.platform === 'meituan' ? 'resource:meituan_logo' :
              (item.platform === 'douyin' ? 'resource:douyin_logo' : 'resource:dianping_logo')) :
            item.icon,
          name: item.recordType === 'groupBuy' ? (item.merchantName || item.name) : item.name,
          iconSize: 46, // 稍微加大图标
          iconRadius: 12,
          showGroupBadge: item.recordType === 'groupBuy'
        })
          .margin({ right: 14 })
          .shadow({ radius: 4, color: 'rgba(0,0,0,0.1)', offsetY: 2 }) // 图标增加轻微阴影

        Column() {
          // 订阅名称
          Text(item.name)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 辅助信息：周期 + 日期
          Row() {
             if (item.recordType === 'warranty') {
                 if (item.nextBillingDate < new Date().getTime()) {
                     Text('已过期 ' + DateUtil.formatDate(item.nextBillingDate))
                       .fontSize(12)
                       .fontColor('#E64340') // Red for expired
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

      // 右侧：显眼的价格 或 保修状态
      Column() {
        if (item.recordType === 'warranty') {
           // 保修状态显示
           if (item.nextBillingDate < new Date().getTime()) {
               Text('已过保')
                 .fontSize(14)
                 .fontColor($r('app.color.text_secondary'))
                 .fontWeight(FontWeight.Medium)
                 .opacity(0.6)
           } else {
               Text('保修中')
                 .fontSize(14)
                 .fontColor($r('app.color.success_color')) // 绿色
                 .fontWeight(FontWeight.Medium)
           }
        } else {
            // 普通订阅显示价格
            Text() {
              Span(item.currency === 'USD' ? '$' : '¥')
                .fontSize(14)
                .fontColor('#E64340')
                .fontWeight(FontWeight.Medium)
              Span(item.price.toFixed(2))
                .fontSize(20) // 加大数字
                .fontColor('#E64340')
                .fontWeight(FontWeight.Bold)
            }
        }
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 4, right: 4 }) // 增加内边距
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 0.5 }, color: '#1A000000' }) 
  }

  build() {
    Stack() {
      // 1. 遮罩层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000') // 更深的遮罩
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
          curve: curves.springMotion(0.6, 0.8) // Smooth spring for backdrop
        }))

      // 2. 结果展示卡片
      Stack() {
        Column() {
          // --- 标题栏 ---
          Row() {
            Text('查询结果')
              .fontSize(22) // 更大的标题
              .fontWeight(FontWeight.Bold) // 更粗的字体
              .fontColor($r('app.color.text_primary'))
            
            Blank()
            
            // 关闭图标
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(32)
            .height(32)
            .backgroundColor($r('app.color.tag_bg')) // 自适应背景色
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
          .padding({ bottom: 20 })
          .alignItems(VerticalAlign.Center)

          // --- 摘要胶囊 ---
          if (this.resultData['resultText']) {
            Row() {
               // 装饰图标 - 使用系统 AI 图标
               SymbolGlyph($r('sys.symbol.AI'))
                  .fontSize(24)
                  .fontColor(['#FF9F0A']) // 橙色/金色
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
            .backgroundColor($r('app.color.card_bg_enhanced')) // 使用应用内定义的卡片背景色
            .borderRadius(12)
            .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetY: 2 }) // 轻微浮起
            .margin({ bottom: 20 })
          }

          // --- 列表区域 ---
          if (this.resultData['records']) {
            List() {
              ForEach(JSON.parse(this.resultData['records'] as string), (item: SubscriptionModel, index: number) => {
                ListItem() {
                  this.RecordItem(item)
                }
                .transition(
                  TransitionEffect.asymmetric(
                    TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 }))
                      .animation({ curve: curves.springMotion(0.5, 0.8), delay: index * 50 }), // Staggered entry
                    TransitionEffect.OPACITY.animation({ duration: 200 }) // Simple fade out
                  )
                )
              })
            }
            .width('100%')
            .layoutWeight(1) 
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .divider({ strokeWidth: 0 }) 
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

          // --- 底部按钮 ---
          Button('知道了')
            .width('100%')
            .height(46)
            .type(ButtonType.Capsule) 
            .backgroundColor($r('app.color.brand_color'))
            .fontColor(Color.White)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20 })
            .shadow({ radius: 8, color: 'rgba(0,0,0,0.2)', offsetY: 4 }) 
            .onClick(() => {
              animateTo({
                duration: this.isAnimationEnabled ? this.animationDuration : 0,
                curve: Curve.EaseOut
              }, () => {
                this.isVisible = false;
              })
            })
        }
        .width('90%') 
        .height('70%')
        .padding(24)
        .backgroundColor($r('app.color.page_background')) 
        .backgroundBlurStyle(BlurStyle.Thick) 
        .borderRadius(24)
        .clip(true) // 必须裁剪才能显示边缘流光
        .visualEffect(new hdsEffect.HdsEffectBuilder()
            .shaderEffect({
              effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
              animation: {
                duration: 4000,
                iterations: -1,
                autoPlay: true,
                onFinish: () => {
                  console.info('Succeeded in finishing');
                }
              },
              controller: this.shaderController,
              params: {
                firstEdgeFlowLight: {
                  startPos: 0,
                  endPos: 1.0,
                  color: '#1AD0F1', // 科技蓝
                },
                secondEdgeFlowLight: {
                  startPos: 0.5,
                  endPos: 1.5,
                  color: '#FFA4E5', // 活力粉
                }
              }
            })
            .buildEffect()
        )
        .shadow({ radius: 50, color: 'rgba(0,0,0,0.25)', offsetY: 20 }) // 深圆角阴影
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
            .combine(TransitionEffect.translate({ y: 40 }))
            .animation({ curve: curves.springMotion(0.4, 0.6) }), // Natural spring entry
          TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }))
            .animation({ duration: 250, curve: Curve.EaseIn }) // Soft exit
        ))
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
      .zIndex(1000)
    }
  }
}
