import { formProvider } from '@kit.FormKit';
import { appInfoManager } from '@kit.AppGalleryKit';
import { display, promptAction, curves, LengthMetrics } from '@kit.ArkUI'; // Added import
import { ImageCropSheet } from './ImageCropPage';

import { BusinessError, deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util, buffer } from '@kit.ArkTS';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { PasswordLockPage } from './PasswordLockPage';

import { SubscriptionRepository } from '../model/SubscriptionRepository';
import { HuaweiAuthManager } from '../utils/HuaweiAuthManager';
import { LocalIconManager } from '../utils/LocalIconManager';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { PromptAction } from '@kit.ArkUI';
import { LoginSheet } from './LoginSheet';
import { WebViewParam } from './WebViewPage';
import { UpdateManager } from '../utils/UpdateManager';
import { AccountMonitor } from '../utils/AccountMonitor';
import { hdsEffect, hdsMaterial, HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { ImportSheet } from './ImportSheet';
import { DynamicIconSheet } from './DynamicIconSheet';
import { SubscriptionModel } from '../model/SubscriptionModel';
import { LocalNotificationManager } from '../manager/LocalNotificationManager';
import { HarmonyShareManager, CustomIconItem } from '../utils/HarmonyShareManager';
import { userAuth } from '@kit.UserAuthenticationKit';


const DOMAIN = 0x0000;

interface SimpleAppInfo {
  icon_url: string;
  name: string;
}

interface SimpleSearchResponse {
  apps: SimpleAppInfo[];
}

// Export Data Interface
interface ExportDataWrapper {
  version: string | number;
  exportTime: string;
  timestamp?: number;
  count: number;
  data?: SubscriptionModel[];
  subscriptions?: SubscriptionModel[];
  customIcons?: CustomIconItem[];
}




const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct SettingsView {
  @Consume('pageStack') pageStack: NavPathStack;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  @StorageLink('isWide') isWide: boolean = false;
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @StorageLink('isSplitViewEnabled') isSplitViewEnabled: boolean = true;
  @StorageLink('userName') userName: string = '立即登录';
  @State userEmail: string = '华为账号昵称';
  @StorageLink('userAvatar') userAvatar: string = '';
  @StorageLink('pushToken') pushToken: string = '';
  @State isPushing: boolean = false;

  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @State showLoginSheet: boolean = false;
  @State themeMode: number = 0; // 0: System, 1: Light, 2: Dark
  @State versionName: string = '';
  @StorageLink('hasNewVersion') hasNewVersion: boolean = false;
  @StorageLink('isAnimationEnabled') @Watch('onAnimationEnabledChange') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') @Watch('onAnimationDurationChange') animationDuration: number = 400;
  @StorageLink('animationDamping') @Watch('onAnimationDurationChange') animationDamping: number = 0.5;
  @StorageLink('animationResponse') @Watch('onAnimationDurationChange') animationResponse: number = 0.6;
  @StorageLink('animationPresetMode') @Watch('onAnimationPresetModeChange') animationPresetMode: number = 0; // 0: 自定义, 1: 慢, 2: 默认, 3: 快
  @StorageLink('isPointLightEnabled') @Watch('onPointLightEnabledChange') isPointLightEnabled: boolean = true;
  @State @Watch('onAnimationSheetChange') showAnimationSheet: boolean = false;

  @State showImportSheet: boolean = false;
  @State importData: SubscriptionModel[] = [];
  @State showDynamicIconSheet: boolean = false;
  @State hasDynamicIcons: boolean = false;


  // 主题状态 (原 VIP 主题 -> 黑金主题)
  @StorageLink('isVip') isVip: boolean = false;  // 复用此字段控制黑金主题开关权限
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('activeThemeId') activeThemeId: string = 'default';
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  @StorageLink('isSmartGestureEnabled') isSmartGestureEnabled: boolean = false;
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @StorageLink('isHdsTabsSupported') isHdsTabsSupported: boolean = false;
  @StorageLink('watermarkImage') watermarkImage: string = '';
  @StorageLink('watermarkOpacity') watermarkOpacity: number = 0.2;
  @StorageLink('watermarkOffsetX') watermarkOffsetX: number = 0; // Keeping for compatibility, though unused
  @StorageLink('watermarkOffsetY') watermarkOffsetY: number = 0; // Keeping for compatibility, though unused

  // Watermark Edit State
  @State showCustomBgSheet: boolean = false;
  @State showWatermarkEditSheet: boolean = false;
  @State tempWatermarkImage: string = '';
  @State tempWatermarkOpacity: number = 0.2;

  @StorageLink('appLockPasswordLength') appLockPasswordLength: number = 4;
  @State showPasswordLockSheet: boolean = false;
  @State showVerifySheet: boolean = false; // New separate sheet for verification
  @State verifyTarget: string = ''; // 'face', 'fingerprint'
  @State passwordLockMode: 'set' | 'disable' | 'change' | 'verify' = 'set';
  @StorageLink('hasAppLock') @Watch('onAppLockStatusChange') hasPasswordLock: boolean = false;
  @State showAppLockSettingsSheet: boolean = false;
  @State biometricCheckTypes: number[] = []; // userAuth.UserAuthType[]


  async checkPasswordLockStatus() {
    await PreferenceUtil.getInstance().getAppLockPassword();
  }

  onAppLockStatusChange() {
    // Only close the sheet if the user is logged out (auto-cleared)
    // If the user manually turns it off, keep the sheet open
    if (!this.hasPasswordLock && !this.isLoggedIn) {
      this.showAppLockSettingsSheet = false;
    }
  }

  @State supportFace: boolean = false;
  @State supportFingerprint: boolean = false;
  @StorageLink('appLockFace') isFaceEnabled: boolean = false;
  @StorageLink('appLockFingerprint') isFingerprintEnabled: boolean = false;


  async initBiometricSettings() {
    this.isFaceEnabled = await PreferenceUtil.getInstance().getAppLockFace();
    this.isFingerprintEnabled = await PreferenceUtil.getInstance().getAppLockFingerprint();
  }

  async checkBiometricSupport() {
    try {
      // Check Face
      try {
        userAuth.getAvailableStatus(userAuth.UserAuthType.FACE, userAuth.AuthTrustLevel.ATL3);
        this.supportFace = true;
      } catch (e) {
        this.supportFace = false;
      }

      // Check Fingerprint
      try {
        userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL3);
        this.supportFingerprint = true;
      } catch (e) {
        this.supportFingerprint = false;
      }
    } catch (err) {
      hilog.error(DOMAIN, 'SettingsView', `Biometric check failed: ${JSON.stringify(err)}`);
    }
  }




  @State customBgLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isClearCustomPressed: boolean = false;
  @State clearCustomLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isChangeCustomPressed: boolean = false;
  @State changeCustomLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;





  async handleSelectWatermarkImage() {
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoViewPicker = new picker.PhotoViewPicker();
      const photoSelectResult = await photoViewPicker.select(photoSelectOptions);

      if (photoSelectResult && photoSelectResult.photoUris.length > 0) {
        const uri = photoSelectResult.photoUris[0];
        // Copy to app storage to ensure persistence
        const context = getContext(this);
        const fileDir = context.filesDir;
        const fileName = `bg_watermark_${Date.now()}.png`;
        const targetPath = `${fileDir}/${fileName}`;

        try {
          const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
          // Read and Write to internal storage
          // Simplified copy for URI sharing issues

          // Note: Direct fs.copy might fail across providers, read/write is safer
          let buf = new ArrayBuffer(1024 * 1024 * 2); // 2MB chunk buffer
          // Since we can't easily stream copy with limited fs API in snippet,
          // we will just use the URI if it's accessible, or try a simple copy.
          // For Safety in HarmonyOS, URIs from picker usually need permission.
          // Best practice: Read content and save.

          // For now, let's try direct URI usage first.
          // If we want persistence, we should implement detailed copy.
          // Let's implement a simple copy strategy using available fs APIs.

          fs.copyFileSync(file.fd, targetPath);
          fs.closeSync(file);

          // Instead of saving immediately, open edit sheet
          this.tempWatermarkImage = `file://${targetPath}`;
          this.tempWatermarkOpacity = this.watermarkOpacity; // Load current or default
          this.showWatermarkEditSheet = true;

        } catch (e) {
          hilog.error(DOMAIN, 'SettingsView', `Failed to copy watermark: ${e}`);
          // Fallback
          this.tempWatermarkImage = uri;
          this.tempWatermarkOpacity = this.watermarkOpacity;
          this.showWatermarkEditSheet = true;
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, 'SettingsView', `Failed to select image: ${err}`);
      this.promptAction.showToast({ message: '选择图片失败' });
    }
  }

  handleSaveWatermark(uri: string) {
    if (uri) {
      PreferenceUtil.getInstance().saveWatermarkImage(uri);
      PreferenceUtil.getInstance().saveWatermarkOpacity(this.tempWatermarkOpacity);
      // Reset offsets since we are using cropped image now (image covers intended area)
      PreferenceUtil.getInstance().saveWatermarkOffset(0, 0);
      this.promptAction.showToast({ message: '背景水印设置成功' });
      this.showWatermarkEditSheet = false;
    }
  }

  handleClearWatermarkImage() {
    PreferenceUtil.getInstance().saveWatermarkImage('');
    this.promptAction.showToast({ message: '背景水印已清除' });
  }


  onAnimationDurationChange() {
    if (this.isAnimationEnabled && this.showAnimationSheet) {
      // Restart loop immediately to show effect
      this.resetPreviewPosition();
    }
  }

  onAnimationEnabledChange() {
    if (this.isAnimationEnabled && this.showAnimationSheet) {
      // Reset position
      this.resetPreviewPosition();
    }
  }

  onAnimationSheetChange(): void {
    if (this.showAnimationSheet) {
      // Trigger preview
      this.resetPreviewPosition();
    } else {
      // Stop loop when sheet closes
      this.stopAutoPlayLoop();
    }
  }

  onPointLightEnabledChange() {
    if (this.showAnimationSheet && this.isAnimationEnabled) {
      // Restart loop (No-op)
    }
  }

  // Preview animation states
  @State previewOffsetX: number = 0;
  @State previewOffsetY: number = 0;
  @State previewScale: number = 1;
  @State isDragging: boolean = false;
  private autoPlayTimer: number = -1;


  onAnimationPresetModeChange() {
    this.applyAnimationPreset(this.animationPresetMode);
  }

  applyAnimationPreset(mode: number) {
    if (mode === 0) return; // Custom, do nothing

    let duration = 400;
    let damping = 0.75;
    let response = 0.35;

    if (mode === 1) { // Slow
      duration = 600;
      damping = 0.6; // Reduced damping for more elasticity as requested
      response = 0.6;
    } else if (mode === 2) { // Default
      duration = 400;
      damping = 0.5;
      response = 0.5;
    } else if (mode === 3) { // Fast
      duration = 250;
      damping = 0.7;
      response = 0.2;
    }

    this.animationDuration = duration;
    this.animationDamping = damping;
    this.animationResponse = response;

    PreferenceUtil.getInstance().saveAnimationDuration(duration);
    PreferenceUtil.getInstance().saveAnimationDamping(damping);
    PreferenceUtil.getInstance().saveAnimationResponse(response);

    // Restart preview to show effect immediately
    if (this.isAnimationEnabled && this.showAnimationSheet) {
      this.resetPreviewPosition();
    }
  }

  // No auto-loop for drag preview
  resetPreviewPosition(): void {
    this.stopAutoPlayLoop();

    if (this.isAnimationEnabled) {
      // Return to center
      const dampedCurve = curves.springMotion(this.animationResponse, this.animationDamping);
      animateTo({ curve: dampedCurve, onFinish: () => {
        // Restart loop after return
        this.startAutoPlayLoop();
      }}, () => {
        this.previewOffsetX = 0;
        this.previewOffsetY = 0;
      })
    }
  }

  startAutoPlayLoop(): void {
    if (this.isDragging || !this.showAnimationSheet || !this.isAnimationEnabled) return;

    // Stop existing
    this.stopAutoPlayLoop();

    // Simple Left-Right loop
    const duration = this.animationDuration;
    const dampedCurve = curves.springMotion(this.animationResponse, this.animationDamping);

    const targetX = 60;

    // 1. Move Right
    animateTo({ duration: duration, curve: dampedCurve }, () => {
      if (!this.isDragging) this.previewOffsetX = targetX;
    })

    // 2. Move Left (after duration + pause)
    this.autoPlayTimer = setTimeout(() => {
      if (this.isDragging || !this.showAnimationSheet) return;

      animateTo({ duration: duration, curve: dampedCurve }, () => {
        if (!this.isDragging) this.previewOffsetX = -targetX;
      })

      // 3. Loop (after duration + pause)
      this.autoPlayTimer = setTimeout(() => {
        this.startAutoPlayLoop();
      }, duration + 800);

    }, duration + 800);
  }

  stopAutoPlayLoop(): void {
    if (this.autoPlayTimer !== -1) {
      clearTimeout(this.autoPlayTimer);
      this.autoPlayTimer = -1;
    }
  }


  // Animation States

  @Prop @Watch('onVisibleChange') isVisible: boolean = false;
  @State animStep1: boolean = false; // Profile Card
  @State animStep2: boolean = false; // General Settings
  @State animStep3: boolean = false; // Data & Security
  @State animStep4: boolean = false; // Desktop Widget
  @State animStep5: boolean = false; // About
  @State animHeader: boolean = false; // Title Header

  // Press states for scale animation
  @State pressCard1: boolean = false;
  @State pressCard2: boolean = false;
  @State pressCard3: boolean = false;
  @State pressCard5: boolean = false;

  // Point light source types for press effect
  @State lightSource1: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State lightSource2: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State lightSource3: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State lightSource5: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  // Button Interaction States
  @State isLoginBtnPressed: boolean = false;
  @State loginBtnLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isWidgetBtnPressed: boolean = false;
  @State widgetBtnLightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  onVisibleChange() {
    if (this.isVisible) {
      // 增强：每次可见时从偏好加载一次，防止状态不一致
      PreferenceUtil.getInstance().loadSplitViewEnabled().then(enabled => {
        if (this.isWide && enabled && !this.isSplitViewEnabled) {
          AppStorage.setOrCreate('isSplitViewEnabled', true);
        }
      });

      this.triggerEntranceAnimation();
    } else {
      // 离开时重置状态，确保下次进入时是从初始态（不可见）平滑过渡
      this.resetAnimationStates();
    }
  }

  private resetAnimationStates() {
    this.animStep1 = false;
    this.animStep2 = false;
    this.animStep3 = false;
    this.animStep4 = false;
    this.animStep5 = false;
    this.animHeader = false;
  }

  private triggerEntranceAnimation() {
    if (this.isAnimationEnabled) {
      const duration = this.animationDuration; // Bound to storage link already
      const interval = duration * 0.125;
      const dampedCurve = curves.springMotion(this.animationResponse, this.animationDamping);

      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animHeader = true }) }, 0);
      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animStep1 = true }) }, 0);
      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animStep2 = true }) }, interval);
      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animStep3 = true }) }, interval * 2);
      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animStep4 = true }) }, interval * 3);
      setTimeout(() => { animateTo({ duration: duration, curve: dampedCurve }, () => { this.animStep5 = true }) }, interval * 4);
    } else {
      this.animHeader = true;
      this.animStep1 = true;
      this.animStep2 = true;
      this.animStep3 = true;
      this.animStep4 = true;
      this.animStep5 = true;
    }
  }

  @Builder AnimationSettingsSheetBuilder() {
    Column() {
      // Handle Bar
      Row()
        .width(40)
        .height(4)
        .backgroundColor($r('app.color.text_secondary'))
        .opacity(0.2)
        .borderRadius(2)
        .margin({ top: 8, bottom: 20 })

      // Title & Main Toggle
      Row() {
        Text("动画配置")
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.isAnimationEnabled })
          .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .onChange((value: boolean) => {
            PreferenceUtil.getInstance().saveAnimationEnabled(value);
          })
      }
      .width('100%')
      .margin({ bottom: 24 })

      if (this.isAnimationEnabled) {
        // Draggable Spring Preview
        Column() {
          Row() {
            Text("效果预览")
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text("可拖拽小球体验回弹")
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .margin({ bottom: 12 })

          // Playground Area
          Stack({ alignContent: Alignment.Center }) {
            // Initial Center Marker (Optional)
            Circle({ width: 8, height: 8 })
              .fill($r('app.color.divider_color'))

            // Draggable Box
            Column()
              .width(64)
              .height(64)
              .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .borderRadius(16)
              .shadow({ radius: 24, color: '#40000000', offsetY: 8 })
              .translate({ x: this.previewOffsetX, y: this.previewOffsetY })
              .scale({ x: this.previewScale, y: this.previewScale })
              .gesture(
                PanGesture()
                  .onActionStart(() => {
                    this.isDragging = true;
                    this.stopAutoPlayLoop(); // Stop auto-play immediately
                    animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
                      this.previewScale = 0.9; // Press feedback
                    })
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    // Direct follow, no animation for immediate response
                    animateTo({ duration: 0 }, () => {
                      this.previewOffsetX = event.offsetX;
                      this.previewOffsetY = event.offsetY;
                    })
                  })
                  .onActionEnd(() => {
                    this.isDragging = false;
                    // Snap back with configured spring physics
                    const dampedCurve = curves.springMotion(this.animationResponse, this.animationDamping);
                    animateTo({ curve: dampedCurve, onFinish: () => {
                      // Resume auto-play after snap back
                      setTimeout(() => { this.startAutoPlayLoop(); }, 100);
                    }}, () => {
                      this.previewOffsetX = 0;
                      this.previewOffsetY = 0;
                      this.previewScale = 1; // Release scale
                    })
                  })
              )
          }
          .height(180)
          .width('100%')
          .backgroundColor($r('app.color.main_background')) // Contrast background
          .borderRadius(16)
          .clip(true)
        }
        .padding(16)
        .backgroundColor($r('app.color.divider_color'))
        .borderRadius(16)
        .margin({ bottom: 24 })
        .opacity(0.9)
      }

      // Controls
      Column() {
        // Compact Presets
        Row({ space: 8 }) {
          ForEach([1, 2, 3], (mode: number) => {
            Button(mode === 1 ? "慢速" : (mode === 2 ? "系统默认" : "极致快"))
              .layoutWeight(1)
              .height(32)
              .fontSize(12)
              .fontWeight(this.animationPresetMode === mode ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.animationPresetMode === mode ? Color.White : $r('app.color.text_primary'))
              .backgroundColor(this.animationPresetMode === mode ?
                (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) :
                $r('app.color.card_background'))
              .onClick(() => {
                PreferenceUtil.getInstance().saveAnimationPresetMode(mode);
              })
          }, (mode: number) => mode.toString())
        }
        .width('100%')
        .padding(4)
        .backgroundColor($r('app.color.divider_color'))
        .borderRadius(10)
        .margin({ bottom: 24 })

        // Compact Sliders
        Column({ space: 16 }) {
          // Duration
          Row({ space: 12 }) {
            Text("动画时长")
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width(60)

            Slider({
              value: this.animationDuration,
              min: 50, max: 1000, step: 50,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .blockColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .trackColor($r('app.color.divider_color'))
              .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .onChange((value: number, mode: SliderChangeMode) => {
                this.animationDuration = value;
                if (mode === SliderChangeMode.End) {
                  PreferenceUtil.getInstance().saveAnimationDuration(value);
                  if (this.animationPresetMode !== 0) PreferenceUtil.getInstance().saveAnimationPresetMode(0);
                }
              })

            Text(`${this.animationDuration/1000}s`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width(48)
              .textAlign(TextAlign.End)
              .maxLines(1)
          }

          // Damping
          Row({ space: 12 }) {
            Text("回弹阻尼")
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width(60)

            Slider({
              value: this.animationDamping * 100,
              min: 5, max: 100, step: 5,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .blockColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .trackColor($r('app.color.divider_color'))
              .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .onChange((value: number, mode: SliderChangeMode) => {
                this.animationDamping = value / 100;
                if (mode === SliderChangeMode.End) {
                  PreferenceUtil.getInstance().saveAnimationDamping(this.animationDamping);
                  if (this.animationPresetMode !== 0) PreferenceUtil.getInstance().saveAnimationPresetMode(0);
                  // Restart loop immediately
                  if (this.isAnimationEnabled && this.showAnimationSheet) {
                    this.resetPreviewPosition();
                  }
                }
              })

            Text(`${this.animationDamping.toFixed(2)}`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width(48)
              .textAlign(TextAlign.End)
          }

          // Response
          Row({ space: 12 }) {
            Text("响应速度")
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width(60)

            Slider({
              value: this.animationResponse * 100,
              min: 5, max: 100, step: 5,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .blockColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .trackColor($r('app.color.divider_color'))
              .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .onChange((value: number, mode: SliderChangeMode) => {
                this.animationResponse = value / 100;
                if (mode === SliderChangeMode.End) {
                  PreferenceUtil.getInstance().saveAnimationResponse(this.animationResponse);
                  if (this.animationPresetMode !== 0) PreferenceUtil.getInstance().saveAnimationPresetMode(0);
                  // Restart loop immediately
                  if (this.isAnimationEnabled && this.showAnimationSheet) {
                    this.resetPreviewPosition();
                  }
                }
              })

            Text(`${this.animationResponse.toFixed(2)}`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width(48)
              .textAlign(TextAlign.End)
          }
        }

        Divider().color($r('app.color.divider_color')).margin({ top: 24, bottom: 24 })

        // Interactive Feedback
        Row() {
          Text("交互反馈 (光效/按压)")
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.isPointLightEnabled })
            .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
            .onChange((value: boolean) => {
              PreferenceUtil.getInstance().savePointLightEnabled(value);
            })
        }
        .width('100%')
      }
      .opacity(this.isAnimationEnabled ? 1 : 0.5)
      .enabled(this.isAnimationEnabled)

    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 32 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder DynamicIconSheetBuilder() {
    DynamicIconSheet()
  }

  async checkDynamicIconsAvailability() {
    try {
      const icons = await appInfoManager.queryDynamicIcons();
      this.hasDynamicIcons = icons && icons.length > 0;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 1006800010) {
        this.hasDynamicIcons = false;
      } else {
        hilog.error(DOMAIN, 'SettingsView', "Failed to check dynamic icons: " + err.message);
      }
    }
  }


  aboutToAppear() {
    this.checkPasswordLockStatus();
    this.checkBiometricSupport();
    this.initBiometricSettings();
    this.checkDynamicIconsAvailability();
    let bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT;
    bundleManager.getBundleInfoForSelf(bundleFlags).then((data) => {
      this.versionName = `v${data.versionName} (${data.versionCode})`;
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, 'SettingsView', 'Failed to get bundle info: %{public}s', JSON.stringify(err));
    });

    PreferenceUtil.getInstance().loadTheme().then(mode => {
      this.themeMode = mode;
    });
    PreferenceUtil.getInstance().loadSplitViewEnabled().then(enabled => {
      // Sync Link
      AppStorage.setOrCreate('isSplitViewEnabled', enabled);
    });
    PreferenceUtil.getInstance().loadAnimationEnabled();
    PreferenceUtil.getInstance().loadAnimationDamping();
    PreferenceUtil.getInstance().loadAnimationResponse();
    PreferenceUtil.getInstance().loadAnimationPresetMode();
    PreferenceUtil.getInstance().loadPointLightEnabled();
    PreferenceUtil.getInstance().loadShowVipTheme();
    PreferenceUtil.getInstance().loadNewYearWatermarkEnabled();
    PreferenceUtil.getInstance().loadNewYearWatermarkEnabled().then(enabled => {
      AppStorage.setOrCreate('isNewYearWatermarkEnabled', enabled);
    });
    PreferenceUtil.getInstance().loadSmartGestureEnabled();
    PreferenceUtil.getInstance().loadHdsTabsEnabled();
    // Initialize Local Icon Manager
    LocalIconManager.getInstance().init(getContext(this));

    // Sync local theme state - Delegated to PreferenceUtil
    // Legacy logic removed to allow theme switching for all users

    this.onVisibleChange();
  }



  // 自定义登录方法
  async handleHuaweiLogin() {
    // 使用 HuaweiAuthManager 处理登录
    await HuaweiAuthManager.getInstance().login(false);

    // 登录完成后，初始化数据库 (本地模式)
    if (this.isLoggedIn) {
      setTimeout(() => {
        SubscriptionRepository.getInstance().init(getContext(this));
      }, 1000);
    }
  }

  // 调用后端登录接口
  // loginToBackend 已移至 HuaweiAuthManager

  // 移除本地授权逻辑，改用后端统一处理
  private handleProfileError(error: BusinessError): void {
    // Placeholder
  }

  dealAllError(error: BusinessError): void {
    hilog.error(0x0000, 'testTag', `Failed to login: ${error.code}, ${error.message}`);
  }

  // 导出 CSV
  async handleExportCSV() {
    if (!this.isLoggedIn) {
      if (this.isWide) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    try {
      // 1. 获取所有数据
      const subs = await SubscriptionRepository.getInstance().queryAll();
      if (!subs || subs.length === 0) {
        this.promptAction.showToast({ message: '暂无订阅数据可导出' });
        return;
      }

      // 2. 构建 CSV 内容 (添加 BOM \uFEFF 以适配 Excel 打开乱码问题)
      // 增加团购券专用字段
      let csvContent = '\uFEFF类型,名称,价格,币种,周期,分类,下次扣款日,是否自动续费,商家,平台,券码,团购状态,实际使用日期,备注\n';

      subs.forEach(sub => {
        // 处理可能包含逗号的字段，用引号包裹
        const name = `"${sub.name.replace(/"/g, '""')}"`;
        const category = sub.category ? `"${sub.category}"` : '""';
        // 格式化日期 YYYY-MM-DD
        const dateObj = new Date(sub.nextBillingDate);
        const dateStr = `${dateObj.getFullYear()}-${(dateObj.getMonth() + 1).toString().padStart(2, '0')}-${dateObj.getDate().toString().padStart(2, '0')}`;
        // 格式化周期
        let cycle = '';
        switch (sub.billingCycle) {
          case 'Monthly': cycle = '月付'; break;
          case 'Quarterly': cycle = '季付'; break;
          case 'Yearly': cycle = '年付'; break;
          case 'Lifetime': cycle = '永久'; break;
          case 'Indefinite': cycle = '不定'; break;
          default: cycle = '未知';
        }

        const autoRenewal = sub.isAutoRenewal !== false ? '是' : '否';

        // 记录类型
        const recordType = sub.recordType === 'groupBuy' ? '团购券' : '订阅';

        // 团购券专用字段
        const merchantName = sub.merchantName ? `"${sub.merchantName.replace(/"/g, '""')}"` : '""';
        const platform = sub.platform || '';
        const couponCode = sub.couponCode ? `"${sub.couponCode.replace(/"/g, '""')}"` : '""';
        const usageStatus = sub.usageStatus === 'used' ? '已使用' : (sub.usageStatus === 'unused' ? '待使用' : '');
        const realUsageTime = sub.realUsageTime ? (() => {
          const d = new Date(sub.realUsageTime);
          return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
        })() : '';

        csvContent += `${recordType},${name},${sub.price},${sub.currency},${cycle},${category},${dateStr},${autoRenewal},${merchantName},${platform},${couponCode},${usageStatus},${realUsageTime},\n`;
      });

      // 3. 调用 SaveViewPicker
      const documentViewPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`记得订阅_${new Date().getTime()}.csv`];

      documentViewPicker.save(saveOptions).then((documentSaveResult: Array<string>) => {
        if (documentSaveResult && documentSaveResult.length > 0) {
          const uri = documentSaveResult[0];
          // 写入文件
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          fs.writeSync(file.fd, csvContent);
          fs.closeSync(file);

          this.promptAction.showToast({ message: '导出成功' });
        }
      }).catch((err: BusinessError) => {
        console.error(`Result failed, code is ${err.code}, message is ${err.message}`);
      });

    } catch (e) {
      console.error('Export CSV failed:', e);
      this.promptAction.showToast({ message: '导出失败: ' + JSON.stringify(e) });
    }
  }

  // 导出 JSON (完整数据备份，包含团购券全部字段)
  async handleExportJSON() {
    if (!this.isLoggedIn) {
      if (this.isWide && this.isSplitViewEnabled) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    try {
      const subs = await SubscriptionRepository.getInstance().queryAll();
      if (!subs || subs.length === 0) {
        this.promptAction.showToast({ message: '暂无数据可导出' });
        return;
      }

      // 导出完整数据，复用 HarmonyShareManager 的压缩与图标处理能力

      const ctx = getContext(this) as common.UIAbilityContext;
      const shareManager = HarmonyShareManager.getInstance();
      shareManager.setContext(ctx);

      const exportSubs = await shareManager.prepareSubscriptionsForExport(subs, true);
      const customIcons = await shareManager.prepareIconLibraryForExport();

      const exportData: ExportDataWrapper = {
        version: 2,
        exportTime: new Date().toISOString(),
        timestamp: Date.now(),
        count: subs.length,
        subscriptions: exportSubs,
        customIcons: customIcons
      };

      const jsonContent = JSON.stringify(exportData, null, 2);

      const documentViewPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`记得订阅_备份_${new Date().getTime()}.json`];

      documentViewPicker.save(saveOptions).then((result: Array<string>) => {
        if (result && result.length > 0) {
          const uri = result[0];
          const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          fs.writeSync(file.fd, jsonContent);
          fs.closeSync(file);
          this.promptAction.showToast({ message: 'JSON 备份导出成功' });
        }
      }).catch((err: BusinessError) => {
        console.error(`Export JSON failed: ${err.code}, ${err.message}`);
      });

    } catch (e) {
      console.error('Export JSON failed:', e);
      this.promptAction.showToast({ message: '导出失败: ' + JSON.stringify(e) });
    }
  }

  // 清除自定义图标缓存
  async handleClearCache() {
    if (!this.isLoggedIn) {
      if (this.isWide && this.isSplitViewEnabled) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    this.promptAction.showDialog({
      title: '清除缓存',
      message: '确定要清除所有自定义图标缓存吗？这会将相关订阅的图标重置为默认文字头像。',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '清除', color: '#E60012' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        const iconDir = `${getContext(this).filesDir}/icons`;
        let deletedCount = 0;
        try {
          if (fs.accessSync(iconDir)) {
            const files = fs.listFileSync(iconDir);
            files.forEach(f => {
              try {
                fs.unlinkSync(`${iconDir}/${f}`);
                deletedCount++;
              } catch (e) {}
            });
          }
        } catch (e) {
          hilog.error(DOMAIN, 'SettingsView', `Clear cache failed: ${JSON.stringify(e)}`);
        }

        await SubscriptionRepository.getInstance().clearCustomIcons();
        this.promptAction.showToast({ message: '自定义图标已清理' });

        // 重置所有激活的提醒
        const allSubs = await SubscriptionRepository.getInstance().queryAll();
        for (const sub of allSubs) {
          if (sub.reminderDaysBefore !== undefined && sub.reminderDaysBefore !== null && !sub.isDeleted) {
            await LocalNotificationManager.getInstance().scheduleReminder(sub);
          }
        }
        this.promptAction.showToast({ message: '提醒服务已重同步' });

        // 自动执行修复逻辑
        this.handleRepairIcons();
      }
    });
  }

  // 自动修复/恢复图标
  async handleRepairIcons() {
    if (!this.isLoggedIn) {
      if (this.isWide && this.isSplitViewEnabled) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    this.promptAction.showToast({ message: '开始检查并修复图标...' });
    // 确保本地图标库已加载
    await LocalIconManager.getInstance().init(getContext(this));

    const subs = await SubscriptionRepository.getInstance().queryAll();
    // 寻找需要修复的应用
    const targets = subs.filter(s => !s.icon || (s.icon.length === 1) || (s.icon.startsWith('resource:') && s.icon !== 'resource:petalone'));

    if (targets.length === 0) {
      this.promptAction.showToast({ message: '未发现需要修复的图标' });
      return;
    }

    let repairedCount = 0;
    for (const item of targets) {
      try {
        // 使用本地/混合数据源搜索
        const appInfo = await LocalIconManager.getInstance().searchApp(item.name);

        if (appInfo && appInfo.icon) {
          item.icon = appInfo.icon;
          // 可选：更新分类
          if (appInfo.category && (!item.category || item.category === '其他' || item.category === '未分类')) {
            item.category = appInfo.category;
          }
          await SubscriptionRepository.getInstance().update(item);
          repairedCount++;
        }
      } catch (e) {
        hilog.error(DOMAIN, 'SettingsView', `Repair icon failed for ${item.name}: ${JSON.stringify(e)}`);
      }
    }

    if (repairedCount > 0) {
      this.promptAction.showToast({ message: `成功修复 ${repairedCount} 个图标` });
      // 发送全局事件通知 HomeView 刷新
      getContext(this).eventHub.emit('dataChange');
    } else {
      this.promptAction.showToast({ message: '修复完成，未找到更多匹配图标' });
    }
  }


  // 检查更新
  async checkUpdate() {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.promptAction.showToast({ message: '正在检查更新...' });

    await UpdateManager.getInstance().checkUpdate(context, false);

    // 如果没有检测到新版本，给出一个负向反馈（手动点击时需要）
    if (!AppStorage.get<boolean>('hasNewVersion')) {
      this.promptAction.showToast({ message: '当前已是最新版本' });
    }
  }

  // 拉起卡片管理页面入口
  openWidgetManager() {
    const params: Record<string, Object> = {
      'ohos.extra.param.key.form_dimension': 2,
      'ohos.extra.param.key.form_name': 'widget',
      'ohos.extra.param.key.module_name': 'entry'
    };
    const want: Want = {
      bundleName: "com.xxtstudio.accountDL",
      abilityName: 'EntryFormAbility',
      parameters: params
    };
    try {
      // 点击按钮后调用openFormManager方法，拉起卡片管理页面
      formProvider.openFormManager(want);
    } catch (error) {
      this.promptAction.showToast({ message: (error as BusinessError).message });
      hilog.info(DOMAIN, 'testTag', 'catch error ', 'code:', (error as BusinessError).code, 'message:',
        (error as BusinessError).message);
    }
  }


  @Builder
  SettingHeader(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .margin({ left: 24, bottom: 8, top: 20 })
      .width('100%')
  }

  @Builder SettingBuilder(){
    Stack({ alignContent: Alignment.Top }) {
      // Content List
      Column() {
        List() {
          // 顶部占位,避免被标题栏遮挡
          ListItem() {
            Column().height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.topRectHeight)) // 标题栏高度 + 间距
          }

          // --- Account Section (Profile Card) ---
          ListItem() {
            Row() {
              // Avatar
              Image(this.userAvatar ? this.userAvatar : $r('app.media.foreground'))

                .width(72)
                .height(72)
                .borderRadius(36)
                .margin({ right: 16 })
                .backgroundColor($r('app.color.card_background'))

              Column() {
                if (this.isLoggedIn) {
                  // Logged In State
                  Text(this.userName)
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                    .margin({ bottom: 4 })
                  Text(this.userEmail)
                    .fontSize(14)
                    .fontColor(this.isNewYearTheme ? 'rgba(255, 255, 255, 0.8)' : (this.showVipTheme ? 'rgba(0, 0, 0, 0.6)' : 'rgba(255, 255, 255, 0.8)'))
                } else {
                  // Not Logged In State
                  Text("未登录用户")
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                    .margin({ bottom: 8 })

                  // 点击弹出登录 Sheet
                  Button('点击登录')
                    .type(ButtonType.Capsule)
                    .backgroundColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.brand_color') : Color.White))
                    .width(120)
                    .height(36)
                    .fontSize(14)
                    .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? Color.White : $r('app.color.brand_color')))
                    .borderRadius(18)
                    .visualEffect(new hdsEffect.HdsEffectBuilder()
                      .pointLight({
                        sourceType: this.loginBtnLightSource,
                        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                      })
                      .buildEffect())
                    .scale({ x: this.isLoginBtnPressed ? 0.95 : 1, y: this.isLoginBtnPressed ? 0.95 : 1 })
                    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                    .onTouch((event: TouchEvent) => {
                      if (event.type === TouchType.Down) {
                        if (this.isAnimationEnabled && this.isPointLightEnabled) {
                          this.isLoginBtnPressed = true;
                          this.loginBtnLightSource = hdsEffect.PointLightSourceType.BRIGHT;
                        }
                      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                        this.isLoginBtnPressed = false;
                        this.loginBtnLightSource = hdsEffect.PointLightSourceType.NONE;
                      }
                    })
                    .onClick(() => {
                      if (this.isWide && this.isSplitViewEnabled) {
                        this.pageStack.removeByName('Login');
                        this.pageStack.pushPathByName('Login', null);
                      } else {
                        this.showLoginSheet = true;
                      }
                    })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Center)
              .layoutWeight(1)

              if (this.isLoggedIn) {
                // 退出按钮 - 更醒目的样式
                Button('退出登录')
                  .type(ButtonType.Normal)
                  .backgroundColor('#FFF0F0')
                  .fontColor('#E60012')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .borderRadius(16)
                  .height(32)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.showLogoutSheet = true;
                  })
              }
            }
            .width('100%')
            .height(100)
            .padding({ left: 16, right: 16 })
            .linearGradient(this.isNewYearTheme ? {
              angle: 135,
              colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
            } : (this.showVipTheme ? {
              angle: 135,
              colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
            } : {
              angle: 135,
              colors: [[$r('app.color.brand_gradient_start'), 0.0], [$r('app.color.brand_gradient_end'), 1.0]]
            }))
            .backgroundColor(Color.Transparent)
            .borderRadius(16)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.lightSource1,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.pressCard1 ? 0.98 : 1, y: this.pressCard1 ? 0.98 : 1 })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressCard1 = true;
                  this.lightSource1 = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressCard1 = false;
                this.lightSource1 = hdsEffect.PointLightSourceType.NONE;
              }
            })
          }
          .padding({ left: 24, right: 24, bottom: 12 })
          .opacity(this.animStep1 ? 1 : 0)
          .translate({ y: this.animStep1 ? 0 : 50 })



          // --- General Settings ---
          ListItem() {
            this.SettingHeader("通用")
          }
          .opacity(this.animStep2 ? 1 : 0)
          .translate({ y: this.animStep2 ? 0 : 50 })

          ListItem() {
            Column() {
              // 1. Theme
              Row() {
                Text("颜色模式")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Row() {
                  Text(this.getThemeText())
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 4 })

                  SymbolGlyph($r('sys.symbol.chevron_down'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .bindMenu([
                  {
                    value: '跟随系统',
                    action: () => this.applyTheme(0)
                  },
                  {
                    value: '浅色模式',
                    action: () => this.applyTheme(1)
                  },
                  {
                    value: '深色模式',
                    action: () => this.applyTheme(2)
                  }
                ])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .backgroundColor(Color.Transparent)

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 1.5 Theme Style Selection (Replaces simple toggle)
              Row() {
                Column() {
                  Text("主题风格")
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .fontWeight(FontWeight.Medium)

                  // Dynamic Description
                  Text(this.isNewYearTheme ? "新春限定" : ((this.showVipTheme) ? "黑金主题" : "默认主题"))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Row() {
                  // Small Preview Dot
                  Circle({ width: 16, height: 16 })
                    .fill(this.isNewYearTheme ? $r('app.color.new_year_red_start') : ((this.showVipTheme) ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                    .margin({ right: 8 })

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 16 })
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showThemeSheet = true;
              })


              // 1.5.1 New Year Watermark Toggle




              // 1.5.0.5 Custom Watermark Image (Renamed to "自定义")
              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              Row() {
                Column() {
                  Text("自定义背景")
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.watermarkImage ? "已设置自定义背景图" : "点击设置个性化背景")
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor(Color.Transparent)

              .onClick(() => {
                this.showCustomBgSheet = true;
              })
              .bindSheet($$this.showCustomBgSheet, this.CustomBgSheetBuilder(), {
                detents: [SheetSize.FIT_CONTENT],
                backgroundColor: $r('app.color.card_background'),
                preferType: SheetType.BOTTOM,
                showClose: false
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 1.5.1 New Year Watermark Toggle
              if (this.isNewYearTheme) {
                Row() {
                  Column() {
                    Text("新春背景图案")
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text("叠加显示在新春主题背景上")
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)

                  Blank()

                  Toggle({ type: ToggleType.Switch, isOn: this.isNewYearWatermarkEnabled })
                    .selectedColor($r('app.color.new_year_red_start'))
                    .onChange((value: boolean) => {
                      PreferenceUtil.getInstance().saveNewYearWatermarkEnabled(value);
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor(Color.Transparent)

              }

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 1.5 Split View (Tablet Only)
              if (this.isWide) {
                Row() {
                  Column() {
                    Text("平行视界")
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text("关闭后将强制使用单栏全屏布局")
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)

                  Blank()

                  Toggle({ type: ToggleType.Switch, isOn: this.isSplitViewEnabled })
                    .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                    .onChange((value: boolean) => {
                      PreferenceUtil.getInstance().saveSplitViewEnabled(value);
                    })
                }
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 12
                })
                .backgroundColor(Color.Transparent)

                Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })
              }

              // 1.6 智感握姿 (仅限手机模式)
              if (!this.isWide) {
                Row() {
                  Column() {
                    Text("智感握姿")
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text("根据您的握持手法智能对齐Tab栏")
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)

                  Blank()

                  Toggle({ type: ToggleType.Switch, isOn: this.isSmartGestureEnabled })
                    .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                    .onChange((value: boolean) => {
                      PreferenceUtil.getInstance().saveSmartGestureEnabled(value);
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor(Color.Transparent)

                Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })
              }

              // 1.6.5 HDS Tabs (API 23 Features)
              Row() {
                Column() {
                  Text("HarmonyOS 6.1界面风格")
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text("启用高级材质（会增加功耗）")
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)

                Blank()

                Toggle({ type: ToggleType.Switch, isOn: this.isHdsTabsEnabled })
                  .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                  .onChange((value: boolean) => {
                    PreferenceUtil.getInstance().saveHdsTabsEnabled(value);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor(Color.Transparent)

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 1.7 App Lock (Relocated & Rewritten)
              Row() {
                Text("应用锁")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Row() {
                  Text(this.hasPasswordLock ? "已开启" : "未开启")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 4 })

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                // Enforce Login check
                if (!this.isLoggedIn) {
                  this.promptAction.showToast({ message: '请先登录' });
                  if (this.isWide) {
                    this.pageStack.removeByName('Login');
                    this.pageStack.pushPathByName('Login', null);
                  } else {
                    this.showLoginSheet = true;
                  }
                  return;
                }

                if (this.hasPasswordLock) {
                  this.passwordLockMode = 'verify'; // Verify before showing settings
                } else {
                  // If not locked, open settings panel directly instead of password sheet
                  // User should toggle the switch inside the panel to start setup
                  this.showAppLockSettingsSheet = true;
                  return;
                }
                this.showPasswordLockSheet = true;
              })
              .bindSheet($$this.showAppLockSettingsSheet, this.AppLockSettingsPanel(), {
                detents: [SheetSize.FIT_CONTENT],
                backgroundColor: $r('app.color.card_background'),
                preferType: SheetType.BOTTOM,
                showClose: true // Show close button for settings panel
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 2. Animation
              Row() {
                Text("动画配置")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                Row() {
                  Text(this.isAnimationEnabled ? `${this.animationDuration}ms` : "已关闭")
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ right: 4 })

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.showAnimationSheet = true;
              })
              .bindSheet($$this.showAnimationSheet, this.AnimationSettingsSheetBuilder(), {
                detents: [SheetSize.FIT_CONTENT],
                backgroundColor: $r('app.color.card_background'),
                preferType:SheetType.BOTTOM,
                showClose: false
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 2.5 Dynamic Icon
              if (this.hasDynamicIcons) {
                Row() {
                  Text("切换应用图标")
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([$r('app.color.text_secondary')])
                }
                .width('100%')
                .height(56)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  this.showDynamicIconSheet = true;
                })
                .bindSheet($$this.showDynamicIconSheet, this.DynamicIconSheetBuilder(), {
                  detents: [SheetSize.FIT_CONTENT],
                  backgroundColor: $r('app.color.card_background'),
                  preferType: SheetType.BOTTOM,
                  showClose: false
                })

                Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })
              }

              // 3. AI Config
              Row() {
                Text("图像识别配置")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.pageStack.pushPathByName('AIConfig', null);
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 4. Icon Library
              Row() {
                Text("图标库管理")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.pageStack.pushPathByName('IconLibraryPage', null);
              })
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.lightSource2,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.pressCard2 ? 0.98 : 1, y: this.pressCard2 ? 0.98 : 1 })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressCard2 = true;
                  this.lightSource2 = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressCard2 = false;
                this.lightSource2 = hdsEffect.PointLightSourceType.NONE;
              }
            })
          }
          .padding({ left: 24, right: 24 })
          .opacity(this.animStep2 ? 1 : 0)
          .translate({ y: this.animStep2 ? 0 : 50 })

          // --- Data & Security ---
          ListItem() {
            this.SettingHeader("数据管理")
          }
          .opacity(this.animStep3 ? 1 : 0)
          .translate({ y: this.animStep3 ? 0 : 50 })

          ListItem() {
            Column() {

              // 导出 CSV 按钮
              Row() {
                Text("导出订阅表格 (.csv)")
                  .fontSize(16)
                  .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.upload'))
                  .fontSize(20)
                  .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.handleExportCSV();
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 导出 JSON (备份)
              Row() {
                Text("导出备份文件 (.json)")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.upload'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.handleExportJSON();
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 导入 JSON (恢复)
              Row() {
                Text("导入备份文件 (.json)")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.download'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.handleImportJSON();
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 华为分享按钮
              Row() {
                Text("通过华为分享传输数据")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.share'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.handleSettingsShare();
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

              // 清除缓存按钮
              Row() {
                Text("清除自定义图标缓存")
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width('100%')
              .height(56)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                this.handleClearCache();
              })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.lightSource3,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.pressCard3 ? 0.98 : 1, y: this.pressCard3 ? 0.98 : 1 })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressCard3 = true;
                  this.lightSource3 = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressCard3 = false;
                this.lightSource3 = hdsEffect.PointLightSourceType.NONE;
              }
            })
          }
          .padding({ left: 24, right: 24, bottom: 20 })
          .opacity(this.animStep3 ? 1 : 0)
          .translate({ y: this.animStep3 ? 0 : 50 })

          ListItem() {
            this.SettingHeader("桌面卡片")
          }
          .opacity(this.animStep4 ? 1 : 0)
          .translate({ y: this.animStep4 ? 0 : 50 })

          ListItem() {
            Column() {
              // 添加拉起卡片管理页面按钮 (完全遵循示例样式)
              Button($r('app.string.open_form_manager_button'))
                .width('100%')
                .height(48)
                .linearGradient(this.isNewYearTheme ? {
                  angle: 135,
                  colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]]
                } : (this.showVipTheme ? {
                  angle: 135,
                  colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]]
                } : {
                  angle: 0,
                  colors: [[$r('app.color.brand_color'), 0.0], [$r('app.color.brand_color'), 1.0]]
                }))
                .backgroundColor(Color.Transparent)
                .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                .borderRadius(12)
                .onClick(() => {
                  this.openWidgetManager();
                })
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.widgetBtnLightSource,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isWidgetBtnPressed ? 0.98 : 1, y: this.isWidgetBtnPressed ? 0.98 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isWidgetBtnPressed = true;
                      this.widgetBtnLightSource = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isWidgetBtnPressed = false;
                    this.widgetBtnLightSource = hdsEffect.PointLightSourceType.NONE;
                  }
                })
            }
          }
          .padding({ left: 24, right: 24, bottom: 20 })
          .opacity(this.animStep4 ? 1 : 0)
          .translate({ y: this.animStep4 ? 0 : 50 })


          // --- About ---
          ListItem() {
            this.SettingHeader("关于")
          }
          .opacity(this.animStep5 ? 1 : 0)
          .translate({ y: this.animStep5 ? 0 : 50 })

          ListItem() {
            Column() {
              // 监听版本点击 - 检查更新
              Row() {
                this.SettingItem("当前版本", this.versionName, false, true, this.hasNewVersion)
              }
              .onClick(() => {
                this.checkUpdate();
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 50 })
              // 使用说明
              Row() {
                this.SettingItem("使用说明", "", false, true)
              }
              .onClick(() => {
                this.pageStack.pushPathByName('WebView',
                  new WebViewParam($rawfile('manual.html'), '使用说明'));
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 50 })

              // 用户反馈群
              Row() {
                this.SettingItem("反馈及新版本内测群 (QQ)", "415152704", false, true)
              }
              .onClick(() => {
                try {
                  const systemPasteboard = pasteboard.getSystemPasteboard();
                  const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, "415152704");
                  systemPasteboard.setData(pasteData).then(() => {
                    this.promptAction.showToast({ message: '群号已复制到剪贴板' });
                  });
                } catch (e) {
                  this.promptAction.showToast({ message: '复制失败' });
                }
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 50 })

              // 新增关于应用功能
              // 赞赏作者 (Donate)
              Row() {
                this.SettingItem("赞赏作者", "", false, true)
              }
              .onClick(() => {
                this.showDonationSheet = true;
              })

              Divider().color($r('app.color.divider_color')).padding({ left: 50 })

              // 关于应用
              Row() {
                this.SettingItem("关于应用", "", false, true)
              }
              .onClick(() => {
                if (this.isSplitViewEnabled) {
                  this.pageStack.pushPathByName('About', null);
                } else {
                  this.pageStack.pushPathByName('About', null);
                }
              })
            }
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(16)
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.lightSource5,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.pressCard5 ? 0.98 : 1, y: this.pressCard5 ? 0.98 : 1 })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.pressCard5 = true;
                  this.lightSource5 = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressCard5 = false;
                this.lightSource5 = hdsEffect.PointLightSourceType.NONE;
              }
            })
          }
          .opacity(this.animStep5 ? 1 : 0)
          .translate({ y: this.animStep5 ? 0 : 50 })
          .width('100%')
          .layoutWeight(1)

          .padding({
            left: 24,
            right: 24,
            bottom: 20
          })
          ListItem() {
            Row().height(120) // 底部留白，防止被 Tab 栏遮挡
          }
        }
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      // Spacer for Tab Bar





      Column()
        .bindSheet($$this.showLoginSheet, this.LoginSheetBuilder(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: true,
          preferType: SheetType.BOTTOM,
          title: { title: '登录', subtitle: '使用华为账号登录' },
        })
      Column()
        .bindSheet($$this.showImportSheet, this.ImportSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          preferType: SheetType.BOTTOM,
        })
      Column()
        .bindSheet($$this.showThemeSheet, this.ThemeSelectSheetBuilder(), {
          detents: [SheetSize.MEDIUM],
          backgroundColor: $r('app.color.card_background'),
          preferType: SheetType.BOTTOM,
          showClose: true,
          title: { title: "主题风格" }
        })
      Column()
        .bindSheet($$this.showLogoutSheet, this.LogoutSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.card_background'),
          preferType: SheetType.BOTTOM,
          showClose: false,
          dragBar: false // Disable drag bar for dialog-like experience
        })

      Column()
        .bindSheet($$this.showDonationSheet, this.DonationSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          backgroundColor: $r('app.color.card_background'),
          preferType: SheetType.BOTTOM,
          showClose: true,
          title: { title: "赞赏作者" }
        })
      Column()
        .bindSheet($$this.showWatermarkEditSheet, this.WatermarkEditSheetBuilder(), {
          detents: [SheetSize.LARGE],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          dragBar: false,
          preferType: SheetType.BOTTOM,
        })
      Column()
        .bindSheet($$this.showPasswordLockSheet, this.PasswordLockBuilder(), {
          detents: [SheetSize.FIT_CONTENT], // Use stable size to prevent jump
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          preferType: SheetType.BOTTOM,
        })
      Column()
        .bindSheet($$this.showVerifySheet, this.VerifySheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: false,
          backgroundColor: Color.Transparent,
          preferType: SheetType.BOTTOM,
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  build() {
    HdsNavDestination() {
      this.SettingBuilder()
    }
    .hideBackButton(true)
    .hideTitleBar(false)
    .backgroundColor(Color.Transparent)
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: '我的' },
        menu: { value: [] }
      },
      style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ? {
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
      } : undefined
    })
  }

  @Builder
  LoginSheetBuilder() {
    LoginSheet({
      isShow: this.showLoginSheet,
      onSuccess: () => { this.showLoginSheet = false },
      onClose: () => { this.showLoginSheet = false }
    })
  }

  @Builder
  SettingItem(title: string, value: string, isDestructive: boolean = false, showArrow: boolean = false, showRedDot: boolean = false) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor(isDestructive ? Color.Red : $r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      // Red Dot
      if (showRedDot) {
        Circle({ width: 8, height: 8 })
          .fill(Color.Red)
          .margin({ right: 8 })
      }

      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ right: 8 })

      if (showArrow || (value === "" && !isDestructive)) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  SettingSwitch(title: string, isOn: boolean) {
    Row() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? '#D4AF37' : $r('app.color.brand_color')))
        .onChange((value: boolean) => {
          if (title === "显示动画效果") {
            PreferenceUtil.getInstance().saveAnimationEnabled(value);
          }
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }
  getThemeText(): string {
    switch (this.themeMode) {
      case 1: return '浅色模式';
      case 2: return '深色模式';
      default: return '跟随系统';
    }
  }

  applyTheme(mode: number) {
    this.themeMode = mode;
    PreferenceUtil.getInstance().saveTheme(this.themeMode);

    let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (this.themeMode === 1) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (this.themeMode === 2) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }

    // Apply immediately
    getContext(this).getApplicationContext().setColorMode(colorMode);
  }




  async handleImportJSON() {
    if (!this.isLoggedIn) {
      if (this.isWide) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.fileSuffixFilters = ['.json'];
      documentSelectOptions.maxSelectNumber = 1;

      const documentViewPicker = new picker.DocumentViewPicker();
      const documentSelectResult = await documentViewPicker.select(documentSelectOptions);

      if (documentSelectResult && documentSelectResult.length > 0) {
        const uri = documentSelectResult[0];
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);

        try {
          // Read file robustly
          let buf = new ArrayBuffer(1024 * 1024 * 2); // Max 2MB
          let readLen = fs.readSync(file.fd, buf);
          const text = buffer.from(buf.slice(0, readLen)).toString('utf-8');

          if (text) {
            const json = JSON.parse(text) as Record<string, Object> | SubscriptionModel[];
            let subs: SubscriptionModel[] = [];

            if (Array.isArray(json)) {
              subs = json as SubscriptionModel[];
            } else if (json && (json as Record<string, Object>).subscriptions) {
              subs = (json as Record<string, Object>).subscriptions as SubscriptionModel[];
            } else if (json && (json as Record<string, Object>).data) {
              // Support new export format
              subs = (json as Record<string, Object>).data as SubscriptionModel[];
            }

            if (subs && subs.length > 0) {
              this.importData = subs;
              this.showImportSheet = true;
            } else {
              this.promptAction.showToast({ message: '未发现有效的订阅数据' });
            }
          }
        } finally {
          fs.closeSync(file);
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, 'SettingsView', `Import JSON failed: ${JSON.stringify(err)}`);
      this.promptAction.showToast({ message: '导入失败，请检查文件格式' });
    }
  }

  async handleSettingsShare() {
    if (!this.isLoggedIn) {
      if (this.isWide) {
        this.pageStack.removeByName('Login');
        this.pageStack.pushPathByName('Login', null);
      } else {
        this.showLoginSheet = true;
      }
      return;
    }
    HarmonyShareManager.getInstance().activeShare();
  }

  @Builder ImportSheetBuilder() {
    ImportSheet({
      isShow: $showImportSheet,
      importData: $importData,
      onCancel: () => {
        this.showImportSheet = false;
        this.importData = [];
      },
      onImport: async () => {
        const loading = this.promptAction.showToast({ message: '正在恢复数据...' });
        let count = 0;
        // Use Repository import logic or manual update
        // Using manual update to share logic with HomeView and better control
        try {
          // Lazy import to avoid circular dependency issues if any


          for (const item of this.importData) {
            const resultId = await SubscriptionRepository.getInstance().upsert(item); // Safe Upsert

            // 自动同步系统提醒
            if (resultId > 0 && item.reminderDaysBefore !== undefined && item.id) {
              await LocalNotificationManager.getInstance().scheduleReminder(item);
            }
            count++;
          }
          this.promptAction.showToast({ message: `成功恢复 ${count} 条数据` });
          this.showImportSheet = false;
          this.importData = [];
          // Notify changes
          getContext(this).eventHub.emit('dataChange');
        } catch (e) {
          this.promptAction.showToast({ message: '部分数据恢复失败' });
          hilog.error(DOMAIN, 'SettingsView', `Import Error: ${JSON.stringify(e)}`);
        }
      }
    })
  }
  @State showThemeSheet: boolean = false;

  // ...

  @Builder ThemeSelectSheetBuilder() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          // Default Theme
          ThemeOptionItem({
            title: "默认主题",
            desc: "经典蓝白配色，清爽简洁",
            themeId: 'default',
            currentThemeId: this.activeThemeId,
            onSelect: () => {
              this.updateTheme('default');
            }
          })

          // Black Gold Theme
          ThemeOptionItem({
            title: "黑金主题",
            desc: "尊贵黑金配色，奢华质感",
            themeId: 'vip',
            currentThemeId: this.activeThemeId,
            onSelect: () => {
              this.updateTheme('vip');
            }
          })

          // New Year Theme
          ThemeOptionItem({
            title: "新春限定",
            desc: "红红火火，喜迎新春",
            themeId: 'new_year',
            currentThemeId: this.activeThemeId,
            onSelect: () => {
              this.updateTheme('new_year');
            }
          })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
      .align(Alignment.Top) // Ensure Scroll content aligns top
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start) // Fix centering issue
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder WatermarkEditSheetBuilder() {
    Column() {
      // Use existing ImageCropSheet but modify it slightly or wrapper it
      // Actually, since ImageCropSheet handles everything including UI, we can just use it.
      // But we need to add Opacity slider...
      // Strategy: Use ImageCropSheet for the "Crop" part, and add Opacity slider below?
      // Or modify ImageCropSheet to include custom controls?
      // User asked to use the "same component". Let's wrap ImageCropSheet and overlay Opacity slider.

      Stack({ alignContent: Alignment.Bottom }) {
        ImageCropSheet({
          sourceUri: this.tempWatermarkImage,
          cropRatio: this.getScreenAspectRatio(), // Use calculated screen ratio
          imageOpacity: this.tempWatermarkOpacity,
          title: '设置背景',
          onComplete: (uri: string) => {
            this.handleSaveWatermark(uri);
          },
          onCancel: () => {
            this.showWatermarkEditSheet = false;
          }
        })

        // Overlay Opacity Slider
        Column() {
          Row() {
            Text("水印透明度")
              .fontSize(14)
              .fontColor(Color.White)
              .shadow({ radius: 2, color: 'rgba(0,0,0,0.5)', offsetY: 1 })
            Blank()
            Text(`${Math.round(this.tempWatermarkOpacity * 100)}%`)
              .fontSize(14)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .shadow({ radius: 2, color: 'rgba(0,0,0,0.5)', offsetY: 1 })
          }
          .width('100%')
          .padding({ left: 32, right: 32, top: 16 })

          Slider({
            value: this.tempWatermarkOpacity * 100,
            min: 0,
            max: 100,
            style: SliderStyle.OutSet
          })
            .blockColor($r('app.color.brand_color'))
            .trackColor('rgba(255,255,255,0.3)')
            .selectedColor($r('app.color.brand_color'))
            .showSteps(false)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.tempWatermarkOpacity = value / 100;
            })
            .width('100%')
            .padding({ left: 32, right: 32, bottom: 84 }) // Bottom padding to clear crop buttons
        }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent) // Allow touches to pass through empty areas? No, Slider needs touch.
        // Problem: If I overlay, I might block crop touches.
        // Better approach: Put ImageCropSheet in a Column, and put Slider below/above it.
        // But ImageCropSheet takes full height.
      }
    }
    .width('100%')
    .height('100%')
  }

  getScreenAspectRatio(): number {
    // User requested 16:9 (interpreted as 9:16 for portrait phone background)
    return 9 / 16;
  }

  @Builder CustomBgSheetBuilder() {
    Column() {
      // Handle Bar
      Row()
        .width(40)
        .height(4)
        .backgroundColor($r('app.color.text_secondary'))
        .opacity(0.2)
        .borderRadius(2)
        .margin({ top: 8, bottom: 20 })

      Text("自定义背景")
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 24 })
        .width('100%')
        .textAlign(TextAlign.Start)

      // Background Preview (If exists)
      if (this.watermarkImage) {
        Column() {
          Image(this.watermarkImage)
            .width('100%')
            .aspectRatio(9/16)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)
            .opacity(this.watermarkOpacity)

        }
        .width('40%')
        .margin({ bottom: 24 })
        .shadow({ radius: 10, color: 'rgba(0,0,0,0.1)', offsetY: 4 })
      }

      // Opacity Control
      Column() {
        Row() {
          Text("背景不透明度")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Blank()

          Text(`${Math.round(this.watermarkOpacity * 100)}%`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .margin({ bottom: 12 })

        Slider({
          value: this.watermarkOpacity * 100,
          min: 0,
          max: 100,
          style: SliderStyle.OutSet
        })
          .blockColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .trackColor($r('app.color.divider_color'))
          .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .onChange((value: number, mode: SliderChangeMode) => {
            this.watermarkOpacity = value / 100;
            if (mode === SliderChangeMode.End) {
              PreferenceUtil.getInstance().saveWatermarkOpacity(this.watermarkOpacity);
            }
          })
      }
      .width('100%')
      .margin({ bottom: 32 })

      // Action Buttons
      Row({ space: 12 }) {
        if (this.watermarkImage) {
          Button("清除背景")
            .layoutWeight(1)
            .height(44)
            .type(ButtonType.Normal)
            .borderRadius(12)
            .backgroundColor('#1AFF0000')
            .fontColor('#FFFF4444')
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: this.clearCustomLight,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .scale({ x: this.isClearCustomPressed ? 0.98 : 1, y: this.isClearCustomPressed ? 0.98 : 1 })
            .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                if (this.isAnimationEnabled && this.isPointLightEnabled) {
                  this.isClearCustomPressed = true;
                  this.clearCustomLight = hdsEffect.PointLightSourceType.BRIGHT;
                }
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isClearCustomPressed = false;
                this.clearCustomLight = hdsEffect.PointLightSourceType.NONE;
              }
            })
            .onClick(() => {
              this.handleClearWatermarkImage();
            })
        }

        Button(this.watermarkImage ? "更换图片" : "选择图片")
          .layoutWeight(2)
          .height(44)
          .type(ButtonType.Normal)
          .borderRadius(12)
          .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: this.changeCustomLight,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .scale({ x: this.isChangeCustomPressed ? 0.98 : 1, y: this.isChangeCustomPressed ? 0.98 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              if (this.isAnimationEnabled && this.isPointLightEnabled) {
                this.isChangeCustomPressed = true;
                this.changeCustomLight = hdsEffect.PointLightSourceType.BRIGHT;
              }
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isChangeCustomPressed = false;
              this.changeCustomLight = hdsEffect.PointLightSourceType.NONE;
            }
          })
          .onClick(() => {
            // this.showCustomBgSheet = false;
            this.handleSelectWatermarkImage();
          })
      }
      .width('100%')

    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 40 })
    .backgroundColor($r('app.color.card_background'))
  }

  updateTheme(id: string) {
    this.activeThemeId = id;
    // Single source of truth via PreferenceUtil
    PreferenceUtil.getInstance().saveThemeId(id);
  }


  @State showLogoutSheet: boolean = false;
  @State showDonationSheet: boolean = false;

  @Builder LogoutSheetBuilder() {
    Column() {
      // Title
      Text('退出登录')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 24, bottom: 8 })

      // Warning Section
      Row() {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(24)
          .fontColor(['#E60012'])
          .margin({ right: 12 })

        Column() {
          Text('重要提示')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 4 })
          Text('退出登录后，您的账号信息和本地订阅数据都将被彻底清除。')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(20)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('rgba(230, 0, 18, 0.1)') // Use semi-transparent red for Dark Mode compatibility
      .borderRadius(12)
      .margin({ top: 12, bottom: 8 })

      // Suggestion Section
      Row() {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(24)
          .fontColor([$r('app.color.brand_color')])
          .margin({ right: 12 })

        Column() {
          Text('建议操作')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 4 })
          Text('1. 前往"数据管理"导出备份文件\n2. 保存备份文件到安全位置\n3. 确认备份完成后再退出')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(20)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider_color') })
      .borderRadius(12)
      .margin({ bottom: 24 })

      // Buttons
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('app.color.page_background'))
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.showLogoutSheet = false;
          })

        Button('确认退出')
          .layoutWeight(1)
          .backgroundColor('#E60012')
          .fontColor(Color.White)
          .onClick(() => {
            this.showLogoutSheet = false;
            import('../utils/AccountMonitor').then(m => {
              m.AccountMonitor.getInstance().handleLogout();
            });
          })
      }
      .width('100%')
      .margin({ bottom: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
  }

  async saveQRCode() {
    // Keep legacy picker method as fallback if needed, but not used in UI now
    try {
      const context = getContext(this);
      const fileData = await context.resourceManager.getRawFileContent('reward_qrcode.png');
      const buffer = fileData.buffer;

      const photoSaveOptions = new picker.PhotoSaveOptions();
      photoSaveOptions.newFileNames = [`donate_qrcode_${new Date().getTime()}.png`];

      const photoViewPicker = new picker.PhotoViewPicker();
      const photoSaveResult = await photoViewPicker.save(photoSaveOptions);

      if (photoSaveResult && photoSaveResult.length > 0) {
        const uri = photoSaveResult[0];
        const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, buffer);
        fs.closeSync(file);

        this.promptAction.showToast({ message: '赞赏码已保存' });
      }
    } catch (e) {
      hilog.error(0x0000, 'Donation', `Failed to save QR code: ${JSON.stringify(e)}`);
    }
  }

  // New SaveButton Handler
  async handleSaveQRCode(result: SaveButtonOnClickResult, error?: BusinessError) {
    if (result === SaveButtonOnClickResult.SUCCESS) {
      try {
        const context = getContext(this);
        let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
        // Create asset in gallery
        let uri = await phAccessHelper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png', {
          title: `reward_qrcode_${Date.now()}`
        });

        const fileData = await context.resourceManager.getRawFileContent('reward_qrcode.png');
        let file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, fileData.buffer);
        fs.closeSync(file);

        this.promptAction.showToast({ message: '赞赏码已保存到相册' });
      } catch (err) {
        hilog.error(0x0000, 'Donation', `SaveButton Error: ${JSON.stringify(err)}`);
        this.promptAction.showToast({ message: '保存失败，请检查设置' });
      }
    } else if (error) {
      hilog.error(0x0000, 'Donation', `SaveButton Result Error: ${JSON.stringify(error)}`);
    }
  }

  @Builder DonationSheetBuilder() {
    Column() {
      Image($r('app.media.foreground'))
        .width(64)
        .height(64)
        .borderRadius(16)
        .margin({ top: 32, bottom: 16 })

      Text('感谢支持')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      Text('如果您觉得《记得订阅》好用，\n欢迎请作者喝杯咖啡 ☕️')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(20)
        .margin({ bottom: 24 })

      // 赞赏码区域
      Column() {
        Image($rawfile('reward_qrcode.png'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      }
      .width(200)
      .height(200)
      .borderRadius(16)
      .clip(true)
      .margin({ bottom: 12 })

      Column() {
        SaveButton({
          icon: SaveIconStyle.FULL_FILLED,
          text: SaveDescription.SAVE_IMAGE,
          buttonType: ButtonType.Capsule
        })
          .width(140)
          .height(32)
          .fontSize(13)
          .backgroundColor(this.isNewYearTheme ? '#1AFFD700' : (this.showVipTheme ? '#1AD4AF37' : '#1A007AFF'))
          .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? '#D4AF37' : $r('app.color.brand_color')))
          .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
            this.handleSaveQRCode(result);
          })
      }
      .margin({ bottom: 20 })

      Text('免责声明：赞赏纯属自愿行为，非购买商品或服务。\n由于虚拟产品的特殊性，赞赏后不支持退款。')
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .opacity(0.6)
        .lineHeight(14)
        .margin({ bottom: 32, left: 32, right: 32 })
    }
    .width('100%')
    .borderRadius(24)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  AppLockSettingsPanel() {
    Column() {
      // Header
      Row() {
        // Handle bar
        Column()
          .width(36)
          .height(4)
          .backgroundColor($r('app.color.divider_color'))
          .borderRadius(2)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 20 })

      Text("应用锁管理")
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 16, bottom: 20 })

      Column() {
        // 1. Master Switch
        Row() {
          Text("开启应用锁")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.hasPasswordLock })
            .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
            .onChange((isOn: boolean) => {
              if (!isOn) {
                // Turn OFF
                this.hasPasswordLock = false;
                AppStorage.setOrCreate('hasAppLock', false);
                PreferenceUtil.getInstance().saveAppLockPassword('');
                // Also disable biometrics
                this.isFaceEnabled = false;
                this.isFingerprintEnabled = false;
                PreferenceUtil.getInstance().saveAppLockFace(false);
                PreferenceUtil.getInstance().saveAppLockFingerprint(false);
              } else {
                // Require Login to Enable
                if (!this.isLoggedIn) {
                  this.hasPasswordLock = false; // Revert toggle
                  this.promptAction.showToast({ message: '请先登录' });
                  if (this.isWide) {
                    this.pageStack.removeByName('Login');
                    this.pageStack.pushPathByName('Login', null);
                  } else {
                    this.showLoginSheet = true;
                  }
                  return;
                }

                this.passwordLockMode = 'set';
                this.showPasswordLockSheet = true;
                this.showAppLockSettingsSheet = false; // Close settings to show lock sheet
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })


        // 2. Biometric Options
        if (this.hasPasswordLock) {
          if (this.supportFace) {
            Row() {
              Text("使用人脸解锁")
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.isFaceEnabled })
                .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .onChange((isOn: boolean) => {
                  this.isFaceEnabled = isOn; // Optimistic update
                  if (isOn) {
                    // Verify to Enable
                    this.biometricCheckTypes = [userAuth.UserAuthType.FACE];
                    this.verifyTarget = 'face';
                    this.showVerifySheet = true;
                  } else {
                    // Turn OFF immediately
                    this.isFaceEnabled = false;
                    PreferenceUtil.getInstance().saveAppLockFace(false);
                    this.promptAction.showToast({ message: '已关闭人脸解锁' });
                  }
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }

          if (this.supportFingerprint) {
            Row() {
              Text("使用指纹解锁")
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.isFingerprintEnabled })
                .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .onChange((isOn: boolean) => {
                  this.isFingerprintEnabled = isOn; // Optimistic update
                  if (isOn) {
                    // Verify to Enable
                    this.biometricCheckTypes = [userAuth.UserAuthType.FINGERPRINT];
                    this.verifyTarget = 'fingerprint';
                    this.showVerifySheet = true;
                  } else {
                    // Turn OFF immediately
                    this.isFingerprintEnabled = false;
                    PreferenceUtil.getInstance().saveAppLockFingerprint(false);
                    this.promptAction.showToast({ message: '已关闭指纹解锁' });
                  }
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }

          // Divider
          Divider().color($r('app.color.divider_color')).padding({ left: 16, right: 16 })

          // 3. Change Password
          Row() {
            Text("修改密码")
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.passwordLockMode = 'change';
            this.showPasswordLockSheet = true;
            // Keep settings sheet open
          })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('auto') // Ensure it wraps content
    .backgroundColor($r('app.color.card_background')) // Use card background
    .padding({ bottom: 32 }) // Safe area
  }

  @Builder
  PasswordLockBuilder() {
    PasswordLockPage({
      mode: this.passwordLockMode,
      checkBiometric: false,
      checkTypes: [],
      onSuccess: () => {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.showPasswordLockSheet = false;
        });

        if (this.passwordLockMode === 'set') {
          this.hasPasswordLock = true;
          AppStorage.setOrCreate('hasAppLock', true);
          this.showAppLockSettingsSheet = true;
        } else if (this.passwordLockMode === 'verify') {
          this.showAppLockSettingsSheet = true;
        } else if (this.passwordLockMode === 'disable') {
          PreferenceUtil.getInstance().saveAppLockPassword('');
          this.hasPasswordLock = false;
          AppStorage.setOrCreate('hasAppLock', false);
          this.promptAction.showToast({ message: '应用锁已关闭' });
          this.isFaceEnabled = false;
          this.isFingerprintEnabled = false;
          PreferenceUtil.getInstance().saveAppLockFace(false);
          PreferenceUtil.getInstance().saveAppLockFingerprint(false);
        }

        setTimeout(() => {
          this.checkPasswordLockStatus();
        }, 300);
      },
      onCancel: () => {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.showPasswordLockSheet = false;
        });
        if (this.passwordLockMode === 'set' && !this.hasPasswordLock) {
          this.hasPasswordLock = false;
        }
      }
    })
  }

  @Builder
  VerifySheetBuilder() {
    PasswordLockPage({
      mode: 'verify',
      checkBiometric: this.biometricCheckTypes.length > 0,
      checkTypes: this.biometricCheckTypes,
      onSuccess: () => {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.showVerifySheet = false;
        });

        setTimeout(() => {
          if (this.verifyTarget === 'face') {
            this.isFaceEnabled = true;
            PreferenceUtil.getInstance().saveAppLockFace(true);
            if (this.isFingerprintEnabled) {
              this.isFingerprintEnabled = false;
              PreferenceUtil.getInstance().saveAppLockFingerprint(false);
            }
            this.promptAction.showToast({ message: '开启成功' });
          } else if (this.verifyTarget === 'fingerprint') {
            this.isFingerprintEnabled = true;
            PreferenceUtil.getInstance().saveAppLockFingerprint(true);
            if (this.isFaceEnabled) {
              this.isFaceEnabled = false;
              PreferenceUtil.getInstance().saveAppLockFace(false);
            }
            this.promptAction.showToast({ message: '开启成功' });
          }

          this.verifyTarget = '';
          this.biometricCheckTypes = [];
        }, 600);
      },
      onCancel: () => {
        animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.showVerifySheet = false;
        });

        setTimeout(() => {
          if (this.verifyTarget === 'face') this.isFaceEnabled = false;
          if (this.verifyTarget === 'fingerprint') this.isFingerprintEnabled = false;
          this.verifyTarget = '';
          this.biometricCheckTypes = [];
        }, 600);
      }
    })
  }
}


@Component
struct ThemeOptionItem {
  @Prop title: string = '';
  @Prop desc: string = '';
  @Prop themeId: string = 'default';
  @Prop currentThemeId: string = 'default';
  onSelect: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // Preview Card (Pass themeId to preview)
        ThemePreviewCard({ themeId: this.themeId })
          .margin({ bottom: 12 })

        Column() {
          Text(this.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeId === this.currentThemeId ? this.getThemeColor() : $r('app.color.text_primary'))

          Text(this.desc)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(16)
      // Card Style
      .backgroundColor(this.themeId === this.currentThemeId ? this.getThemeBgColor() : $r('app.color.card_background')) // Contrast BG for unselected
      .borderRadius(16.0)
      .borderWidth(2.0)
      .borderColor(this.themeId === this.currentThemeId ? this.getThemeColor() : Color.Transparent)
      .animation({ duration: 200 })

      // Checkmark Overlay
      if (this.themeId === this.currentThemeId) {
        Row() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([Color.White])
            .fontWeight(FontWeight.Bold)
        }
        .width(24)
        .height(24)
        .borderRadius({ topLeft: 12, bottomRight: 12 }) // Rounded corner to match card
        .backgroundColor(this.getThemeColor())
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.themeId !== this.currentThemeId) {
        this.onSelect();
      }
    })
  }

  getThemeColor(): ResourceColor {
    if (this.themeId === 'new_year') return $r('app.color.new_year_red_start');
    if (this.themeId === 'vip') return $r('app.color.vip_gold');
    return $r('app.color.brand_color');
  }

  getThemeBgColor(): ResourceColor {
    if (this.themeId === 'new_year') return '#0AD93025';
    if (this.themeId === 'vip') return '#1A302008';
    return '#0A007AFF';
  }
}

@Component
struct ThemePreviewCard {
  @Prop themeId: string = 'default';

  getShadowColor(): ResourceColor {
    if (this.themeId === 'vip') return '#40E6C07B';
    if (this.themeId === 'new_year') return '#40D93025';
    return '#40007AFF';
  }

  build() {
    Column() {
      Row() {
        Text("本月预估支出")
          .fontColor(this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? $r('app.color.new_year_text_on_red') : $r('app.color.vip_text_on_gold')))
          .fontSize(12)
        Blank()
        Text("12 个订阅")
          .fontColor(this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? $r('app.color.new_year_text_on_red') : $r('app.color.vip_text_on_gold')))
          .fontSize(10)
          .backgroundColor(this.themeId === 'default' ? '#33FFFFFF' : (this.themeId === 'new_year' ? '#33FFFFFF' : '#1A302008'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10.0)
      }
      .width('100%').margin({ bottom: 8 })

      Row({ space: 2 }) {
        Text('¥')
          .fontColor(this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? '#FFD700' : $r('app.color.vip_text_on_gold')))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 4 })
        Text("1,280.00")
          .fontColor(this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? '#FFD700' : $r('app.color.vip_text_on_gold')))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
      }

      // Sync Status Mock
      Row() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(10)
          .fontColor([this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? $r('app.color.new_year_text_on_red') : $r('app.color.vip_text_on_gold'))])
        Text(" 碰一碰/隔空传送 已就绪")
          .fontSize(9)
          .fontColor(this.themeId === 'default' ? Color.White : (this.themeId === 'new_year' ? $r('app.color.new_year_text_on_red') : $r('app.color.vip_text_on_gold')))
          .opacity(0.8)
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.themeId === 'default' ? '#22FFFFFF' : (this.themeId === 'new_year' ? '#22FFFFFF' : '#40302008'))
      .borderRadius(8.0)
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(20.0)
    .linearGradient(this.themeId === 'vip' ? {
      angle: 135,
      colors: [[$r('app.color.vip_gold_start'), 0.0], [$r('app.color.vip_gold_end'), 1.0]] as [ResourceColor, number][]
    } : (this.themeId === 'new_year' ? {
      angle: 135,
      colors: [[$r('app.color.new_year_red_start'), 0.0], [$r('app.color.new_year_red_end'), 1.0]] as [ResourceColor, number][]
    } : {
      angle: 135,
      colors: [[$r('app.color.brand_gradient_start'), 0.0], [$r('app.color.brand_gradient_end'), 1.0]] as [ResourceColor, number][]
    }))
    .shadow({ radius: 10.0, color: this.getShadowColor(), offsetY: 4.0 })
  }
}
