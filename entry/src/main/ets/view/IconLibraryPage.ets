import { LocalIconManager, AppInfo } from '../utils/LocalIconManager';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction, curves, LengthMetrics } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageCropSheet } from './ImageCropPage';
import { WebViewParam } from './WebViewPage';
import { hdsEffect, HdsNavDestination, HdsNavigationTitleBarOptions, HdsNavigationMenuItemOptions,
  ScrollEffectType} from '@kit.UIDesignKit';
import { BackgroundWatermark } from './BackgroundWatermark';

// Basic implementation of IDataSource to handle data listener
class BasicDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];

  public totalCount(): number {
    return 0;
  }

  public getData(index: number): AppInfo | undefined {
    return undefined;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded();
    })
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataAdd(index);
    })
  }

  notifyDataChange(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataChange(index);
    })
  }

  notifyDataDelete(index: number): void {
    this.listeners.forEach(listener => {
      listener.onDataDelete(index);
    })
  }

  notifyDataMove(from: number, to: number): void {
    this.listeners.forEach(listener => {
      listener.onDataMove(from, to);
    })
  }
}

class IconDataSource extends BasicDataSource {
  private dataArray: AppInfo[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): AppInfo {
    return this.dataArray[index];
  }

  public addData(index: number, data: AppInfo): void {
    this.dataArray.splice(index, 0, data);
    this.notifyDataAdd(index);
  }

  public pushData(data: AppInfo): void {
    this.dataArray.push(data);
    this.notifyDataAdd(this.dataArray.length - 1);
  }

  public setData(data: AppInfo[]) {
    this.dataArray = data;
    this.notifyDataReload();
  }
}

@Builder
export function IconLibraryPageBuilder() {
  IconLibraryPage()
}

const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct IconLibraryPage {
  @Consume('pageStack') pageStack: NavPathStack;
  @State icons: AppInfo[] = [];
  @State filteredIcons: AppInfo[] = [];
  @State categories: string[] = ['全部'];
  @State selectedCategory: string = '全部';
  @State searchText: string = '';
  @State isLoading: boolean = true;
  @State isImporting: boolean = false;
  @State showHelpSheet: boolean = false;
  private iconDataSource: IconDataSource = new IconDataSource();

  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('topRectHeight') topRectHeight: number = 0;

  @State importProgress: number = 0;
  private scroller: Scroller = new Scroller();

  // States for selection and deletion
  @State isSelectionMode: boolean = false;
  @State selectedIconNames: string[] = [];

  // State for single icon addition
  @State showAddSingleDialog: boolean = false;
  @State newIconName: string = '';
  @State newIconCategory: string = '自定义';
  @State newIconUri: string = '';
  @State showCropSheet: boolean = false;
  @State cropSourceUri: string = '';

  // Animation System
  isAnimationEnabled: boolean = false;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationResponse') animationResponse: number = 0.35;
  @StorageLink('animationDamping') animationDamping: number = 0.75;

  @State pressedIcon: string = ''; // Track pressed icon name for animation

  async aboutToAppear() {
    await this.loadData();
  }

  async loadData() {
    this.isLoading = true;
    try {
      LocalIconManager.getInstance().init(getContext(this)).then(async () => {
        this.icons = await LocalIconManager.getInstance().getAllApps();
        const cats = await LocalIconManager.getInstance().getAllCategories();
        this.categories = ['全部', ...cats];
        this.filterIcons();
        this.isLoading = false;
      });
    } catch (e) {
      console.error('Failed to load icons:', e);
      this.isLoading = false;
    }
  }

  filterIcons() {
    let result = this.icons;
    if (this.selectedCategory !== '全部') {
      result = result.filter(icon => icon.category === this.selectedCategory);
    }
    if (this.searchText) {
      const lower = this.searchText.toLowerCase();
      result = result.filter(icon => icon.name.toLowerCase().includes(lower));
    }
    this.filteredIcons = result;
    this.iconDataSource.setData(result);
  }

  toggleSelection(name: string) {
    const index = this.selectedIconNames.indexOf(name);
    if (index >= 0) {
      this.selectedIconNames.splice(index, 1);
      if (this.selectedIconNames.length === 0) {
        this.isSelectionMode = false;
      }
    } else {
      this.selectedIconNames.push(name);
    }
  }

  async deleteSelectedIcons() {
    if (this.selectedIconNames.length === 0) return;

    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedIconNames.length} 个自定义图标吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: '#FF0000' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        const count = await LocalIconManager.getInstance().deleteCustomIcons(this.selectedIconNames);
        if (count > 0) {
          promptAction.showToast({ message: `已删除 ${count} 个图标` });
          this.selectedIconNames = [];
          this.isSelectionMode = false;
          await this.loadData();
        } else {
          promptAction.showToast({ message: '部分图标无法删除（内置图标不可删除）' });
        }
      }
    });
  }

  async importIconPack() {
    if (this.isImporting) return;
    try {
      const documentViewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const selectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOptions.maxSelectNumber = 1;
      selectOptions.fileSuffixFilters = ['.zip'];
      const result: Array<string> = await documentViewPicker.select(selectOptions);
      if (result && result.length > 0) {
        this.isImporting = true;
        this.importProgress = 0;
        const uri: string = result[0];
        const count: number = await LocalIconManager.getInstance().importIconPackage(uri, (progress: number) => {
          this.importProgress = progress;
        });
        await this.loadData();
        this.selectedCategory = '全部';
        promptAction.showDialog({
          title: '导入成功',
          message: `成功导入 ${count} 个图标。`,
          buttons: [{ text: '确定', color: $r('app.color.brand_color') }]
        });
      }
    } catch (err) {
      const e = err as BusinessError;
      if (e.code !== 1300300) {
        promptAction.showToast({ message: '导入失败' });
      }
    } finally {
      this.isImporting = false;
    }
  }

  async addSingleIcon() {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (result.photoUris && result.photoUris.length > 0) {
        this.cropSourceUri = result.photoUris[0];
        this.showCropSheet = true;
      }
    } catch (err) {
      console.error('Failed to pick single icon:', err);
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  @Builder
  BottomBuilder() {
    Column() {
      // Search Bar
      Search({ value: this.searchText, placeholder: '搜索图标名称...' })
        .width('92%')
        .height(40)
        .backgroundColor('#33FFFFFF')
        .placeholderColor($r('app.color.text_secondary'))
        .margin({ top: 8, bottom: 12 })
        .border({ width: 0.5, color: 'rgba(255,255,255,0.2)' })
        .onChange((value: string) => {
          this.searchText = value;
          this.filterIcons();
        })

      // Categories List
      List({ space: 8 }) {
        ForEach(this.categories, (cat: string) => {
          ListItem() {
            Text(cat)
              .fontSize(14)
              .fontColor(this.selectedCategory === cat ?
                (this.isNewYearTheme ? '#FFD700' :
                  (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White)) :
                $r('app.color.text_secondary'))
              .fontWeight(this.selectedCategory === cat ? FontWeight.Medium : FontWeight.Normal)
              .padding({
                left: 16,
                right: 16,
                top: 6,
                bottom: 6
              })
              .backgroundColor(this.selectedCategory === cat ?
                (this.isNewYearTheme ? $r('app.color.new_year_red_start') :
                  (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) :
                $r('app.color.card_background'))
              .borderRadius(16)
          }
          .onClick(() => {
            this.selectedCategory = cat;
            this.filterIcons();
          })
        })
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height(40)
      .scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })
      .margin({ bottom: 12 })
    }
    .width('100%')
  }

  @Builder
  CropSheetBuilder() {
    ImageCropSheet({
      sourceUri: this.cropSourceUri,
      onComplete: (uri: string) => {
        this.newIconUri = uri;
        this.showCropSheet = false;
        this.newIconName = ''; // Reset for user input
        this.showAddSingleDialog = true;
      },
      onCancel: () => {
        this.showCropSheet = false;
      }
    })
  }

  async confirmAddSingleIcon() {
    if (!this.newIconName.trim()) {
      promptAction.showToast({ message: '请输入图标名称' });
      return;
    }
    const success = await LocalIconManager.getInstance().saveSingleCustomIcon(this.newIconUri, this.newIconName.trim(), this.newIconCategory.trim());
    if (success) {
      this.showAddSingleDialog = false;
      await this.loadData();
      promptAction.showToast({ message: '添加自定义图标成功' });
    } else {
      promptAction.showToast({ message: '添加失败' });
    }
  }

  @Builder ImportOverlay() {
    if (this.isImporting) {
      Stack() {
        Rect().width('100%').height('100%').fill(Color.Black).opacity(0.4)
        Column() {
          Progress({ value: this.importProgress, total: 100, type: ProgressType.Ring })
            .width(80).height(80)
            .color(Color.White)
            .style({ strokeWidth: 8 })
          Text(`${this.importProgress}%`)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).margin({ top: -50 })
          Text('正在导入图标包...')
            .fontSize(14).fontColor(Color.White).margin({ top: 30 })
        }
        .padding(24)
        .backgroundColor('#AA333333')
        .borderRadius(16)
        .backgroundBlurStyle(BlurStyle.Regular)
      }
      .width('100%').height('100%').zIndex(999)
    }
  }

  @Builder HelpSheetBuilder() {
    Column() {
      Row() {
        Text("图标包导入指南")
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(36).height(36).backgroundColor(Color.Transparent)
        .onClick(() => { this.showHelpSheet = false; })
      }
      .width('100%')
      .padding({ left: 24, right: 16, top: 16, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(16)
                .fontColor([$r('app.color.text_secondary')])
                .margin({ right: 8 })
              Text("免责声明")
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .margin({ bottom: 8 })

            Text("1. 本功能仅供个人学习、研究及交流使用，严禁用于任何商业用途。\n2. 导入的图标版权归原作者或原权利人所有，请尊重知识产权。\n3. 用户需确保导入内容的合法性，因使用本功能产生的一切版权纠纷或法律责任由用户自行承担。")
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .padding(20)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(16)
          .margin({ bottom: 16 })
          .border({ width: 1, color: $r('app.color.divider_color'), style: BorderStyle.Dashed })

          this.StepCard("1", "获取三方图标包", "感谢热心用户收集了常用的图标包，供您按需下载，请您先阅读免责声明后使用。密码:jddy", () => {
            const context = getContext(this) as common.UIAbilityContext;
            const want: Want = {
              action: 'ohos.want.action.viewData',
              entities: ['entity.system.browsable'],
              uri: 'https://wwats.lanzouu.com/b0j18f82j'
            };
            context.startAbility(want);
          }, "跳转下载")

          this.StepCard("2", "准备本地图标包资源", "将制作好的图标包保存在您手机中可见的文件目录。如果您使用的是系统浏览器，默认会保存在“我的手机-Download-浏览器-app-icons.zip”")

          this.StepCard("3", "点击导入图标包", "点击当前页面右上角的“导入图标包”图标即可。", undefined, undefined, false, $r('sys.symbol.square_and_arrow_down'))

          this.StepCard("4", "选中图标包", "在弹出的文件选择器中，选中您准备好的 .zip 格式图标包(例如app_icons.zip)即可。")

          Column().height(32)
        }
        .padding(16)
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  @Builder StepCard(num: string, title: string, desc: string, onAction?: () => void, actionText?: string, showCode: boolean = false, iconSymbol?: Resource) {
    Column({ space: 12 }) {
      Row() {
        Stack() {
          Circle().width(32).height(32).fill(num === "1" ? (this.isNewYearTheme ? '#FFE5E5' : (this.showVipTheme ? '#FFF8E1' : '#E8F1FF')) : '#F2F2F2')
          Text(num).fontSize(16).fontWeight(FontWeight.Bold).fontColor(num === "1" ? (this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))) : $r('app.color.text_secondary'))
        }
        .margin({ right: 12 })

        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Row() {
        Text(desc)
          .fontSize(14)
          .lineHeight(20)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        if (iconSymbol) {
          SymbolGlyph(iconSymbol)
            .fontSize(28)
            .fontColor([$r('app.color.brand_color')])
            .margin({ left: 12 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (showCode) {
        Text('{\n  "App名称": {\n    "filename": "icon.png",\n    "category": "分类"\n  }\n}')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding(12)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(10)
          .width('100%')
          .margin({ top: 4 })
      }

      if (onAction && actionText) {
        Button(actionText)
          .width('100%')
          .height(44)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .borderRadius(12)
          .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
          .onClick(onAction)
      }
    }
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(20)
    .width('100%')
    .shadow({ radius: 12, color: '#08000000', offsetY: 4 })
  }

  @Builder AddSingleIconDialog() {
    Column({ space: 16 }) {
      Text('添加自定义图标')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text('图标名称')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: '请输入图标对应的应用名称', text: this.newIconName })
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.page_background'))
            .onChange((v) => this.newIconName = v)
        }

        Column({ space: 4 }) {
          Text('分类')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          TextInput({ placeholder: '如：音视频、社交', text: this.newIconCategory })
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.page_background'))
            .onChange((v) => this.newIconCategory = v)
        }
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.page_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => { this.showAddSingleDialog = false; })

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .fontColor(this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_text_on_gold') : Color.White))
          .onClick(() => { this.confirmAddSingleIcon(); })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .padding(24)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(24)
    .width('90%')
  }

  @Builder IconItemBuilder(item: AppInfo) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Image(item.icon)
          .width(48)
          .height(48)
          .objectFit(ImageFit.Contain)
          .borderRadius(10)
          .margin({ bottom: 8 })
        Text(item.name)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(8)
      .backgroundColor(this.selectedIconNames.includes(item.name) ? (this.isNewYearTheme ? '#1AFFE5E5' : (this.showVipTheme ? '#1AFFF8E1' : '#1A0A59F7')) : $r('app.color.card_background'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Center)
      .border({
        width: this.selectedIconNames.includes(item.name) ? 1.5 : 0,
        color: this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))
      })

      if (this.isSelectionMode && item.isCustom) {
        Checkbox({ name: item.name, group: 'icons' })
          .select(this.selectedIconNames.includes(item.name))
          .selectedColor(this.isNewYearTheme ? $r('app.color.new_year_red_start') : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color')))
          .width(18)
          .height(18)
          .margin({ top: 6, right: 6 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .scale({ x: this.pressedIcon === item.name ? 0.9 : 1, y: this.pressedIcon === item.name ? 0.9 : 1 })
    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: curves.springMotion(this.animationResponse, this.animationDamping) })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressedIcon === item.name ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.pressedIcon = item.name;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedIcon = '';
      }
    })
    .onClick(() => {
      if (this.isSelectionMode) {
        if (item.isCustom) {
          this.toggleSelection(item.name);
        } else {
          promptAction.showToast({ message: '内置图标不可删除' });
        }
      } else {
        promptAction.showToast({ message: item.name });
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (!this.isSelectionMode) {
            if (item.isCustom) {
              this.isSelectionMode = true;
              this.toggleSelection(item.name);
            } else {
              promptAction.showToast({ message: '内置图标不可编辑' });
            }
          }
        })
    )
  }
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @Builder IconBuilder(){
    Stack({ alignContent: Alignment.Top }) {
      // Universal Background Watermark
      BackgroundWatermark()
        .zIndex(0)

      // 1. Icon Grid (Background Layer)
      Grid(this.scroller) {
        GridItem() {
          Column()
            .height(56 + this.getUIContext().px2vp(this.statusBarHeight) + 96)
        }
        .columnStart(0).columnEnd(3)

        // Icons List
        if (this.isLoading) {
          GridItem() {
            Column() {
              LoadingProgress().width(40).height(40)
                .color($r('app.color.brand_color'))
              Text('快速加载图标中...').fontSize(14).fontColor($r('app.color.text_secondary'))
                .margin({ top: 12 })
            }.width('100%').height(200).justifyContent(FlexAlign.Center)
          }.columnStart(0).columnEnd(3)
        } else if (this.filteredIcons.length === 0) {
          GridItem() {
            Column() {
              SymbolGlyph($r('sys.symbol.magnifyingglass_circle'))
                .fontSize(48)
                .fontColor([$r('app.color.text_secondary')])
              Text('未找到相关图标').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ top: 10 })
            }.width('100%').height(300).justifyContent(FlexAlign.Center)
          }.columnStart(0).columnEnd(3)
        } else {
          LazyForEach(this.iconDataSource, (icon: AppInfo) => {
            GridItem() {
              this.IconItemBuilder(icon)
            }
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })),
              TransitionEffect.OPACITY)
              .animation({
                curve: curves.springMotion(this.animationResponse, this.animationDamping),
                duration: this.isAnimationEnabled ? this.animationDuration : 0,
                // Stagger based on index in current view, but clamp to reasonable range for scrolling
                delay: this.isAnimationEnabled ? (this.filteredIcons.indexOf(icon) % 15) * 30 : 0
              })
            )
          }, (icon: AppInfo) => icon.name + (this.selectedIconNames.includes(icon.name) ? '_s' : '_u'))
        }
      }
      .width('100%')
      .height('100%')
      .cachedCount(4)
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .padding({ left: 16, right: 16, bottom: 20 })
      .editMode(this.isSelectionMode)
      .scrollBar(BarState.Off)
      .zIndex(1)


      // 3. Progress Overlay
      this.ImportOverlay()

      // 4. Help Sheet Helper
      Column()
        .bindSheet($$this.showHelpSheet, this.HelpSheetBuilder(), {
          detents: [SheetSize.LARGE, SheetSize.MEDIUM],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          preferType: SheetType.BOTTOM
        })
      Column()
        .bindSheet($$this.showCropSheet, this.CropSheetBuilder(), {
          detents: [SheetSize.LARGE],
          backgroundColor: $r('app.color.page_background'),
          showClose: false,
          preferType: SheetType.BOTTOM
        })

      // 5. Add Single Icon Dialog Mask
      if (this.showAddSingleDialog) {
        Stack() {
          Rect()
            .width('100%')
            .height('100%')
            .fill(Color.Black)
            .opacity(0.3)
            .onClick(() => {
              this.showAddSingleDialog = false;
            })

          this.AddSingleIconDialog()
        }
        .width('100%')
        .height('100%')
        .zIndex(200)
      }
    }
  }
  build() {
      HdsNavDestination() {
        this.IconBuilder()
      }
      .bindToScrollable([this.scroller])
      .titleBar(this.isSelectionMode ? {
        avoidLayoutSafeArea: true,
        content: {
          title: {
            mainTitle: '已选 ' + this.selectedIconNames.length.toString()
          },
          menu: {
            value: [
              {
                content: {
                  label: '删除',
                  icon: $r('sys.symbol.trash'),
                  action: (): void => {
                    this.deleteSelectedIcons();
                  }
                }
              } as HdsNavigationMenuItemOptions,
              {
                content: {
                  label: '取消',
                  action: (): void => {
                    this.isSelectionMode = false;
                    this.selectedIconNames = [];
                  }
                }
              } as HdsNavigationMenuItemOptions
            ]
          }
        },
      } as HdsNavigationTitleBarOptions :
        {
          avoidLayoutSafeArea: true,
          content: {
            title: {
              mainTitle: '图标库'
            },
            bottomBuilder: {
              builder: (): void => this.BottomBuilder(),
              height: 96
            },
            menu: {
              value: [
                {
                  content: {
                    label: '帮助',
                    icon: $r('sys.symbol.questionmark_circle'),
                    action: (): void => {
                      this.showHelpSheet = true;
                    }
                  }
                } as HdsNavigationMenuItemOptions,
                {
                  content: {
                    label: '添加',
                    icon: $r('sys.symbol.plus_circle'),
                    action: (): void => {
                      this.addSingleIcon();
                    }
                  }
                } as HdsNavigationMenuItemOptions,
                {
                  content: {
                    label: '导入图标包',
                    icon: $r('sys.symbol.square_and_arrow_down'),
                    action: (): void => {
                      this.importIconPack();
                    }
                  }
                } as HdsNavigationMenuItemOptions
              ]
            }
          },
        } as HdsNavigationTitleBarOptions)
      .backgroundColor($r('app.color.page_background'))

  }
}
