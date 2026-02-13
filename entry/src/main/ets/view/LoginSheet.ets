/**
 * 登录 Sheet 组件
 * 使用 BindSheet 弹出的登录界面
 */
import { HuaweiAuthManager } from '../utils/HuaweiAuthManager';
import { privacyManager } from '@kit.StoreKit';
import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { hdsEffect } from '@kit.UIDesignKit';

import { promptAction, curves } from '@kit.ArkUI';
import { WebViewParam } from './WebViewPage';

@Component
export struct LoginSheet {
  @Consume('pageStack') pageStack: NavPathStack;
  @Prop isShow: boolean = false;
  onSuccess: () => void = () => {};
  onClose: () => void = () => {};
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('isOnline') isOnline: boolean = true;
  
  // Theme States
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  
  // 入场动画
  @State contentOpacity: number = 0;
  @State contentTranslateY: number = 30;
  @State isLoading: boolean = false;
  
  // 隐私政策同意状态
  @State isPrivacyAgreed: boolean = false;
  
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;

  // Interaction State
  @State isLoginPressed: boolean = false;
  @State loginLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  aboutToAppear() {
    if (this.isAnimationEnabled) {
      setTimeout(() => {
        animateTo({
          duration: this.animationDuration,
          curve: curves.springMotion(this.animationResponse, this.animationDamping)
        }, () => {
          this.contentOpacity = 1;
          this.contentTranslateY = 0;
        });
      }, 50);
    } else {
      this.contentOpacity = 1;
      this.contentTranslateY = 0;
    }
  }
  
  async handleLogin() {
    if (this.isLoading) return;

    // 检查是否同意隐私政策
    if (!this.isPrivacyAgreed) {
      promptAction.showToast({ message: '请先阅读并同意用户协议和隐私政策' });
      return;
    }

    if (!this.isOnline) {
       promptAction.showToast({ message: '无法连接到服务器,请检查设备的网络连接' });
       return;
    }

    this.isLoading = true;
    try {
      await HuaweiAuthManager.getInstance().login(false);
      
      if (this.isLoggedIn) {
        // 登录成功, 初始化数据库并关闭
        const ctx = HuaweiAuthManager.getInstance().getContext();
        if (ctx) {
          setTimeout(() => {
            SubscriptionRepository.getInstance().init(ctx);
            // 本地模式，不再同步云端
            this.onSuccess();
          }, 500);
        } else {
          this.onSuccess();
        }
      }
    } catch (e) {
      // Login failed or cancelled
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // Logo 和标题
      Column() {
        Image($r('app.media.foreground'))
          .width(80)
          .height(80)
          .borderRadius(20)
          .margin({ bottom: 16 })
        
        Text('记得订阅')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })
        
        Text('登录后即刻体验完整功能')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      .margin({ top: 20, bottom: 32 })
      .alignItems(HorizontalAlign.Center)
      
      // 华为登录按钮
      Button() {
        Row() {
          if (this.isLoading) {
             LoadingProgress()
               .width(20)
               .height(20)
               .color(Color.White)
               .margin({ right: 8 })
             Text('正在登录...')
               .fontSize(17)
               .fontWeight(FontWeight.Medium)
               .fontColor(Color.White)
          } else {
             Text('华为账号登录')
               .fontSize(17)
               .fontWeight(FontWeight.Medium)
               .fontColor(Color.White)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
        .enabled(!this.isLoading) // Loading时禁用，未勾选协议时不禁用（以保持高对比度并支持各点击提示）
        .type(ButtonType.Capsule)
        .width('80%')
        .height(50)
        .backgroundColor(this.isPrivacyAgreed ? '#E60012' : $r('app.color.text_hint'))
        .shadow({ radius: this.isPrivacyAgreed ? 8 : 0, color: this.isPrivacyAgreed ? '#40E60012' : '#00000000', offsetY: this.isPrivacyAgreed ? 4 : 0 })
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: this.loginLight,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .scale({ x: this.isLoginPressed ? 0.95 : 1, y: this.isLoginPressed ? 0.95 : 1 })
        .onTouch((event: TouchEvent) => {
            if (this.isPrivacyAgreed) {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isLoginPressed = true;
                    this.loginLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isLoginPressed = false;
                this.loginLight = hdsEffect.PointLightSourceType.NONE;
              }
            }
        })
        .animation({ 
           duration: this.isAnimationEnabled ? 150 : 0, 
           curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
        })
        .onClick(() => {
          this.handleLogin();
        })
      
      // 恢复其他登录方式提示
      Text('使用华为账号安全登录')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8, bottom: 4 }) 
      
      // 底部合规与协议区域
      Column() {
        // 合规声明（更紧凑、左对齐）
        Text('应相关法律法规要求，使用生成式人工智能功能需要核验用户身份。《记得订阅》将通过华为账号登录间接核验用户身份的真实性。')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.6)
          .textAlign(TextAlign.Start)
          .width('100%')
          .margin({ bottom: 8 })

        // 隐私政策同意区域
        Row() {
          Checkbox({ name: 'privacy_checkbox', group: 'privacy_group' })
            .select(this.isPrivacyAgreed)
            .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
            .onChange((value: boolean) => {
              this.isPrivacyAgreed = value;
            })
            .width(16)
            .height(16)
            .margin({ right: 6 })

          Text() {
            Span('登录即代表您同意使用并已阅读')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))

            Span('《用户协议》')
              .fontSize(12)
              .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .onClick(() => {
                this.onClose();
                this.pageStack.pushPathByName('WebView', new WebViewParam($rawfile('user_agreement.html'), '用户协议'));
              })

            Span('和')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))

            Span('《隐私政策》')
              .fontSize(12)
              .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .onClick(() => {
                this.onClose();
                const defaultUrl = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1866142389635159616';
                let targetUrl = defaultUrl;
                try {
                  const mgmtInfo = privacyManager.getAppPrivacyMgmtInfo();
                  if (mgmtInfo && mgmtInfo.privacyInfo) {
                    const privacyLink = mgmtInfo.privacyInfo.find(link => link.type === privacyManager.AppPrivacyLinkType.PRIVACY_STATEMENT_LINK);
                    if (privacyLink && privacyLink.url) {
                      targetUrl = privacyLink.url;
                    }
                  }
                } catch (e) {
                  console.error('Failed to get privacy url:', JSON.stringify(e));
                }
                this.pageStack.pushPathByName('WebView', new WebViewParam(targetUrl, '隐私政策'));
              })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('85%')
      .margin({ top: 10 }) 
      
      Blank()

    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
    .opacity(this.contentOpacity)
    .translate({ y: this.contentTranslateY })
  }
}
