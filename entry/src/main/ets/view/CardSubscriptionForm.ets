import { hdsEffect } from '@kit.UIDesignKit';
import { curves, promptAction } from '@kit.ArkUI';
import { DateUtil } from '../utils/DateUtil';

@Component
export struct CardSubscriptionForm {
  @Link name: string;
  @Link cardType: string;
  @Link cardBalance: string;
  @Link nextBillingDate: Date;
  @Link billingDate: Date;
  @Link isReminderEnabled: boolean;
  @Link reminderDaysBefore: number;
  @Link reminderTime: string;
  @Prop predictedTotalReminders: number;

  // Theme & Animation Link
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;


  // Local Interaction States
  @State isCardNamePressed: boolean = false;
  @State isCardBalancePressed: boolean = false;
  @State isCardTypePressed: boolean = false;
  @State isDatePressed: boolean = false;
  @State isStartDatePressed: boolean = false;

  @State isReminderExpanded: boolean = false;
  @State reminderOpacity: number = 0;
  @State isReminderDaysPressed: boolean = false;
  @State reminderDaysLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @State isReminderTimePressed: boolean = false;
  @State reminderTimeLight: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;

  private cardTypeOptions: string[] = ['会员卡', '银行卡', '储值卡', '积分卡', '礼品卡', '交通卡', '驾照/行驶证', '身份证/护照', '社保卡/医保卡', '门禁卡', '学生卡/工作证', '图书卡', '健身卡', '美容/美发卡', '加油卡', '电影票', '优惠券', '取货码', '其他'];
  private reminderDaysOptions: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30'];

  aboutToAppear() {
    // 编辑进入时，如果提醒已开启，自动展开说明文字区域
    if (this.isReminderEnabled) {
      this.isReminderExpanded = true;
      this.reminderOpacity = 1;
    }
  }

  build() {
    Column({ space: 24 }) {
      Column({ space: 12 }) {
        // 标题行
        Row() {
          SymbolGlyph($r('sys.symbol.creditcard'))
            .fontSize(18)
            .fontColor([this.isNewYearTheme ? $r('app.color.new_year_red_start') :
              (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
            .margin({ right: 8 })
          Text("卡证信息")
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          Blank()
          Text("请填写卡证详情")
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 4 })

        // 1. 卡片名称
        Row() {
          Text("卡片名称")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          TextInput({ placeholder: '请输入卡片名称', text: this.name })
            .width('60%')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .textAlign(TextAlign.End)
            .onChange((value: string) => { this.name = value; })
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(12)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isCardNamePressed) ?
              hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .scale({
          x: (this.isAnimationEnabled && this.isCardNamePressed) ? 0.98 : 1,
          y: (this.isAnimationEnabled && this.isCardNamePressed) ? 0.98 : 1
        })
        .animation({
          duration: this.isAnimationEnabled ? 150 : 0,
          curve: curves.springMotion(this.animationResponse, this.animationDamping)
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.isCardNamePressed = true;
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isCardNamePressed = false;
        })

        // 3. 余额/积分
        Row() {
          Text("余额/积分")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          TextInput({ placeholder: '选填', text: this.cardBalance })
            .width('60%')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .textAlign(TextAlign.End)
            .type(InputType.NUMBER_DECIMAL)
            .maxLength(12)
            .onChange((value: string) => { this.cardBalance = value; })
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(12)
        .visualEffect(new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isCardBalancePressed) ?
              hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
            illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
          })
          .buildEffect())
        .scale({
          x: (this.isAnimationEnabled && this.isCardBalancePressed) ? 0.98 : 1,
          y: (this.isAnimationEnabled && this.isCardBalancePressed) ? 0.98 : 1
        })
        .animation({
          duration: this.isAnimationEnabled ? 150 : 0,
          curve: curves.springMotion(this.animationResponse, this.animationDamping)
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) this.isCardBalancePressed = true;
          else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.isCardBalancePressed = false;
        })

        // 3. 卡类型
        Row() {
          Text("卡类型")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Row() {
            Text(this.cardType || '请选择卡类型')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
              .margin({ right: 6 })
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .padding({ left: 12, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(8)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isCardTypePressed) ?
                hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .scale({ x: this.isCardTypePressed ? 0.98 : 1, y: this.isCardTypePressed ? 0.98 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.isCardTypePressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isCardTypePressed = false;
            }
          })
          .onClick(() => {
            TextPickerDialog.show({
              range: this.cardTypeOptions,
              selected: Math.max(0, this.cardTypeOptions.indexOf(this.cardType)),
              selectedTextStyle: {
                color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              acceptButtonStyle: {
                fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              onAccept: (value: TextPickerResult) => {
                this.cardType = value.value as string;
              }
            })
          })
        }
        .width('100%')
      }

      Column({ space: 12 }) {
        // 生效日期选择
        Row() {
          Text("生效日期")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Row() {
            Text(DateUtil.formatDate(this.billingDate))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
              .margin({ right: 6 })
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(16)
              .fontColor([this.isNewYearTheme ? '#FFD700' :
                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
          }
          .padding({ left: 12, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(8)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isStartDatePressed) ?
                hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .scale({ x: this.isStartDatePressed ? 0.98 : 1, y: this.isStartDatePressed ? 0.98 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.isStartDatePressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isStartDatePressed = false;
            }
          })
          .onClick(() => {
            DatePickerDialog.show({
              start: new Date(1900, 0, 1),
              end: new Date(2099, 11, 31),
              selected: this.billingDate,
              selectedTextStyle: {
                color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              acceptButtonStyle: {
                fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              onAccept: (value: DatePickerResult) => {
                const d = new Date(this.billingDate);
                d.setFullYear(value.year ?? d.getFullYear());
                d.setMonth((value.month ?? d.getMonth()));
                d.setDate(value.day ?? d.getDate());
                this.billingDate = d;
              }
            });
          })
        }
        .width('100%')

        // 到期日选择
        Row() {
          Text("到期日期")
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Row() {
            Text(DateUtil.formatDate(this.nextBillingDate))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(FontWeight.Medium)
              .margin({ right: 6 })
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(16)
              .fontColor([this.isNewYearTheme ? '#FFD700' :
                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
          }
          .padding({ left: 12, right: 10, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(8)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pointLight({
              sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.isDatePressed) ?
                hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
              illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
            })
            .buildEffect())
          .scale({ x: this.isDatePressed ? 0.98 : 1, y: this.isDatePressed ? 0.98 : 1 })
          .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.isDatePressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isDatePressed = false;
            }
          })
          .onClick(() => {
            DatePickerDialog.show({
              start: new Date(),
              end: new Date(2099, 11, 31),
              selected: this.nextBillingDate,
              selectedTextStyle: {
                color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              acceptButtonStyle: {
                fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              onAccept: (value: DatePickerResult) => {
                const d = new Date(this.nextBillingDate);
                d.setFullYear(value.year ?? d.getFullYear());
                d.setMonth((value.month ?? d.getMonth()));
                d.setDate(value.day ?? d.getDate());
                this.nextBillingDate = d;
              }
            });
          })
        }
        .width('100%')

        Divider().color($r('app.color.divider_color')).opacity(0.3)

        // 到期提醒
        Column({ space: 12 }) {
          Row() {
            Text("自动提醒")
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isReminderEnabled })
              .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
              .switchPointColor(Color.White)
              .onChange((isOn: boolean) => {
                this.isReminderEnabled = isOn;
                if (isOn) {
                  if (this.predictedTotalReminders > 30) {
                   promptAction.showToast({ message: `提醒数量已达上限 (30个)，当前预测为 ${this.predictedTotalReminders} 个` });
                  }
                  this.isReminderEnabled = true;
                  if (this.isAnimationEnabled) {
                    animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                      this.isReminderExpanded = true;
                      this.reminderOpacity = 1;
                    })
                  } else {
                    this.isReminderExpanded = true;
                    this.reminderOpacity = 1;
                  }
                } else {
                  this.isReminderEnabled = false;
                  if (this.isAnimationEnabled) {
                    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                      this.reminderOpacity = 0;
                    });
                    setTimeout(() => {
                      animateTo({ duration: this.animationDuration, curve: Curve.FastOutSlowIn }, () => {
                        this.isReminderExpanded = false;
                      });
                    }, 200);
                  } else {
                    this.isReminderExpanded = false;
                    this.reminderOpacity = 0;
                  }
                }
              })
          }
          .width('100%')

          if (this.isReminderEnabled || this.isReminderExpanded) {
            Row() {
              Blank()
              Text(`已设置 ${this.predictedTotalReminders}/30 个提醒`)
                .fontSize(11)
                .fontColor(this.predictedTotalReminders >= 30 ? $r('app.color.warning_color') : $r('app.color.text_secondary'))
                .margin({ bottom: 4 })
            }
            .width('100%')
          }

          if (this.isReminderExpanded) {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(12)
                .fontColor([$r('app.color.text_secondary')])
                .margin({ right: 4 })

              Text("提示音为系统默认提示音，可能会出现铃声过大问题、提示被忽略等问题，可通过调整系统闹钟音量调整本应用提示音量。请合理设置提醒时间，避免过度滥用提醒功能。本应用不对因提醒失效导致的任何损失承担责任。")
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: -4, bottom: 8 })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
              .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
            .opacity(this.reminderOpacity)

            Row() {
              Blank()
              // 提前天数
              Row() {
                Text(`提前 ${this.reminderDaysBefore} 天`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
              }
              .height(32)
              .padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.page_background'))
              .borderRadius(8)
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.reminderDaysLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .scale({ x: this.isReminderDaysPressed ? 0.98 : 1, y: this.isReminderDaysPressed ? 0.98 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isReminderDaysPressed = true;
                    this.reminderDaysLight = hdsEffect.PointLightSourceType.BRIGHT;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isReminderDaysPressed = false;
                  this.reminderDaysLight = hdsEffect.PointLightSourceType.NONE;
                }
              })
              .onClick(() => {
                TextPickerDialog.show({
                  range: this.reminderDaysOptions,
                  selected: this.reminderDaysOptions.indexOf(this.reminderDaysBefore.toString()),
                  selectedTextStyle: {
                    color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                  },
                  acceptButtonStyle: {
                    fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                  },
                  onAccept: (value: TextPickerResult) => {
                    this.reminderDaysBefore = parseInt(value.value as string);
                  }
                })
              })
              .margin({ right: 12 })

              // 提醒时间
              Row() {
                Text(this.reminderTime)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
              }
              .height(32)
              .padding({ left: 10, right: 10 })
              .backgroundColor($r('app.color.page_background'))
              .borderRadius(8)
              .visualEffect(new hdsEffect.HdsEffectBuilder()
                .pointLight({
                  sourceType: this.reminderTimeLight,
                  illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                })
                .buildEffect())
              .scale({ x: this.isReminderTimePressed ? 0.98 : 1, y: this.isReminderTimePressed ? 0.98 : 1 })
              .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  if (this.isAnimationEnabled && this.isPointLightEnabled) {
                    this.isReminderTimePressed = true;
                    this.reminderTimeLight = hdsEffect.PointLightSourceType.BRIGHT;
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.isReminderTimePressed = false;
                  this.reminderTimeLight = hdsEffect.PointLightSourceType.NONE;
                }
              })
              .onClick(() => {
                const timeParts = this.reminderTime.split(':');
                const selectedHour = parseInt(timeParts[0]);
                const selectedMinute = parseInt(timeParts[1]);
                const selectedDate = new Date();
                selectedDate.setHours(selectedHour, selectedMinute);

                TimePickerDialog.show({
                  selected: selectedDate,
                  selectedTextStyle: {
                    color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                  },
                  acceptButtonStyle: {
                    fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                      (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
                  },
                  onAccept: (value: TimePickerResult) => {
                    const h = value.hour.toString().padStart(2, '0');
                    const m = value.minute.toString().padStart(2, '0');
                    this.reminderTime = `${h}:${m}`;
                  }
                })
              })
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 }))
              .animation({ duration: this.isAnimationEnabled ? undefined : 0 }))
            .opacity(this.reminderOpacity)
          }
        }
        .width('100%')
      }
    }
  }
}
