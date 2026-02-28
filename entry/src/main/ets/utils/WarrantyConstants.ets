
/**
 * 保修分类主题色类型
 */
export type WarrantyColorTheme = 'blue' | 'purple' | 'orange' | 'teal' | 'green' | 'gray';

/**
 * 导出图标映射名称，供 Widget 解析使用 (仅记录文件名部分)
 * 为保持 Widget 简洁，我们仅传递资源路径
 */
export const WARRANTY_ICON_MAP_NAMES: Record<string, string> = {
  '手机': 'devices_icon/手机.svg',
  '平板': 'devices_icon/平板.svg',
  '笔记本电脑': 'devices_icon/笔记本电脑.svg',
  '台式电脑': 'devices_icon/台式电脑.svg',
  '显卡': 'devices_icon/显卡.svg',
  'CPU': 'devices_icon/CPU.svg',
  '移动硬盘': 'devices_icon/移动硬盘.svg',
  '家庭存储': 'devices_icon/家庭存储.svg',
  '显示屏': 'devices_icon/显示屏.svg',
  '智能电视': 'devices_icon/智能电视.svg',
  '头戴耳机': 'devices_icon/头戴耳机.svg',
  '智能音箱': 'devices_icon/智能音箱.svg',
  '投影仪': 'devices_icon/投影仪.svg',
  '打印机': 'devices_icon/打印机.svg',
  '路由器': 'devices_icon/路由器.svg',
  '充电宝': 'devices_icon/充电宝.svg',
  '无线充电器': 'devices_icon/无线充电器.svg',
  '游戏机': 'devices_icon/游戏机.svg',
  '游戏主机': 'devices_icon/游戏主机.svg',
  '游戏手柄': 'devices_icon/游戏手柄.svg',
  'VR头显': 'devices_icon/VR头显.svg',
  '电子书': 'devices_icon/电子书.svg',
  '数码相机': 'devices_icon/数码相机.svg',
  '拍立得': 'devices_icon/拍立得.svg',
  '无人机': 'devices_icon/无人机.svg',
  '运动云台': 'devices_icon/运动云台.svg',
  '运动相机': 'devices_icon/运动相机.svg',
  '防丢器TAG': 'devices_icon/防丢器TAG.svg',
  '鼠标': 'devices_icon/鼠标.svg',
  '键盘': 'devices_icon/键盘.svg',
  '数位板': 'devices_icon/数位板.svg',
  '手写笔': 'devices_icon/手写笔.svg',
  '冰箱': 'devices_icon/冰箱.svg',
  '洗衣机': 'devices_icon/洗衣机.svg',
  '空调': 'devices_icon/空调.svg',
  '扫地机器人': 'devices_icon/扫地机器人.svg',
  '空气净化器': 'devices_icon/空气净化器.svg',
  '智能窗帘': 'devices_icon/智能窗帘.svg',
  '智能门锁': 'devices_icon/智能门锁.svg',
  '吹风机': 'devices_icon/吹风机.svg',
  '咖啡机': 'devices_icon/咖啡机.svg',
  '微波炉': 'devices_icon/微波炉.svg',
  '电饭煲': 'devices_icon/电饭煲.svg',
  '空气炸锅': 'devices_icon/空气炸锅.svg',
  'TWS耳机': 'devices_icon/TWS耳机.svg',
  '智能手表': 'devices_icon/智能手表.svg',
};

/**
 * 导出色标映射
 */
export const WARRANTY_THEME_MAP: Record<string, WarrantyColorTheme> = {
  '手机': 'blue', '平板': 'blue', '笔记本电脑': 'blue', '台式电脑': 'blue', '显卡': 'blue', 'CPU': 'blue', '移动硬盘': 'blue', '家庭存储': 'blue', '智能手表': 'blue',
  '智能电视': 'purple', '头戴耳机': 'purple', 'TWS耳机': 'purple', '智能音箱': 'purple', '游戏机': 'purple', '游戏主机': 'purple', '游戏手柄': 'purple', 'VR头显': 'purple', '投影仪': 'purple',
  '数码相机': 'orange', '拍立得': 'orange', '无人机': 'orange', '运动云台': 'orange', '运动相机': 'orange', '防丢器TAG': 'orange',
  '鼠标': 'teal', '键盘': 'teal', '数位板': 'teal', '手写笔': 'teal', '路由器': 'teal', '充电宝': 'teal', '无线充电器': 'teal',
  '扫地机器人': 'green', '空气净化器': 'green', '智能窗帘': 'green', '智能门锁': 'green', '吹风机': 'green', '咖啡机': 'green',
  '冰箱': 'gray', '洗衣机': 'gray', '空调': 'gray', '显示屏': 'gray', '打印机': 'gray', '电子书': 'gray', '微波炉': 'gray', '电饭煲': 'gray', '空气炸锅': 'gray',
};

/**
 * 获取保修分类的渐变色样式
 */
export function getWarrantyThemeColors(theme: WarrantyColorTheme): [string, string] {
  const styles: Record<string, [string, string]> = {
    'blue': ['#EBF4FF', '#D1E5FF'],
    'purple': ['#F2F0FF', '#E5E0FF'],
    'orange': ['#FFF5E6', '#FFEBCC'],
    'teal': ['#E6F7F6', '#CCF0EE'],
    'green': ['#EBF9EE', '#D1F2D8'],
    'gray': ['#F2F2F7', '#E5E5EA']
  };
  return styles[theme] || styles['blue'];
}
