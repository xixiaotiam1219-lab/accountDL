import { WebViewParam } from './WebViewPage';
import { BackgroundWatermark } from './BackgroundWatermark';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct AboutPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  private appVersion: string = 'v1.0.3';
  private agreementUrl: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1861657117321107008';

  // Animation System
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationResponse') animationResponse: number = 0.35;
  @StorageLink('animationDamping') animationDamping: number = 0.75;

  @State animStep1: boolean = false;
  @State animStep2: boolean = false;
  @State animStep3: boolean = false;

  aboutToAppear() {
    this.triggerAnimations();
  }

  triggerAnimations() {
    if (this.isAnimationEnabled) {
      const duration = this.animationDuration;
      const interval = duration * 0.15;
      const curve = curves.springMotion(this.animationResponse, this.animationDamping);
      
      setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep1 = true }) }, 0);
      setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep2 = true }) }, interval);
      setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep3 = true }) }, interval * 2);
    } else {
      this.animStep1 = true;
      this.animStep2 = true;
      this.animStep3 = true;
    }
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        // Universal Background Watermark
        BackgroundWatermark()
          .zIndex(0) // Ensure it's behind content
        // Main Content
        Column() {
          // 应用 Logo 与名称
          Column() {
            Image($r('app.media.startIcon'))
              .width(80)
              .height(80)
              .borderRadius(16)
              .margin({ top: 40, bottom: 16 })
              .shadow({ radius: 10, color: '#10000000', offsetX: 0, offsetY: 4 })
            
            Text("记得订阅")
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            
            Text(`Version ${this.appVersion}`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })

          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .opacity(this.animStep1 ? 1 : 0)
          .translate({ y: this.animStep1 ? 0 : 20 })

          Blank()

          Column() {
            Divider().color($r('app.color.divider_color'))
            
            Row() {
              Text("隐私政策")
                .fontSize(14)
                .fontColor($r('app.color.brand_color'))
                .onClick(() => {
                  this.pageStack.pushPathByName('WebView', new WebViewParam(this.agreementUrl, '隐私政策'));
                })
            }
            .margin({ top: 16, bottom: 20 })

            Row() {
              Text("开源许可")
                .fontSize(14)
                .fontColor($r('app.color.brand_color'))
                .onClick(() => {
                  this.pageStack.pushPathByName('OpenSourceLicense', null);
                })
            }
            .margin({ bottom: 20 })

            Row() {
              Text("闽ICP备2026001305号-2A")
                .fontSize(12)
                .fontColor($r('app.color.brand_color'))
                .onClick(() => {
                  this.pageStack.pushPathByName('WebView', new WebViewParam('https://beian.miit.gov.cn/', 'ICP备案查询'));
                })
            }
            .margin({ bottom: 8 })
            
            Text("记得订阅. All Rights Reserved.")
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 30 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .opacity(this.animStep2 ? 1 : 0)
          .translate({ y: this.animStep2 ? 0 : 20 })
        }
        .width('100%')
        .height('100%')
        .padding({ top: TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight) }) // Push content down
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: {
          mainTitle: '关于应用'
        }
      }
    })
    .backgroundColor($r('app.color.page_background'))
  }
}

@Builder
export function AboutPageBuilder(name: string, param: Object) {
  AboutPage()
}
