import { common } from '@kit.AbilityKit';
import { resolveIcon } from '../utils/MemberServiceConfig';

@Component
export struct SubscriptionIcon {
  @Prop @Watch('onIconChange') icon: string = '';
  @Prop name: string = '';
  @Prop iconSize: number = 32;
  @Prop iconRadius: number = 8;
  @State loadFailed: boolean = false;
  
  // Theme States
  @StorageLink('isVip') isVip: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;

  @Prop showGroupBadge: boolean = false;
  @Prop showWarrantyBadge: boolean = false;
  
  // State to handle resource resolution status
  @State resolvedResource: Resource | null = null;
  @State isResourceResolved: boolean = false;

  aboutToAppear() {
    this.onIconChange();
  }

  onIconChange() {
    this.loadFailed = false;
    this.isResourceResolved = false;
    this.resolvedResource = null;

    if (this.icon && this.icon.startsWith('resource:')) {
      const result = resolveIcon(this.icon);
      // Check if resolution was successful (returned a Resource object, not the string input)
      if (typeof result !== 'string') {
        this.resolvedResource = result;
        this.isResourceResolved = true;
      }
    }
  }

  // 计算最终显示的图标内容，处理内置协议逻辑
  private getDisplayIcon(): string {
    if (!this.icon) return '';
    
    if (this.icon.startsWith('builtin://')) {
      const filename = this.icon.substring(10); // "builtin://".length
      const context = getContext(this) as common.UIAbilityContext;
      return `file://${context.filesDir}/local_icons/${filename}`;
    }
    
    return this.icon;
  }

  build() {
    // Root container with unified styling for ALL icon types
    Stack({ alignContent: Alignment.BottomEnd }) {
      Stack({ alignContent: Alignment.Center }) {
        // 1. 底层默认显示（首字母） - acting as background/fallback
        // 仅当没有图标，或者图标加载失败时显示
        if (!this.icon || this.loadFailed) {
          Text(this.name ? this.name.charAt(0).toUpperCase() : '?')
            .fontSize(this.iconSize * 0.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.brand_color')))
            .textAlign(TextAlign.Center)
            .width('100%')
            .height('100%')
        }

        // 2. 表层内容 (Resource vs URL/File vs Text)
        if (this.isResourceResolved && this.resolvedResource) {
          // Resource Type (App Icons)
          Image(this.resolvedResource)
            .width('100%') // Slightly scale up to ensure edges are fully clipped
            .height('100%') // Removing any potential 1px dark edge artifacts
            .objectFit(ImageFit.Contain) // Use Contain to ensure full icon is visible within the rounded container
            .borderRadius(this.iconRadius) // Double safety, though container clip handles it
        } else if (this.icon) {
          if (this.icon.startsWith('file://') || this.icon.startsWith('http') || this.icon.startsWith('data:') || this.icon.startsWith('builtin://')) {
            // Image Type (Local File, Network, or Builtin Preview)
            if (!this.loadFailed) {
              Image(this.getDisplayIcon())
                .width('102%') // Slightly scale up
                .height('102%')
                .objectFit(ImageFit.Contain)
                .borderRadius(this.iconRadius)
                .onError(() => {
                  this.loadFailed = true;
                })
            }
          } else if (!this.icon.startsWith('resource:')) {
            // Text Type (Emoji or Single Character)
            Text(this.icon)
              .fontSize(this.iconSize * 0.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isNewYearTheme ? $r('app.color.sub_card_ny_text') : (this.showVipTheme ? $r('app.color.sub_card_vip_text') : $r('app.color.text_primary')))
              .textAlign(TextAlign.Center)
              .width('100%')
              .height('100%')
              .borderRadius(this.iconRadius)
          }
        }
      }
      .width(this.iconSize)
      .height(this.iconSize)
      .backgroundColor(this.isNewYearTheme ? '#1AFF2400' : (this.showVipTheme ? '#20EDC269' : '#1A0A59F7'))
      .borderRadius(this.iconRadius)
      .clip(true) // CRITICAL: Clip content to border radius to prevent "black edges" or unrounded corners

      // Badge for Group Buy
      if (this.showGroupBadge) {
          Text('团')
            .fontSize(this.iconSize * 0.22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#FF9500') // 团购橘色
            .padding({ left: 3, right: 3, top: 1, bottom: 1 })
            .borderRadius(this.iconRadius * 0.4)
            .margin({ right: -this.iconSize * 0.05, bottom: -this.iconSize * 0.05 })
            .border({ width: this.iconSize * 0.03, color: $r('app.color.card_background') })
      }

      // Badge for Warranty
      if (this.showWarrantyBadge) {
        Text('保')
          .fontSize(this.iconSize * 0.22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor('#007AFF') // 保修蓝色
          .padding({ left: 3, right: 3, top: 1, bottom: 1 })
          .borderRadius(this.iconRadius * 0.4)
          .margin({ right: -this.iconSize * 0.05, bottom: -this.iconSize * 0.05 })
          .border({ width: this.iconSize * 0.03, color: $r('app.color.card_background') })
      }
    }
  }
}
