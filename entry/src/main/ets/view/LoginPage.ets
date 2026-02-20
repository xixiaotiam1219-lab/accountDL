import { LoginSheet } from './LoginSheet';
import { BackgroundWatermark } from './BackgroundWatermark';
import { hdsMaterial, HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';

@Builder
export function LoginPageBuilder() {
  LoginPage()
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
struct LoginPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder LoginBuilder(){
    Stack({ alignContent: Alignment.Top }) {
      // Universal Background Watermark
      BackgroundWatermark()
        .zIndex(0)

      // Content
      Column() {
        Column().height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.statusBarHeight))
        LoginSheet({
          onSuccess: () => {
            this.pageStack.pop();
          },
          onClose: () => {
            this.pageStack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  build() {
      HdsNavDestination() {
          this.LoginBuilder()
      }
      .titleBar({
        content: {
          title: {
            mainTitle: '登录'
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
      .backgroundColor($r('app.color.page_background'))


  }
}
