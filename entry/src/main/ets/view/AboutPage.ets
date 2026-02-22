import { WebViewParam } from './WebViewPage';
import { BackgroundWatermark } from './BackgroundWatermark';
import {   HdsNavDestination, ScrollEffectType, hdsEffect } from '@kit.UIDesignKit';
import { curves, LengthMetrics, PromptAction, promptAction } from '@kit.ArkUI';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { privacyManager } from '@kit.StoreKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { AccountMonitor } from '../utils/AccountMonitor';

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct AboutPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  private appVersion: string = 'v1.0.3';
  private agreementUrl: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1866142389635159616';
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  // Animation System
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationResponse') animationResponse: number = 0.35;
  @StorageLink('animationDamping') animationDamping: number = 0.75;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
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

  handleDisablePrivacyService() {
    this.promptAction.showDialog({
      title: '撤销隐私政策',
      message: '撤销后将停止收集订阅信息等功能。应用将清除本地缓存并自动登出账号，确定要撤销吗？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '撤销', color: '#E60012' }
      ]
    }).then(async (result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        try {
          privacyManager.disableService();
          hilog.info(0x0000, 'AboutPage', "Succeeded in disabling service.");

          // 执行退出登录清理逻辑
          AccountMonitor.getInstance().handleLogout();

          this.promptAction.showToast({ message: '隐私协议已撤销，应用程序即将退出' });

          // 立即退出
          const context = getContext(this) as common.UIAbilityContext;
          context.terminateSelf();

        } catch (error) {
          const err = error as BusinessError;
          hilog.error(0x0000, 'AboutPage', "DisableService exception code: " + err.code + ", exception message: " + err.message);
          this.promptAction.showToast({ message: `撤销失败: ${err.message} (Code: ${err.code})` });
        }
      }
    });
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
                .shadow({
                  radius: 10,
                  color: '#10000000',
                  offsetX: 0,
                  offsetY: 4
                })

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

            Column({ space: 12 }) {
              PrivacyListItem({
                title: "隐私政策",
                action: () => {
                  let targetUrl = this.agreementUrl;
                  try {
                    const mgmtInfo = privacyManager.getAppPrivacyMgmtInfo();
                    if (mgmtInfo && mgmtInfo.privacyInfo) {
                      const privacyLink = mgmtInfo.privacyInfo.find((link: privacyManager.AppPrivacyLink) => link.type ===
                      privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK);
                      if (privacyLink && privacyLink.url) {
                        targetUrl = privacyLink.url;
                      }
                    }
                  } catch (e) {
                    hilog.error(0x0000, 'AboutPage', 'Failed to get privacy url: %{public}s', JSON.stringify(e));
                  }
                  this.pageStack.pushPathByName('WebView', new WebViewParam(targetUrl, '隐私政策'));
                }
              })

              PrivacyListItem({
                title: "用户协议",
                action: () => {
                  this.pageStack.pushPathByName('WebView', new WebViewParam($rawfile('user_agreement.html'), '用户协议'));
                }
              })

              PrivacyListItem({
                title: "开源许可",
                action: () => {
                  this.pageStack.pushPathByName('OpenSourceLicense', null);
                }
              })

              PrivacyListItem({
                title: "闽ICP备2026001305号-2A",
                action: () => {
                  this.pageStack.pushPathByName('WebView',
                    new WebViewParam('https://beian.miit.gov.cn/', 'ICP备案查询'));
                }
              })

              PrivacyListItem({
                title: "撤销隐私政策",
                isDestructive: true,
                action: () => {
                  this.handleDisablePrivacyService();
                }
              })

              // 底部元信息
              Column() {
                Divider().color($r('app.color.divider_color')).margin({ top: 8, bottom: 16 })

                Text("记得订阅. All Rights Reserved.")
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 10 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
            .width('90%')
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
        },
        // style:(deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
        //   systemMaterialEffect: {
        //     materialType: hdsMaterial.MaterialType.IMMERSIVE,
        //     materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
        //   },
        //   scrollEffectOpts: {
        //     enableScrollEffect: true,
        //     scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
        //     blurEffectiveStartOffset: LengthMetrics.vp(0),
        //     blurEffectiveEndOffset: LengthMetrics.vp(20)
        //   }
        // }:undefined
      })
      .backgroundColor($r('app.color.page_background'))

  }
}

@Component
struct PrivacyListItem {
  title: string = '';
  action: () => void = () => {
  };
  isDestructive: boolean = false;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @State isPressed: boolean = false;
  @State lightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  build() {
    Row() {
      Text(this.title)
        .fontSize(16)
        .fontColor(this.isDestructive ? Color.Red : $r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
      Blank()
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.lightSource,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
    .animation({ duration: (this.isAnimationEnabled || this.isPointLightEnabled) ? 150 : 0, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isPointLightEnabled) {
          this.isPressed = true;
          this.lightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.lightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
    .onClick(() => {
      this.action();
    })
  }
}

@Builder
export function AboutPageBuilder(name: string, param: Object) {
  AboutPage()
}
