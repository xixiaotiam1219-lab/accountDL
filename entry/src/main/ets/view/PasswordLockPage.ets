import { PreferenceUtil } from '../utils/PreferenceUtil';
import { promptAction, curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { userAuth, UserAuthIcon } from '@kit.UserAuthenticationKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { mediaquery } from '@kit.ArkUI';

@Component
export struct PasswordLockPage {
  @Prop mode: 'verify' | 'set' | 'disable' | 'change' = 'verify';
  @Prop checkBiometric: boolean = false; // Force check biometric even if disabled in prefs (For Setup)
  @Prop checkTypes: number[] = []; // Specific types to check (UserAuthType)
  onSuccess: () => void = () => {};
  onCancel: () => void = () => {};
  
  @State password: string = '';
  @State confirmPassword: string = ''; // For set/change mode
  @State isConfirming: boolean = false; // true when entering confirmation password
  @State title: string = '输入密码';
  @State errorMessage: string = '';

  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;

  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  @StorageLink('appLockFace') appLockFace: boolean = false;
  @StorageLink('appLockFingerprint') appLockFingerprint: boolean = false;
  @StorageLink('appLockPasswordLength') passwordLength: number = 4;

  @State pressedKeyIndex: number = -1;
  @State keyLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Biometric Auth State
  @State showUserAuthIcon: boolean = false;
  @State showKeypad: boolean = true;
  @State authParam: userAuth.AuthParam = {
    challenge: new Uint8Array([1, 2, 3, 4, 5, 6]),
    authType: [],
    authTrustLevel: userAuth.AuthTrustLevel.ATL3
  };
  @State widgetParam: userAuth.WidgetParam = {
    title: '验证已开启的应用锁'
  };

  // Tablet & Foldable Adaptation
  @State isTablet: boolean = false;
  @State isUltraWide: boolean = false;
  @State isPhoneDevice: boolean = false; // Hardware-level phone check
  @State isTabletDevice: boolean = false; // Hardware-level tablet check
  private tabletListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width >= 600vp)');
  private ultraWideListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width >= 840vp)');

  private get useSideBySide(): boolean {
    // Force vertical layout for consistent compact experience
    return false;
  }

  aboutToAppear() {
    // Hardware detection
    this.isPhoneDevice = deviceInfo.deviceType === 'phone';
    this.isTabletDevice = deviceInfo.deviceType === 'tablet';

    // Initialize state immediately from current display
    this.isTablet = this.tabletListener.matches;
    this.isUltraWide = this.ultraWideListener.matches;

    // Register media query listener
    this.tabletListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isTablet = result.matches;
      this.updateTitle();
    }); 
    this.ultraWideListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isUltraWide = result.matches;
    });
    this.isTablet = this.tabletListener.matches;
    this.isUltraWide = this.ultraWideListener.matches;

    this.updateTitle();
    // Auto-start biometric auth in verify mode
    if (this.mode === 'verify') {
        const hasBiometric = this.appLockFace || this.appLockFingerprint;
        // Only hide keypad on phones (isTablet is false)
        if ((hasBiometric || this.checkBiometric) && !this.isTablet) {
            this.showKeypad = false;
        }
        this.startBiometricAuth();
    } else {
        this.showKeypad = true;
    }
  }

  updateTitle() {
    if (this.mode === 'verify') {
      // Dynamic title based on active method
      // Only show "Authenticating..." title style if keypad is hidden (Phone Mode)
      if (!this.showKeypad && this.showUserAuthIcon && !this.isTablet) {
          this.title = '验证身份';
      } else {
          this.title = '输入密码解锁';
      }
    } else if (this.mode === 'disable') {
      this.title = '输入密码关闭应用锁';
    } else if (this.mode === 'set') {
      this.title = this.isConfirming ? '再次输入密码' : '设置新密码';
    } else if (this.mode === 'change') {
       this.title = this.isConfirming ? '再次输入新密码' : '设置新密码';
    }
  }

  async startBiometricAuth() {
    try {
        const isFaceEnabled = this.appLockFace;
        const isFingerprintEnabled = this.appLockFingerprint;

        const authType: userAuth.UserAuthType[] = [];
        
        if (this.checkBiometric && this.checkTypes.length > 0) {
            // Force check specific types (For Setup)
            authType.push(...this.checkTypes);
        } else {
            // Default: Check enabled types from prefs
            if (isFaceEnabled) authType.push(userAuth.UserAuthType.FACE);
            if (isFingerprintEnabled) authType.push(userAuth.UserAuthType.FINGERPRINT);
        }
        
        if (authType.length === 0) {
            console.info('Biometric auth skipped: No methods enabled.');
            this.showUserAuthIcon = false;
            if (this.checkBiometric) {
                this.onCancel();
            } else {
                this.showKeypad = true;
                this.updateTitle();
            }
            return; 
        }

        const challenge: Uint8Array = new Uint8Array([1, 2, 3, 4, 5, 6]); 
        const authTrustLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3;
        
        // Update State for UserAuthIcon
        this.authParam = {
            challenge: challenge,
            authType: authType,
            authTrustLevel: authTrustLevel
        };
        this.showUserAuthIcon = true;
        // Only hide keypad on phones
        if (!this.isTablet) {
            this.showKeypad = false; 
        }
        this.updateTitle();
        
        try {
             const userAuthInstance = userAuth.getUserAuthInstance(this.authParam, this.widgetParam);
             
             userAuthInstance.on('result', {
                 onResult: (result) => {
                     // Only handle success here, failures allow retry via Icon or Password
                     if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
                         this.onSuccess();
                     } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
                         // User cancelled (e.g. side button) 
                         if (this.checkBiometric) {
                             // If in setup/force-check mode, cancel should exit immediately
                             this.onCancel();
                         } else {
                             // Default unlock mode: show keypad for password fallback
                             this.showKeypad = true;
                             this.updateTitle();
                         }
                     }
                 }
             });
             
             userAuthInstance.start();
        } catch (error) {
            const err = error as BusinessError;
            console.error(`Auth start failed: ${err.code}, ${err.message}`);
            // If auto start fails, user can click icon or use password
            // Don't auto-show keypad yet, let user decide or retry via icon
        }
    } catch (err) {
        console.error(`Biometric setup failed: ${JSON.stringify(err)}`);
        if (this.checkBiometric) {
            this.onCancel();
        } else {
            this.showKeypad = true;
            this.updateTitle(); 
        }
    }
  }

  handleInput(num: string) {
    if (this.password.length < this.passwordLength) {
      this.password += num;
      this.errorMessage = '';
      if (this.password.length === this.passwordLength) {
        this.checkPassword();
      }
    }
  }

  handleDelete() {
    if (this.password.length > 0) {
      this.password = this.password.slice(0, -1);
      this.errorMessage = '';
    }
  }

  handleReset() {
    this.password = '';
    this.errorMessage = '';
    if (this.mode === 'set' || this.mode === 'change') {
       this.isConfirming = false;
       this.confirmPassword = '';
       this.updateTitle();
    }
  }

  async checkPassword() {
    if (this.mode === 'verify' || this.mode === 'disable') {
      const savedPassword = await PreferenceUtil.getInstance().getAppLockPassword();
      if (this.password === savedPassword) {
        this.onSuccess();
      } else {
        this.errorMessage = '密码错误，请重试';
        this.shakeAnimation();
        this.clearPassword();
      }
    } else if (this.mode === 'set' || this.mode === 'change') {
      if (!this.isConfirming) {
        this.confirmPassword = this.password;
        this.isConfirming = true;
        this.password = '';
        this.updateTitle();
      } else {
        if (this.password === this.confirmPassword) {
          await PreferenceUtil.getInstance().saveAppLockPassword(this.password);
          promptAction.showToast({ message: '密码设置成功' });
          this.onSuccess();
        } else {
          this.errorMessage = '两次密码不一致，请重新输入';
          this.shakeAnimation();
          this.isConfirming = false;
          this.password = '';
          this.confirmPassword = '';
          this.updateTitle();
        }
      }
    }
  }

  clearPassword() {
    setTimeout(() => {
      this.password = '';
    }, 200);
  }

  shakeAnimation() {
    // Placeholder for shake animation
  }

  // Helper to determine text color
  getTextColor(): ResourceColor {
      // Use system default text color (Black in Light, White in Dark)
      // Even for New Year theme, user found red text "ugly", so we stick to system primary.
      return $r('sys.color.font_primary');
  }

  // Helper for secondary/subtitle color
  getSecondaryTextColor(): ResourceColor {
      if (this.isNewYearTheme) {
          return $r('app.color.sub_card_ny_title');
      }
      return $r('sys.color.font_secondary');
  }

  @Builder
  KeyPadButton(item: string, index: number) {
    Column() {
      if (item === 'del') {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(28)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.getTextColor()])
      } else if (item !== '') {
        Text(item)
          .fontSize(item === '重置' ? 18 : 28)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getTextColor())
      }
    }
    .width(70) // Compact tap target
    .height(70)
    .justifyContent(FlexAlign.Center)
    .borderRadius(40)
    .backgroundColor(
      (this.isPointLightEnabled && this.pressedKeyIndex === index)
        ? (this.isNewYearTheme ? '#73D93025' : (this.showVipTheme ? '#73D4AF37' : '#73000000')) // 按压态：45% 不透明度
        : (this.isNewYearTheme ? '#2EFF2400' : (this.showVipTheme ? '#2EEDC269' : '#2E000000')) // 常态：18% 不透明度，确保显著色差
    )
    .scale({ 
      x: (this.isPointLightEnabled && this.pressedKeyIndex === index) ? 0.8 : 1, 
      y: (this.isPointLightEnabled && this.pressedKeyIndex === index) ? 0.8 : 1 
    })
    .clip(true) // 防止点光源阴影/光效溢出到边距
    .animation({ 
      duration: this.isAnimationEnabled ? 150 : 0, 
      curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: (this.isPointLightEnabled && this.pressedKeyIndex === index) ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
            this.pressedKeyIndex = index;
            // Point light only if enabled
            if (this.isPointLightEnabled) {
                this.keyLightSource = hdsEffect.PointLightSourceType.BRIGHT;
            }
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedKeyIndex = -1;
            this.keyLightSource = hdsEffect.PointLightSourceType.NONE;
            
            if (item === 'del') {
                this.handleDelete();
            } else if (item === '重置') {
                this.handleReset();
            } else if (item !== '') {
                this.handleInput(item);
            }
        }
    })
  }

  build() {
    Column() {
      // 0. 面板手柄 (增强面板感)
      Column() {
        Row()
          .width(36)
          .height(4)
          .backgroundColor($r('app.color.divider_color'))
          .borderRadius(2)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 4 })

      // 1. 顶部操作栏 (取消按钮)
      Row() {
        if (this.mode !== 'verify') {
          Text('取消')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getTextColor())
            .onClick(() => {
              this.onCancel();
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ right: 24 })
      .height(40)

      // 2. 核心验证区 (自适应高度)
      Column() {
        // 顶部微留白
        Column().height(16)

        if (!this.showKeypad && this.mode === 'verify' && !this.isTablet) {
          // 生物识别精简视图
          Column() {
            UserAuthIcon({
              authParam: this.authParam,
              widgetParam: this.widgetParam,
              iconHeight: 56,
              iconColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')),
              onAuthResult: (result: userAuth.UserAuthResult) => {
                if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
                  this.onSuccess();
                } else if (result.result === userAuth.UserAuthResultCode.CANCELED) {
                  if (this.checkBiometric) {
                    this.onCancel();
                  } else {
                    this.showKeypad = true;
                    this.updateTitle();
                  }
                }
              }
            })
            .margin({ bottom: 16 })

            Text(this.title)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getTextColor())
              .margin({ bottom: 32 }) // 增加间距替代圆点位置

            if (!this.checkBiometric) {
              Text("使用密码解锁")
                .fontSize(14)
                .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .onClick(() => {
                  this.showKeypad = true;
                  this.updateTitle();
                })
                .padding(8)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else {
          // 完整键盘视图
          Column() {
            Column() {
              if (this.showUserAuthIcon && this.mode === 'verify') {
                UserAuthIcon({
                  authParam: this.authParam,
                  widgetParam: this.widgetParam,
                  iconHeight: 52,
                  iconColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')),
                  onAuthResult: (result: userAuth.UserAuthResult) => {
                    if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
                      this.onSuccess();
                    }
                  }
                })
                .margin({ bottom: 8 })
              } else {
                SymbolGlyph($r('sys.symbol.lock'))
                  .fontSize(48)
                  .fontColor([this.getTextColor()])
                  .margin({ bottom: 8 })
              }

              Text(this.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getTextColor())
                .margin({ bottom: 2 })

              Text(this.errorMessage)
                .fontSize(12)
                .fontColor(Color.Red)
                .height(14)
                .opacity(this.errorMessage ? 1 : 0)
                .margin({ bottom: 6 })

              Row({ space: this.passwordLength === 6 ? 10 : 14 }) {
                ForEach([0, 1, 2, 3, 4, 5].slice(0, this.passwordLength), (index: number) => {
                  Circle({ width: 9, height: 9 })
                    .fill(this.password.length > index ?
                      (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) :
                      '#E5E5E5')
                    .animation({ duration: 200 })
                }, (index: number) => index.toString())
              }
            }
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 8 })

            Column() {
              if (this.mode === 'set' || this.mode === 'change') {
                Text(`切换为 ${this.passwordLength === 4 ? '6' : '4'} 位密码`)
                  .fontSize(13)
                  .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                  .padding(4)
                  .opacity(this.isConfirming ? 0 : 1)
                  .animation({ duration: 300, curve: Curve.EaseInOut })
                  .hitTestBehavior(this.isConfirming ? HitTestMode.None : HitTestMode.Default)
                  .onClick(() => {
                    animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
                      const newLen = this.passwordLength === 4 ? 6 : 4;
                      this.password = '';
                      this.passwordLength = newLen;
                      PreferenceUtil.getInstance().saveAppLockPasswordLength(newLen);
                    })
                  })
              }
            }
            .height((this.mode === 'set' || this.mode === 'change') ? 28 : 0)
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 4 })

            Grid() {
              ForEach(['1', '2', '3', '4', '5', '6', '7', '8', '9', '重置', '0', 'del'], (item: string, index: number) => {
                GridItem() {
                  this.KeyPadButton(item, index)
                }
              }, (item: string) => item)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .rowsGap(8)
            .width('100%')
            .clip(true) // 额外剪裁层，防止子组件点光源溢出
            .constraintSize({ maxWidth: 360 })
            .padding({ left: 32, right: 32 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 448 })
      .padding({ bottom: 48 }) // 底部留出安全区，消除巨大空白
    }
    .width('100%')
    .backgroundColor(
      (this.mode === 'verify' ? $r('sys.color.background_primary') : $r('app.color.card_background'))
    )
    .borderRadius({ topLeft: 24, topRight: 24 }) // 面板圆角
    .backgroundBlurStyle(this.mode === 'verify' ? BlurStyle.Regular : BlurStyle.NONE)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
