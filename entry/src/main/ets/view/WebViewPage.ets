import { webview } from '@kit.ArkWeb';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
export class WebViewParam {
  url: ResourceStr = '';
  title: string = '';

  constructor(url: ResourceStr, title: string) {
    this.url = url;
    this.title = title;
  }
}

@Component
export struct WebViewPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State url: ResourceStr = '';
  @State title: string = '';
  @StorageLink('topRectHeight') topRectHeight: number = 0;
  @StorageProp('currentColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  controller: webview.WebviewController = new webview.WebviewController();

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        // Web Content
        Column() {
          Web({ src: this.url, controller: this.controller })
            .width('100%')
            .layoutWeight(1)
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .darkMode(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? WebDarkMode.On : (this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? WebDarkMode.Off : WebDarkMode.Auto))
            .forceDarkAccess(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK || (this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET && (getContext(this) as common.UIAbilityContext).config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK))
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea:true,
      content: {
        title: {
          mainTitle: this.title
        }
      }
    })
    .backgroundColor($r('app.color.page_background'))
    .onBackPressed(() => {
      if (this.controller.accessStep(-1)) {
        this.controller.backward();
        return true;
      }
      return false;
    })
  }
}

@Builder
export function WebViewPageBuilder(name: string, param: Object) {
  WebViewPage({ 
    url: (param as WebViewParam).url, 
    title: (param as WebViewParam).title 
  })
}
