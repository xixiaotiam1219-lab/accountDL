import { MonthlyReportSheet } from './MonthlyReportSheet';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { BackgroundWatermark } from './BackgroundWatermark';
import { HdsNavDestination } from '@kit.UIDesignKit';

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

  aboutToAppear() {
    const params = this.pageStack.getParamByName('MonthlyReport') as Array<SubscriptionModel[]>;
    if (params && params.length > 0) {
      this.subscriptions = params[params.length - 1];
    }
  }

  build() {
    HdsNavDestination() {
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
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: '月度报告'
        }
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }
}
