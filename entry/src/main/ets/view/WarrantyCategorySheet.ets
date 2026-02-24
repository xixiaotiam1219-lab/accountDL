
import {  HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsEffect } from '@kit.UIDesignKit';
import { LengthMetrics, curves } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 保修分类主题色类型
 */
export type WarrantyColorTheme = 'blue' | 'purple' | 'orange' | 'teal' | 'green' | 'gray';

/**
 * 保修分类项类 (使用类以符合 ArkTS 严格类型检查)
 */
export class WarrantyCategory {
  name: string;
  icon: Resource;
  theme: WarrantyColorTheme;

  constructor(name: string, icon: Resource, theme: WarrantyColorTheme = 'blue') {
    this.name = name;
    this.icon = icon;
    this.theme = theme;
  }
}

/**
 * 导出图标映射，供 SubscriptionIcon 解析使用
 */
export const WARRANTY_ICON_MAP: Record<string, Resource> = {
  '手机': $rawfile('devices_icon/手机.svg'),
  '平板': $rawfile('devices_icon/平板.svg'),
  '笔记本电脑': $rawfile('devices_icon/笔记本电脑.svg'),
  '台式电脑': $rawfile('devices_icon/台式电脑.svg'),
  '显卡': $rawfile('devices_icon/显卡.svg'),
  'CPU': $rawfile('devices_icon/CPU.svg'),
  '移动硬盘': $rawfile('devices_icon/移动硬盘.svg'),
  '家庭存储': $rawfile('devices_icon/家庭存储.svg'),
  '显示屏': $rawfile('devices_icon/显示屏.svg'),
  '智能电视': $rawfile('devices_icon/智能电视.svg'),
  '头戴耳机': $rawfile('devices_icon/头戴耳机.svg'),
  '智能音箱': $rawfile('devices_icon/智能音箱.svg'),
  '投影仪': $rawfile('devices_icon/投影仪.svg'),
  '打印机': $rawfile('devices_icon/打印机.svg'),
  '路由器': $rawfile('devices_icon/路由器.svg'),
  '充电宝': $rawfile('devices_icon/充电宝.svg'),
  '无线充电器': $rawfile('devices_icon/无线充电器.svg'),
  '游戏机': $rawfile('devices_icon/游戏机.svg'),
  '游戏主机': $rawfile('devices_icon/游戏主机.svg'),
  '游戏手柄': $rawfile('devices_icon/游戏手柄.svg'),
  'VR头显': $rawfile('devices_icon/VR头显.svg'),
  '电子书': $rawfile('devices_icon/电子书.svg'),
  '数码相机': $rawfile('devices_icon/数码相机.svg'),
  '拍立得': $rawfile('devices_icon/拍立得.svg'),
  '无人机': $rawfile('devices_icon/无人机.svg'),
  '运动云台': $rawfile('devices_icon/运动云台.svg'),
  '运动相机': $rawfile('devices_icon/运动相机.svg'),
  '防丢器TAG': $rawfile('devices_icon/防丢器TAG.svg'),
  '鼠标': $rawfile('devices_icon/鼠标.svg'),
  '键盘': $rawfile('devices_icon/键盘.svg'),
  '数位板': $rawfile('devices_icon/数位板.svg'),
  '手写笔': $rawfile('devices_icon/手写笔.svg'),
  '冰箱': $rawfile('devices_icon/冰箱.svg'),
  '洗衣机': $rawfile('devices_icon/洗衣机.svg'),
  '空调': $rawfile('devices_icon/空调.svg'),
  '扫地机器人': $rawfile('devices_icon/扫地机器人.svg'),
  '空气净化器': $rawfile('devices_icon/空气净化器.svg'),
  '智能窗帘': $rawfile('devices_icon/智能窗帘.svg'),
  '智能门锁': $rawfile('devices_icon/智能门锁.svg'),
  '吹风机': $rawfile('devices_icon/吹风机.svg'),
  '咖啡机': $rawfile('devices_icon/咖啡机.svg'),
  '微波炉': $rawfile('devices_icon/微波炉.svg'),
  '空气炸锅': $rawfile('devices_icon/空气炸锅.svg'),
  'TWS耳机': $rawfile('devices_icon/TWS耳机.svg'),
  '智能手表': $rawfile('devices_icon/智能手表.svg'),
  '其他物品': $rawfile('devices_icon/其他物品.svg'),
};

/**
 * 导出色标映射
 */
export const WARRANTY_THEME_MAP: Record<string, WarrantyColorTheme> = {
  // Blue: 核心数码
  '手机': 'blue', '平板': 'blue', '笔记本电脑': 'blue', '台式电脑': 'blue', '显卡': 'blue', 'CPU': 'blue', '移动硬盘': 'blue', '家庭存储': 'blue', '智能手表': 'blue',
  // Purple: 影音娱乐
  '智能电视': 'purple', '头戴耳机': 'purple', 'TWS耳机': 'purple', '智能音箱': 'purple', '游戏机': 'purple', '游戏主机': 'purple', '游戏手柄': 'purple', 'VR头显': 'purple', '投影仪': 'purple',
  // Orange: 摄影配件
  '数码相机': 'orange', '拍立得': 'orange', '无人机': 'orange', '运动云台': 'orange', '运动相机': 'orange', '防丢器TAG': 'orange',
  // Teal: 外设周边
  '鼠标': 'teal', '键盘': 'teal', '数位板': 'teal', '手写笔': 'teal', '路由器': 'teal', '充电宝': 'teal', '无线充电器': 'teal',
  '智能门锁': 'green', '吹风机': 'green', '咖啡机': 'green',
  // Gray: 基础家电 & 办公
  '冰箱': 'gray', '洗衣机': 'gray', '空调': 'gray', '显示屏': 'gray', '打印机': 'gray', '电子书': 'gray', '微波炉': 'gray', '电饭煲': 'gray', '空气炸锅': 'gray',
  // Teal: 其他
  '其他物品': 'teal'
};

@Component
export struct WarrantyCategorySheet {
  @Prop selectedCategory: string = '';
  @State pressedItem: string = '';
  onSelect: (category: WarrantyCategory) => void = () => {};
  onClose: () => void = () => {};
  
  // HDS Navigation Support
  private navStack: NavPathStack = new NavPathStack();
  @StorageLink('isHdsTabsEnabled') isHdsTabsEnabled: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;

  // Animation & Effect Support
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  // 转换 Map 为数组供循环使用
  private getOptions(): WarrantyCategory[] {
    const keys = Object.keys(WARRANTY_ICON_MAP);
    const options: WarrantyCategory[] = [];
    for (const key of keys) {
      const theme = WARRANTY_THEME_MAP[key] || 'blue';
      options.push(new WarrantyCategory(key, WARRANTY_ICON_MAP[key], theme));
    }
    return options;
  }

  // 获取主题对应的柔和渐变配置
  private getSoftGradient(theme: WarrantyColorTheme): LinearGradient {
    const styles: Record<string, [string, string]> = {
      'blue': ['#EBF4FF', '#D1E5FF'],
      'purple': ['#F2F0FF', '#E5E0FF'],
      'orange': ['#FFF5E6', '#FFEBCC'],
      'teal': ['#E6F7F6', '#CCF0EE'],
      'green': ['#EBF9EE', '#D1F2D8'],
      'gray': ['#F2F2F7', '#E5E5EA']
    };
    const colors = styles[theme] || styles['blue'];
    return {
      angle: 135,
      colors: [[colors[0], 0.0], [colors[1], 1.0]]
    };
  }

  build() {
    HdsNavigation(this.navStack) {
      // 图标网格
      Scroll() {
        Grid() {
          ForEach(this.getOptions(), (item: WarrantyCategory) => {
            GridItem() {
              Column({ space: 8 }) {
                // 图标容器 - 艺术化多色族设计
                Stack() {
                  Image(item.icon)
                    .width(36)
                    .height(36)
                    .objectFit(ImageFit.Contain)
                    // 图标恢复原生态，保留内部渐变和分层细节
                    .opacity(this.selectedCategory === item.name ? 0.95 : 0.7)
                }
                .width(60)
                .height(60)
                .borderRadius(20)
                // 背景：选中时使用柔和的艺术渐变底座，未选中时使用极淡的基础灰
                .linearGradient(this.selectedCategory === item.name ? this.getSoftGradient(item.theme) : undefined)
                .backgroundColor(this.selectedCategory === item.name ? Color.Transparent : 
                  '#F5F7FA')
                .shadow({ 
                  radius: this.selectedCategory === item.name ? 8 : 0, 
                  color: this.selectedCategory === item.name ? '#15000000' : '#00000000', 
                  offsetY: this.selectedCategory === item.name ? 2 : 0 
                })
                .visualEffect(new hdsEffect.HdsEffectBuilder()
                  .pointLight({
                    sourceType: (this.isAnimationEnabled && this.isPointLightEnabled && this.pressedItem === item.name) ?
                      hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
                    illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
                  })
                  .buildEffect())
                .scale({
                  x: this.pressedItem === item.name ? 0.9 : 1,
                  y: this.pressedItem === item.name ? 0.9 : 1
                })
                .animation({
                  duration: this.isAnimationEnabled ? 150 : 0,
                  curve: curves.springMotion(this.animationResponse, this.animationDamping)
                })

                // 分类名称
                Text(item.name)
                  .fontSize(12)
                  .fontWeight(this.selectedCategory === item.name ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.selectedCategory === item.name ? $r('app.color.text_primary') : 
                    $r('app.color.text_secondary'))
                  .maxLines(1)
              }
              .width('100%')
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedItem = item.name;
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedItem = '';
                }
              })
              .onClick(() => {
                this.onSelect(item);
              })
            }
          }, (item: WarrantyCategory) => item.name)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(24)
        .columnsGap(12)
        .padding({ left: 16, right: 16, top: 76, bottom: 40 }) // Top padding for immersive title bar
        .width('100%')
      }
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .backgroundColor($r('app.color.page_background')) // Use page background instead of card background for root
    .titleBar({
      content: {
        title: { 
          mainTitle: '选择设备类型',
          subTitle: '选择与保修产品匹配的类型'
        },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.xmark'),
                action: () => {
                  this.onClose();
                }
              }
            }
          ]
        }
      },

    })
    .titleMode(HdsNavigationTitleMode.MODAL)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .width('100%')
    .height('100%')
  }
}
