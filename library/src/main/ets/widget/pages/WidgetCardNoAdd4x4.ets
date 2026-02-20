import { CardListComponent } from '../view/CardListComponent';
import { CardListParameter } from '../viewmodel/CardListParameter';

const MAX_LINES = 1;
const STROKE_WIDTH = 0.38;
const LAYOUT_WEIGHT = 1;

const ICON_MAP: Record<string, Resource> = {
  // 'petalone': $r("app.media.petalone")
};

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCardNoAdd4x4 {
  @LocalStorageProp('widgetData') @Watch('onDataChange') widgetData: CardListItemData[] = [];
  @State sortedWidgetData: CardListItemData[] = [];
  @LocalStorageProp('totalCount') @Watch('onDataChange') totalCount: number = 0;
  @LocalStorageProp('isLoggedIn') @Watch('onDataChange') isLoggedIn: boolean = false;
  @LocalStorageProp('activeThemeId') @Watch('onDataChange') activeThemeId: string = 'default';

  get isNewYearTheme(): boolean { return this.activeThemeId === 'new_year'; }
  get isVipTheme(): boolean { return this.activeThemeId === 'vip'; }
  
  @State themeAccentColor: Resource = $r('sys.color.ohos_id_color_emphasize');
  
  @State cardListParameter: CardListParameter = new CardListParameter(
    this.isNewYearTheme ? $r('app.color.sub_card_ny_start') : (this.isVipTheme ? $r('app.color.sub_card_vip_start') : $r('sys.color.ohos_id_color_background')),
    '订阅列表', '', ImageSize.Auto, $r('app.media.startIcon'), false,
    this.isNewYearTheme ? $r('app.color.sub_card_ny_start') : (this.isVipTheme ? $r('app.color.sub_card_vip_start') : $r('sys.color.ohos_id_color_background')), 
    true, this.widgetData.length, 
    this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.isVipTheme ? $r('app.color.sub_card_vip_text') : $r('sys.color.ohos_id_color_emphasize')),
    this.isNewYearTheme ? '#33FF2400' : (this.isVipTheme ? '#33EDC269' : $r('app.color.list_item_count_background')), 
    $r('sys.color.ohos_id_color_text_primary'), false, $r('app.media.bottom_icon'));
  
  aboutToAppear() {
    this.onDataChange();
  }

  onDataChange() {
     const isNY = this.isNewYearTheme;
     const isVIP = this.isVipTheme;

     const bg = isNY ? $r('app.color.sub_card_ny_start') : (isVIP ? $r('app.color.sub_card_vip_start') : $r('sys.color.ohos_id_color_background'));
     const accent = isNY ? $r('app.color.sub_card_ny_text') : (isVIP ? $r('app.color.sub_card_vip_text') : $r('sys.color.ohos_id_color_emphasize'));
     const countBg = isNY ? '#33FF2400' : (isVIP ? '#33EDC269' : $r('app.color.list_item_count_background'));
     
     this.themeAccentColor = isNY ? $r('app.color.new_year_red_start') : (isVIP ? $r('app.color.vip_gold') : $r('sys.color.ohos_id_color_emphasize'));

     this.sortedWidgetData = [...this.widgetData].sort((a, b) => {
        let aIsUsed = false;
        let bIsUsed = false;

        // 1. 优先检查原始数据
        try {
          if (a.originalItem) {
            const aObj = JSON.parse(a.originalItem) as Record<string, Object>;
            if (aObj['recordType'] === 'groupBuy' && (aObj['usageStatus'] === 'used' || aObj['usageStatus'] === 'expired')) {
              aIsUsed = true;
            }
          }
        } catch (e) {}

        try {
          if (b.originalItem) {
            const bObj = JSON.parse(b.originalItem) as Record<string, Object>;
            if (bObj['recordType'] === 'groupBuy' && (bObj['usageStatus'] === 'used' || bObj['usageStatus'] === 'expired')) {
              bIsUsed = true;
            }
          }
        } catch (e) {}

        // 2. 兜底策略：如果原始数据解析失败，检查显示的文本内容
        if (!aIsUsed && a.content && (a.content.includes('已使用') || a.content.includes('已过期'))) {
          aIsUsed = true;
        }
        if (!bIsUsed && b.content && (b.content.includes('已使用') || b.content.includes('已过期'))) {
          bIsUsed = true;
        }

        if (aIsUsed && !bIsUsed) return 1;
        if (!aIsUsed && bIsUsed) return -1;
        return 0;
     });

     this.cardListParameter = new CardListParameter(
       bg,
       '订阅列表',
       this.cardListParameter.backgroundImage,
       this.cardListParameter.backgroundImageSize,
       this.cardListParameter.logo,
       false,
       bg,
       this.cardListParameter.isItemCount,
       this.totalCount,
       accent,
       countBg,
       $r('sys.color.ohos_id_color_text_primary'),
       false,
       this.cardListParameter.bottomIcon
    );
  }
    
  readonly actionType = 'router';
  readonly abilityName = 'EntryAbility';
  readonly message = 'add_subscription';
  readonly fullWidthPercent = '100%';
  readonly fullHeightPercent = '100%';

  @Builder
  cardListBuilder() {
    if (this.sortedWidgetData.length === 0) {
      Column() {
        Text("暂无订阅")
          .fontSize($r('app.float.item_content_font_size'))
          .fontColor($r('sys.color.black'))
          .opacity(0.6)
          .margin({ top: 20 })
      }
      .width(this.fullWidthPercent)
      .alignItems(HorizontalAlign.Center)
    } else {
      ForEach(this.sortedWidgetData, (item: CardListItemData, index: number) => {
        ListItem() {
          Row() {
            Column() {
              Text(item.title)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontSize($r('app.float.item_content_font_size'))
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .height($r('app.float.item_text_height'))
                .margin({ top: $r('app.float.item_text_margin') })
              
              Text(item.content)
                .maxLines(MAX_LINES)
                .fontSize($r('app.float.item_content_font_size'))
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontWeight(item.isExpiring ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(item.isExpiring ? '#E60012' : $r('sys.color.ohos_id_color_text_secondary'))
                .height($r('app.float.item_text_height'))

              if (index < this.sortedWidgetData.length - 1) {
                Divider()
                  .strokeWidth(STROKE_WIDTH)
                  .lineCap(LineCapStyle.Square)
                  .color($r('sys.color.ohos_id_color_list_separator'))
                  .margin({ top: $r('app.float.list_divider_margin') })
              }
            }
            .margin({ right: $r('app.float.list_row_margin') })
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(LAYOUT_WEIGHT)
            
            // 显示价格 (Vertical Centered)
            Text(item.price)
               .fontSize($r('app.float.item_content_font_size'))
               .fontColor($r('sys.color.ohos_id_color_text_primary'))
               .fontWeight(FontWeight.Medium)
               .margin({ right: 8 })

            // 图标保持在最右侧
             Stack({ alignContent: Alignment.BottomEnd }) {
               if (item.icon && item.icon.startsWith('memory://')) {
                  Image(item.icon)
                    .width($r('app.float.item_image_size'))
                    .height($r('app.float.item_image_size'))
                    .borderRadius(12)
                    .objectFit(ImageFit.Contain)
               } else if (item.icon && (item.icon.startsWith('http://') || item.icon.startsWith('https://'))) {
                  Image(item.icon)
                    .width($r('app.float.item_image_size'))
                    .height($r('app.float.item_image_size'))
                    .objectFit(ImageFit.Contain)
                    .borderRadius(12)
               } else if (item.icon && item.icon.startsWith('resource:')) {

                      Stack() {
                        Text(item.title ? item.title.charAt(0).toUpperCase() : '?')
                          .fontSize(20)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.isVipTheme ? $r('app.color.sub_card_vip_text') : $r('sys.color.ohos_id_color_emphasize')))
                      }
                      .width($r('app.float.item_image_size'))
                      .height($r('app.float.item_image_size'))
                      .backgroundColor(this.isNewYearTheme ? '#1AFF2400' : (this.isVipTheme ? '#20EDC269' : $r('app.color.list_item_count_background')))
                      .borderRadius(12)
                      .clip(true)

               } else if (item.icon && item.icon.length === 1) {
                  Stack() {
                         Text(item.icon)
                           .fontSize(20)
                           .fontWeight(FontWeight.Bold)
                           .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.isVipTheme ? $r('app.color.sub_card_vip_text') : $r('sys.color.ohos_id_color_emphasize')))
                  }
                  .width($r('app.float.item_image_size'))
                  .height($r('app.float.item_image_size'))
                  .backgroundColor(this.isNewYearTheme ? '#1AFF2400' : (this.isVipTheme ? '#20EDC269' : $r('app.color.list_item_count_background')))
                  .borderRadius(12)
                  .clip(true)
               } else {
                  Stack() {
                         Text(item.title ? item.title.charAt(0).toUpperCase() : '?')
                           .fontSize(20)
                           .fontWeight(FontWeight.Bold)
                           .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.isVipTheme ? $r('app.color.sub_card_vip_text') : $r('sys.color.ohos_id_color_emphasize')))
                  }
                  .width($r('app.float.item_image_size'))
                  .height($r('app.float.item_image_size'))
                  .backgroundColor(this.isNewYearTheme ? '#1AFF2400' : (this.isVipTheme ? '#20EDC269' : $r('app.color.list_item_count_background')))
                  .borderRadius(12)
                  .clip(true)
               }

               if (item.isGroupBuy) {
                 Text("团")
                   .fontSize(9)
                   .fontWeight(FontWeight.Bold)
                   .fontColor(Color.White)
                   .backgroundColor('#FFA500')
                   .borderRadius(4)
                   .padding({ left: 3, right: 3, top: 1, bottom: 1 })
               }

                if (item.isWarranty) {
                  Text("保")
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .backgroundColor('#007AFF')
                    .borderRadius(4)
                    .padding({ left: 3, right: 3, top: 1, bottom: 1 })
                }
             }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .onClick(() => {
          postCardAction(this, {
            action: this.actionType,
            abilityName: this.abilityName,
            params: {
              target: 'ViewSubscriptionDetail',
              data: item.originalItem || JSON.stringify(item)
            }
          });
        })
      }, (item: CardListItemData, index) => `${item.id}_${this.activeThemeId}_${index}_${item.title}_${item.content}_${item.icon}`) // Use ID as primary key
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.sortedWidgetData.length === 0) {
        // 无内容时展示登录引导
        Column() {
          Image($r("app.media.startIcon")) // App Logo
            .width(48)
            .height(48)
            .margin({ bottom: 12 })
            .objectFit(ImageFit.Contain)
          
          Text("暂无订阅")
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .margin({ bottom: 4 })
            
          Text("请先添加订阅")
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .opacity(0.6)
        }
        .width(this.fullWidthPercent)
        .height(this.fullHeightPercent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_start') : (this.isVipTheme ? $r('app.color.sub_card_vip_start') : $r('sys.color.ohos_id_color_background')))
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { target: 'AddSubscription' }
          });
        })
      } else {
        // 有数据时展示主界面内容
        Row() {
          CardListComponent({ cardListParameter: this.cardListParameter }) {
            this.cardListBuilder();
          }
        }
        .height(this.fullHeightPercent)
        .onClick(() => {
          // Click empty area to open app (Home)
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              target: 'Main'
            }
          });
        })
      }
    }
    .height(this.fullHeightPercent)
  }
}

interface CardListItemData {
  id: string;
  title: string;
  content: string;
  icon?: string;
  originalItem?: string;
  isExpiring?: boolean;
  price?: string;
  fullDate?: string;
  isLifetime?: boolean;
  isGroupBuy?: boolean;
  isWarranty?: boolean;
}
