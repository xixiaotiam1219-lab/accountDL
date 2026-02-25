import { appInfoManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { curves, promptAction } from '@kit.ArkUI';

const TAG = 'DynamicIconSheet';
const DOMAIN = 0x0000;

@Component
export struct DynamicIconSheet {
  @State dynamicIcons: appInfoManager.DynamicIconInfo[] = [];
  @State isLoading: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;

  aboutToAppear() {
    this.queryIcons();
  }

  // 查询动态图标信息
  private async queryIcons() {
    this.isLoading = true;
    try {
      const queryResult = await appInfoManager.queryDynamicIcons();
      hilog.info(DOMAIN, TAG, "Succeeded in getting DynamicIconInfo size = " + queryResult.length);
      this.dynamicIcons = queryResult;
    } catch (error) {
      const err = error as BusinessError;
      if (err.code === 1006800010) {
        // 特殊处理：1006800010 表示没有动态图标数据，不视为报错
        hilog.info(DOMAIN, TAG, "No dynamic icon data configured.");
        this.dynamicIcons = [];
      } else {
        hilog.error(DOMAIN, TAG, "queryDynamicIcons failed, code: " + err.code + ", message: " + err.message);
        promptAction.showToast({ message: '加载图标失败' });
      }
    } finally {
      this.isLoading = false;
    }
  }

  // 切换动态图标
  private async selectIcon(iconId: string) {
    try {
      await appInfoManager.selectDynamicIcon(iconId);
      hilog.info(DOMAIN, TAG, "Succeeded in selecting dynamic icon: " + iconId);
      promptAction.showToast({ message: '图标切换成功' });
      // 重新查询以更新选中状态
      this.queryIcons();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, "selectDynamicIcon failed, code: " + err.code + ", message: " + err.message);
      if (err.code === 1006800013) {
         promptAction.showToast({ message: '图标已在切换中，请稍后' });
      } else {
         promptAction.showToast({ message: '切换失败: ' + err.message });
      }
    }
  }

  // 恢复默认图标
  private async disableIcon() {
    try {
      await appInfoManager.disableDynamicIcon();
      hilog.info(DOMAIN, TAG, "Succeeded in disabling dynamic icon");
      promptAction.showToast({ message: '已恢复默认图标' });
      this.queryIcons();
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, "disableDynamicIcon failed, code: " + err.code + ", message: " + err.message);
      promptAction.showToast({ message: '恢复失败: ' + err.message });
    }
  }

  @Builder
  CheckmarkBuilder() {
    SymbolGlyph($r('sys.symbol.checkmark'))
      .fontSize(14)
      .fontColor([Color.White])
  }

  @Builder
  IconItem(icon: appInfoManager.DynamicIconInfo) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(icon.iconUrl)
          .width(80)
          .height(80)
          .borderRadius(18)
          .shadow({ radius: 10, color: '#1A000000', offsetY: 4 })
          .onClick(() => {
            if (!icon.enabled) {
              this.selectIcon(icon.iconId);
            }
          })

        if (icon.enabled) {
          Circle({ width: 24, height: 24 })
            .fill(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
            .margin({ top: -8, right: -8 })
            .overlay(this.CheckmarkBuilder(), { align: Alignment.Center })
        }
      }
      .width(80)
      .height(80)

      Text(icon.iconId) // 如果接口没有提供名称，暂时显示 ID
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(10)
  }

  build() {
    Column() {
      // 顶部条
      Row()
        .width(40)
        .height(4)
        .backgroundColor($r('app.color.text_secondary'))
        .opacity(0.2)
        .borderRadius(2)
        .margin({ top: 8, bottom: 16 })

      Text("切换应用图标")
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 24 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          Text("加载图标中...")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.dynamicIcons.length === 0) {
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
            .fontSize(64)
            .fontColor([$r('app.color.text_tertiary')])
          Text("暂无可切换的动态图标")
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
          
          Button("恢复默认图标")
            .onClick(() => this.disableIcon())
            .margin({ top: 20 })
            .backgroundColor($r('app.color.divider_color'))
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.dynamicIcons, (icon: appInfoManager.DynamicIconInfo) => {
                GridItem() {
                  this.IconItem(icon)
                }
              }, (icon: appInfoManager.DynamicIconInfo) => icon.iconId)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(16)
            .rowsGap(16)
            .width('100%')
            .padding({ bottom: 24 })

            Button("恢复默认图标")
              .width('100%')
              .height(50)
              .borderRadius(12)
              .backgroundColor($r('app.color.divider_color'))
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
              .onClick(() => this.disableIcon())
              .margin({ top: 20, bottom: 20 })
          }
        }
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('60%') // 占据屏幕 60% 高度
    .padding({ left: 24, right: 24, bottom: 32 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}
