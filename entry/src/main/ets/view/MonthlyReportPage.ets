import { MonthlyReportSheet } from './MonthlyReportSheet';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { BackgroundWatermark } from './BackgroundWatermark';
import { hdsMaterial, HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Builder
export function MonthlyReportPageBuilder() {
  MonthlyReportPage()
}

@Component
struct MonthlyReportPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  @State subscriptions: SubscriptionModel[] = [];
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  aboutToAppear() {
    const params = this.pageStack.getParamByName('MonthlyReport') as Array<SubscriptionModel[]>;
    if (params && params.length > 0) {
      this.subscriptions = params[params.length - 1];
    }
  }
@Builder MonthlyReportBuilder(){
  Stack({ alignContent: Alignment.Top }) {
    // Universal Background Watermark
    BackgroundWatermark()
      .zIndex(0)

    Column() {
      MonthlyReportSheet({
        subscriptions: this.subscriptions,
        showCloseButton: false, // Title bar handles navigation
        onClose: () => {
          this.pageStack.pop();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight) })
  }
}
  build() {

      HdsNavDestination() {
        this.MonthlyReportBuilder()
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: '月度报告'
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
      .backgroundColor($r('app.color.page_background'))
  }
}
