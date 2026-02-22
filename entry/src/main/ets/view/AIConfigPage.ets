import { PromptAction, curves, LengthMetrics } from '@kit.ArkUI';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { WebViewParam } from './WebViewPage';
import { http } from '@kit.NetworkKit';
import { ZHIPU_API_BASE_URL } from '../utils/ApiConfig';
import { hdsEffect,   HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { BackgroundWatermark } from './BackgroundWatermark';
import { deviceInfo } from '@kit.BasicServicesKit';

@Builder
export function AIConfigPageBuilder() {
  AIConfigPage()
}

const TITLE_BAR_HEIGHT_MINI: number = 46;

@Component
export struct AIConfigPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State apiKey: string = '';
  @State isAIEnabled: boolean = true;
  @State isTesting: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('isVip') isVip: boolean = false; // VIP 主题状态
  @StorageLink('showVipTheme') showVipTheme: boolean = true; // 会员配色开关
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  async aboutToAppear() {
    this.apiKey = await PreferenceUtil.getInstance().getAIKey();
    this.isAIEnabled = await PreferenceUtil.getInstance().isAIEnabled();
    this.triggerAnimations();
  }

  // Animation States
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationResponse') animationResponse: number = 0.35;
  @StorageLink('animationDamping') animationDamping: number = 0.75;
  @State animStep1: boolean = false;
  @State animStep2: boolean = false;
  @State animStep3: boolean = false;
  @State animStep4: boolean = false;
  @State animStep5: boolean = false;

  // Interaction State
  @State isTestPressed: boolean = false;
  @State testLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isSavePressed: boolean = false;
  @State saveLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isRegisterPressed: boolean = false;
  @State registerLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isBackPressed: boolean = false;
  @State backLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  @State isSwitchPressed: boolean = false;
  @State isInputFocused: boolean = false;

  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  triggerAnimations() {
       if (this.isAnimationEnabled) {
          const duration = this.animationDuration;
          const interval = duration * 0.15;
          const curve = curves.springMotion(this.animationResponse, this.animationDamping);
          setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep1 = true }) }, 0);
          setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep2 = true }) }, interval);
          setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep3 = true }) }, interval * 2);
          setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep4 = true }) }, interval * 3);
          setTimeout(() => { animateTo({ duration: duration, curve: curve }, () => { this.animStep5 = true }) }, interval * 4);
      } else {
          this.animStep1 = true;
          this.animStep2 = true;
          this.animStep3 = true;
          this.animStep4 = true;
          this.animStep5 = true;
      }
  }

  async testConnection() {
    if (!this.apiKey) {
      this.promptAction.showToast({ message: '请先输入 API Key' });
      return;
    }

    this.isTesting = true;
    const httpRequest = http.createHttp();
    try {
      // 智谱 AI 验证接口 (使用 chat/completions 接口测试连通性)
      const url = `${ZHIPU_API_BASE_URL}/chat/completions`;
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        },
        extraData: {
          model: 'glm-4-flash',
          messages: [{ role: 'user', content: 'Connection test' }],
          max_tokens: 10
        }
      });

      if (response.responseCode === 200) {
        this.promptAction.showToast({ message: '连接成功！API Key 有效' });
      } else if (response.responseCode === 401) {
        this.promptAction.showToast({ message: '验证失败：API Key 错误' });
      } else {
        this.promptAction.showToast({ message: `连接异常: ${response.responseCode}` });
      }
    } catch (err) {
      this.promptAction.showToast({ message: '网络异常或 API Key 无效' });
    } finally {
      httpRequest.destroy();
      this.isTesting = false;
    }
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder AIBuilder(){
    Stack({ alignContent: Alignment.Top }) {
      // Universal Background Watermark
      BackgroundWatermark()
        .zIndex(0)

      Scroll() {

        Column({ space: 24 }) {
          Column() {
            Blank()
              .height(TITLE_BAR_HEIGHT_MINI + this.getUIContext().px2vp(this.statusBarHeight))

          }

          // 合规使用说明
          Column() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontColor(['#FA5A5A'])
                .fontSize(20)
              Text("合规使用说明")
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FA5A5A')
            }
            .width('100%')
            .margin({ bottom: 8 })

            Text("本应用为智谱 GLM-4V-FLASH 图像理解服务的客户端工具。根据监管要求，您填写的 API Key 必须是您本人在智谱 AI 开放平台经过实名认证后获取的有效凭证。\n本应用仅作技术透传，不存储您的身份信息。")
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(22)
          }
          .padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .width('100%')
          // --- Section 1: API Key Config ---
          Column({ space: 16 }) {


            Column() {
              TextInput({ placeholder: '请输入您的 API Key', text: this.apiKey })
                .height(56)
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.page_background'))
                .borderRadius(16)
                .onChange((val) => this.apiKey = val)
                .showPasswordIcon(true)
                .type(InputType.Password)
                .onFocus(() => {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isInputFocused = true;
                  }
                })
                .onBlur(() => {
                  this.isInputFocused = false;
                })
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 12 })
                .width('100%')

              // AI Enable Switch
              Row() {
                Text("启用 AI 智能识别")
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.isAIEnabled })
                  .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                  .onChange(async (isOn: boolean) => {
                    this.isAIEnabled = isOn;
                    await PreferenceUtil.getInstance().saveAIEnabled(isOn);
                  })
              }
              .width('100%')
              .padding({ top: 12, bottom: 4 })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isSwitchPressed = true;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isSwitchPressed = false;
                }
              })
            }
            .padding(20)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(20)
            .shadow({ radius: 20, color: '#0D000000', offsetX: 0, offsetY: 8 })
            .visualEffect(new hdsEffect.HdsEffectBuilder()
              .pointLight({
                sourceType: (this.isInputFocused || this.isSwitchPressed) ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
              })
              .buildEffect())
            .opacity(this.animStep1 ? 1 : 0)
            .translate({ y: this.animStep1 ? 0 : 20 })

            Row({ space: 12 }) {
              Button(this.isTesting ? "正在连通..." : "测试连接")
                .layoutWeight(1)
                .height(48)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .backgroundColor($r('app.color.page_background'))
                .fontColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .borderRadius(14)
                .border({ width: 1, color: '#1A0A59F7' })
                .enabled(!this.isTesting)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.testLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isTestPressed ? 0.95 : 1, y: this.isTestPressed ? 0.95 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) })
                .onTouch((event: TouchEvent) => {
                  if (!this.isTesting) {
                    if (event.type === TouchType.Down) {
                      if (this.isAnimationEnabled && this.isPointLightEnabled) {
                        this.isTestPressed = true;
                        this.testLight = hdsEffect.PointLightSourceType.BRIGHT;
                      }
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.isTestPressed = false;
                      this.testLight = hdsEffect.PointLightSourceType.NONE;
                    }
                  }
                })
                .onClick(() => this.testConnection())

              Button("确认并保存")
                .layoutWeight(1)
                .height(48)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
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
                .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                .borderRadius(14)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.saveLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isSavePressed ? 0.95 : 1, y: this.isSavePressed ? 0.95 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isSavePressed = true;
                      this.saveLight = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isSavePressed = false;
                    this.saveLight = hdsEffect.PointLightSourceType.NONE;
                  }
                })
                .onClick(async () => {
                  await PreferenceUtil.getInstance().saveAIKey(this.apiKey);
                  this.promptAction.showToast({ message: '配置已更新' });
                })
            }
            .width('100%')
            .margin({ top: 4 })
            .opacity(this.animStep1 ? 1 : 0)
            .translate({ y: this.animStep1 ? 0 : 20 })
          }

          // --- Section 2: Guidance ---
          Column({ space: 16 }) {
            Column({ space: 16 }) {
              Text("获取指引")
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              // --- Registration Entry ---
              Button("注册并获取 API Key")
                .height(44)
                .width('100%')
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
                .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
                .borderRadius(12)
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: this.registerLight,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({ x: this.isRegisterPressed ? 0.98 : 1, y: this.isRegisterPressed ? 0.98 : 1 })
                .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    if (this.isAnimationEnabled && this.isPointLightEnabled) {
                      this.isRegisterPressed = true;
                      this.registerLight = hdsEffect.PointLightSourceType.BRIGHT;
                    }
                  } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                    this.isRegisterPressed = false;
                    this.registerLight = hdsEffect.PointLightSourceType.NONE;
                  }
                })
                .onClick(() => {
                  this.pageStack.pushPathByName('WebView', new WebViewParam('https://bigmodel.cn/usercenter/proj-mgmt/apikeys', '获取 API Key'))
                })
            }
            .opacity(this.animStep2 ? 1 : 0)
            .translate({ y: this.animStep2 ? 0 : 20 })

            // Step 1: Create
            Row() {
              this.StepWithImage(
                "1",
                "点击“添加新的API Key”",
                "在管理后台点击右上角的“添加新的API Key”按钮。",
                $r('app.media.step1')
              )
            }
            .width('100%')
            .opacity(this.animStep3 ? 1 : 0)
            .translate({ y: this.animStep3 ? 0 : 20 })

            // Step 2: Copy
            Row() {
              this.StepWithImage(
                "2",
                "设置API Key名称",
                "在弹出的窗口中随便输入一个名称，点击确定。",
                $r('app.media.step2')
              )
            }
            .width('100%')
            .opacity(this.animStep4 ? 1 : 0)
            .translate({ y: this.animStep4 ? 0 : 20 })

            // Step 3: Paste & Save
            Row() {
              this.StepWithImage(
                "3",
                "回到应用粘贴保存",
                "将生成的API Key点击按钮复制，然后回到此页面，将密钥粘贴到上方输入框并点击“确认并保存”。",
                $r('app.media.step3')
              )
            }
            .width('100%')
            .opacity(this.animStep5 ? 1 : 0)
            .translate({ y: this.animStep5 ? 0 : 20 })
          }
        }
        .padding({ left: 16, right: 16, bottom: 40 })

      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
  build() {
      HdsNavDestination() {
        this.AIBuilder()
      }
      .titleBar({
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: '图像识别配置'
          },

        },
        // style: (deviceInfo.distributionOSApiVersion >= 60100 && this.isHdsTabsEnabled) ?{
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

  @Builder
  StepWithImage(num: string, title: string, desc: string, img: Resource) {
    Column({ space: 12 }) {
      Row() {
        Stack() {
          Circle().width(32).height(32).fill(num === "1" ? (this.isNewYearTheme ? '#FFE5E5' : (this.showVipTheme ? '#FFF8E1' : '#E8F1FF')) : '#F2F2F2')
          Text(num).fontSize(16).fontWeight(FontWeight.Bold).fontColor(num === "1" ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? '#8A6D3B' : $r('app.color.brand_color'))) : $r('app.color.text_secondary'))
        }
        .margin({ right: 12 })
        
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Text(desc)
        .fontSize(14)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Image(img)
        .width('100%')
        .height(180)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
        .margin({ top: 8 })
        .backgroundColor('#F7F7F7')
    }
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .width('100%')
  }
}
