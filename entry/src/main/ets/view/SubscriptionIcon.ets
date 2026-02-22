import { common } from '@kit.AbilityKit';
import { resolveIcon } from '../utils/MemberServiceConfig';
import { WARRANTY_THEME_MAP, WarrantyColorTheme, getWarrantyThemeColors } from '../utils/WarrantyConstants';
import { LocalIconManager } from '../utils/LocalIconManager';

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
  @State resolvedBuiltinPath: string = '';

  aboutToAppear() {
    this.onIconChange();
  }

  async onIconChange() {
    this.loadFailed = false;
    this.isResourceResolved = false;
    this.resolvedResource = null;
    this.resolvedBuiltinPath = '';

    if (this.icon && (this.icon.startsWith('resource:') || this.icon.startsWith('warranty_icon:'))) {
      const result = resolveIcon(this.icon);
      // Check if resolution was successful (returned a Resource object, not the string input)
      if (typeof result !== 'string') {
        this.resolvedResource = result;
        this.isResourceResolved = true;
      }
    } else if (this.icon && this.icon.startsWith('builtin://')) {
      const appName = this.icon.substring(10).replace('.png', '');
      let appInfo = await LocalIconManager.getInstance().getAppInfo(appName);
      
      // If exact match fails for builtin parsing, fall back to fuzzy search
      if (!appInfo) {
        const fuzzyResults = await LocalIconManager.getInstance().searchApps(appName, 1);
        if (fuzzyResults && fuzzyResults.length > 0) {
          appInfo = fuzzyResults[0];
        }
      }

      if (appInfo && appInfo.icon) {
        this.resolvedBuiltinPath = appInfo.icon;
        this.loadFailed = false; // 重置错误状态以触发重绘
      } else {
        this.loadFailed = true;
      }
    }
  }

  // 获取保修主题柔和渐变底座
  private getWarrantyBgGradient(): LinearGradient | undefined {
    if (!this.icon.startsWith('warranty_icon:')) return undefined;
    const name = this.icon.split(':')[1];
    const theme: WarrantyColorTheme = WARRANTY_THEME_MAP[name] || 'blue';
    const colors = getWarrantyThemeColors(theme);
    return {
      angle: 135,
      colors: [[colors[0], 0.0], [colors[1], 1.0]]
    };
  }

  // 计算最终显示的图标内容，处理内置协议逻辑
  private getDisplayIcon(): string {
    if (!this.icon) return '';
    
    if (this.icon.startsWith('builtin://')) {
      return this.resolvedBuiltinPath; // Use the dynamically retrieved path from LocalIconManager
    }
    
    // 如果是 file://, http://, data: 等原生支持的路径，直接返回
    return this.icon;
  }

  build() {
    // Root container with unified styling for ALL icon types
    Stack({ alignContent: Alignment.BottomEnd }) {
      Stack() {
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
          // Resource Type (App Icons / SVG Warranty Icons)
          Image(this.resolvedResource)
            .width('100%') // Slightly scale up to ensure edges are fully clipped
            .height('100%') // Removing any potential 1px dark edge artifacts
            .objectFit(ImageFit.Contain) // Use Contain to ensure full icon is visible within the rounded container
            .borderRadius(this.iconRadius) // Double safety, though container clip handles it
            .opacity(0.85) // 保持适度的柔和感，避免纯黑过于突兀
        } else if (this.icon) {
          if (this.icon.startsWith('file://') || this.icon.startsWith('http') || this.icon.startsWith('data:') || this.icon.startsWith('builtin://')) {
            // Image Type (Local File, Network, or Builtin Preview)
            // 只有当非 builtin，或者 builtin 且已解析出真实路径时，才渲染 Image 组件，防止触发空 url 报错
            if (!this.loadFailed && (!this.icon.startsWith('builtin://') || this.resolvedBuiltinPath)) {
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
      // 为保修图标提供 100% 不透明的浅色弱渐变底座，其他场景保持默认轻微背景
      .linearGradient(this.getWarrantyBgGradient())
      .backgroundColor(this.icon.startsWith('warranty_icon:') ? Color.Transparent : 
        (this.isNewYearTheme ? '#1AFF2400' : (this.showVipTheme ? '#20EDC269' : '#1A0A59F7')))
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
