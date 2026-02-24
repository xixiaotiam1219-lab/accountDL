import { ExtendedWarrantyItem } from '../model/SubscriptionModel';
import { DateUtil } from '../utils/DateUtil';

@Component
export struct ExtendedWarrantyItemView {
  @ObjectLink item: ExtendedWarrantyItem;
  @Prop index: number;
  @Prop currency: string;
  @Prop isNewYearTheme: boolean;
  @Prop showVipTheme: boolean;
  @Prop animationDuration: number;
  @Prop isParentReminderEnabled: boolean;
  onDelete: (id: string) => void = (id: string) => {};
<<<<<<< HEAD
=======
  onReminderChange: () => void = () => {};
>>>>>>> API23

  build() {
    Column() {
      // 头部：项目编号及删除按钮
      Row() {
        Text(`保障项目 ${this.index + 1}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Button() {
          SymbolGlyph($r('sys.symbol.minus_circle'))
            .fontSize(16)
            .fontColor([$r('app.color.new_year_red_start')])
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onDelete(this.item.id);
        })
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 内容：名称、金额、日期、提醒开关
      Column({ space: 8 }) {
        // 名称
        Row() {
          Text("名称").fontSize(14).fontColor($r('app.color.text_primary'))
          Blank()
          TextInput({ placeholder: '例如：碎屏险', text: this.item.name })
            .width('60%')
            .fontSize(14)
            .textAlign(TextAlign.End)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .height(32)
            .onChange((val: string) => { this.item.name = val; })
        }.width('100%')

        Divider().color($r('app.color.divider_color')).opacity(0.1)

        // 金额
        Row() {
          Text("金额").fontSize(14).fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.currency === 'USD' ? '$' : '¥')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ right: 2 })
          TextInput({ placeholder: '0.00', text: this.item.price })
            .width('40%')
            .fontSize(14)
            .textAlign(TextAlign.End)
            .backgroundColor(Color.Transparent)
            .type(InputType.NUMBER_DECIMAL)
            .padding(0)
            .height(32)
            .onChange((val: string) => { this.item.price = val; })
        }.width('100%')

        Divider().color($r('app.color.divider_color')).opacity(0.1)

        // 到期时间
        Row() {
          Text("到期时间").fontSize(14).fontColor($r('app.color.text_primary'))
          Blank()
          Row() {
            Text(this.item.date ? DateUtil.formatDate(this.item.date) : '请选择')
              .fontSize(14)
              .fontColor(this.item.date ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
              .margin({ right: 4 })
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(14)
              .fontColor([this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
          }
          .onClick(() => {
            DatePickerDialog.show({
              selected: this.item.date ? new Date(this.item.date) : new Date(),
              selectedTextStyle: {
                color: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              acceptButtonStyle: {
                fontColor: this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
              },
              onDateAccept: (date: Date) => {
                this.item.date = date.getTime();
              }
            })
          })
        }.width('100%')

        Divider().color($r('app.color.divider_color')).opacity(0.1)

        // 提醒设置 (仅开关)
        Column({ space: 8 }) {
          if (this.isParentReminderEnabled) {
            Row() {
              Text("到期提醒").fontSize(14).fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.item.isReminderEnabled })
                .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
                .height(20)
                .onChange((isOn: boolean) => {
                  animateTo({ duration: 200 }, () => {
                    this.item.isReminderEnabled = isOn;
<<<<<<< HEAD
=======
                    this.onReminderChange();
>>>>>>> API23
                  })
                })
            }.width('100%')
          } else {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(12)
                .fontColor([$r('app.color.text_secondary')])
                .margin({ right: 4 })
              Text("开启下方“到期提醒”主开关后可在到期前提醒")
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }
        }
      }
      .padding(12)
      .backgroundColor($r('app.color.page_background'))
      .borderRadius(12)
      .border({ width: 0.5, color: '#10000000' })
    }
  }
}
