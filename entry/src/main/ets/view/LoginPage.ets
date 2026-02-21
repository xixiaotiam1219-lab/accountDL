import { LoginSheet } from './LoginSheet';
import { BackgroundWatermark } from './BackgroundWatermark';
import {  HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';

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
      })
      .backgroundColor($r('app.color.page_background'))


  }
}
