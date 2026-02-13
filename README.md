# 记得订阅 (accountDL)

一款基于 HarmonyOS 的智能化订阅管理工具，旨在帮助用户清晰掌握各类会员、服务订阅的周期与支出。

## 🌟 核心特性

- **智能化订阅管理**：支持订阅服务的添加、编辑及到期自动提醒。
- **📸 屏幕捕捉识别**：通过“闪控球”快速截取屏幕，利用 AI 自动识别并提取订阅信息。
- **🃏 万能卡片支持**：提供“标准版”与“纯净版”原子化服务卡片，桌面直观查看订阅状态。
- **🖐️ 智感握姿技术**：自动识别单手操作习惯，智能对齐 Tab 栏，提升交互体验。
- **🌓 深度主题适配**：完美支持深色模式与不同设备的响应式布局（手机、平板、2in1）。

## 🚀 技术细节

- **开发框架**：HarmonyOS ArkTS 声明式 UI 范式。
- **核心能力**：
  - 基于 `ReminderRequest` 的精准后台提醒。
  - 使用 `CustomScreenCapture` 实现的高效截图流。
  - `ohos.permission.DETECT_GESTURE` 驱动的手势感应。
- **依赖库**：
  - `@candies/image_cropper`: 图片裁剪处理。
  - `@ark/luban`: 图片压缩优化。

## 📂 项目结构

```txt
├── AppScope             # 全局公共资源
├── entry/src/main       # 主程序模块
│   ├── ets              # 代码根目录
│   │   ├── entryability # 程序生命周期管理
│   │   ├── manager      # 核心管理类（通知、共享等）
│   │   ├── view         # UI 界面组件
│   └── resources        # 资源文件（多语言、图片、配置）
└── library              # 原子化服务卡片等库模块
```

## 🛠️ 快速开始

1. **环境准备**：
   - DevEco Studio 5.0.1 或更高版本。
   - HarmonyOS SDK 版本：API 12+。
2. **运行步骤**：
   - 使用 DevEco Studio 打开项目。
   - 连接 HarmonyOS 真机或模拟器。
   - 点击 **Run** 按钮部署。

## 📝 许可证

本项目遵循 [GitCode 远程许可证](https://gitcode.com/xxt1219/accountDL/tree/main?tab=license) 及项目内置的 [用户协议与开源许可](f:/accountDL/entry/src/main/resources/rawfile/user_agreement.html)。

---
*由 ArkTS Antigravity 辅助构建。*
