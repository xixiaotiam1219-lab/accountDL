import { SubscriptionModel } from '../model/SubscriptionModel';
import { vibrator } from '@kit.SensorServiceKit';
import { curves, promptAction } from '@kit.ArkUI';
import { LocalNotificationManager } from '../manager/LocalNotificationManager';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { GlobalBus, EVENT_NOTIFY_PERMISSION_GRANTED } from '../utils/GlobalBus';
import { commonEventManager } from '@kit.BasicServicesKit';

@Component
export struct NewYearSubscriptionCard {
  @Prop data: SubscriptionModel; // Optional, mainly for key/id if needed in List
  
  // 交互状态
  @State isPressed: boolean = false;
  
  // 动画配置
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('animationDamping') animationDamping: number = 0.5;

  // 倒计时状态
  @State countdownText: string = '';
  @State timerId: number = -1;
  @State isExpired: boolean = false; // 是否已经过了春节当天
  @State isHolidayOver: boolean = false; // 是否已经过了节日假期 (2月24日)
  @State isReminderSet: boolean = false; // 是否设置了新年提醒
  private permissionSubscriber: commonEventManager.CommonEventSubscriber | null = null;

  // 背景动画状态
  @State breathingOpacity: number = 0.6;

  aboutToAppear() {
    this.checkVisibility();
    this.startBreathingAnimation();
    this.startCountdown();
    this.initDefaultReminder();
    this.initPermissionListener();
  }

  async initPermissionListener() {
    this.permissionSubscriber = await GlobalBus.subscribe(EVENT_NOTIFY_PERMISSION_GRANTED, async () => {
      // 权限授予后，立即尝试初始化默认提醒，实现首次启动"自动亮起"
      await this.initDefaultReminder();
    });
  }

  aboutToDisappear() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
    if (this.permissionSubscriber) {
      GlobalBus.unsubscribe(this.permissionSubscriber);
    }
  }

  checkVisibility() {
    const now = new Date().getTime();
    const holidayEndDate = new Date('2026-02-24T23:59:59').getTime();
    if (now > holidayEndDate) {
      this.isHolidayOver = true;
    }
  }

  async initDefaultReminder() {
    const manager: LocalNotificationManager = LocalNotificationManager.getInstance();
    const pref: PreferenceUtil = PreferenceUtil.getInstance();
    
    // 检查状态
    this.isReminderSet = await manager.isNewYearReminderSet();
    
    // 如果未设置，且用户没有明确手动关闭过，则尝试开启 (不强制弹授权框，静默尝试)
    if (!this.isReminderSet) {
      const isDisabled: boolean = await pref.getNewYearReminderDisabled();
      if (!isDisabled) {
        const success: boolean = await manager.scheduleNewYearReminder(false);
        if (success) {
          this.isReminderSet = true;
        }
      }
    }
  }

  async toggleReminder() {
    const manager: LocalNotificationManager = LocalNotificationManager.getInstance();
    const pref: PreferenceUtil = PreferenceUtil.getInstance();
    
    if (this.isReminderSet) {
      await manager.cancelNewYearReminder();
      this.isReminderSet = false;
      // 记录用户手动关闭意图
      await pref.saveNewYearReminderDisabled(true);
      promptAction.showToast({ message: '新年提醒已取消' });
    } else {
      // 开启时，强制请求授权（如果无权限会引导至设置页）
      const success: boolean = await manager.scheduleNewYearReminder(true);
      if (success) {
        this.isReminderSet = true;
        // 重置手动关闭标记
        await pref.saveNewYearReminderDisabled(false);
        promptAction.showToast({ message: '提醒已预约：2026-02-17 00:00' });
      }
    }
  }

  startBreathingAnimation() {
    if (!this.isAnimationEnabled) return;
    animateTo({
      duration: 2000,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.breathingOpacity = 1.0;
    })
  }

  startCountdown() {
    const targetDate = new Date('2026-02-17T00:00:00').getTime();
    const holidayEndDate = new Date('2026-02-24T23:59:59').getTime();
    
    const update = () => {
      const now = new Date().getTime();
      
      // 1. 如果已经过了假期 (2月24日)
      if (now > holidayEndDate) {
        this.isHolidayOver = true;
        clearInterval(this.timerId);
        return;
      }

      // 2. 如果已经过了春节当天 (2月17日)，但在假期内
      const diff = targetDate - now;
      if (diff <= 0) {
        this.isExpired = true;
        this.countdownText = '🧨 春节快乐，恭喜发财！';
        return;
      }

      // 3. 正常倒数
      const days = Math.floor(diff / (1000 * 60 * 60 * 24));
      const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
      const seconds = Math.floor((diff % (1000 * 60)) / 1000);

      this.countdownText = `${days}天 ${hours}时 ${minutes}分 ${seconds}秒`;
    };

    update();
    this.timerId = setInterval(update, 1000);
  }

  @Builder LanternDecoration() {
    Stack() {
      // 灯笼线
      Line().startPoint([10, 0]).endPoint([10, 15]).stroke('#FFD700').strokeWidth(1)
      // 灯笼主体
      Text('🏮')
        .fontSize(24)
        .fontColor(Color.Red)
        .position({ x: 0, y: 10 })
    }
    .position({ right: 10, top: -5 })
    .rotate({ angle: 5 })
  }

  @Builder FuDecoration() {
      Text('福')
        .fontSize(60)
        .fontWeight(FontWeight.Bold)
        .fontColor('#20FFD700') // 金色低透明度
        .rotate({ angle: 15 })
        .position({ bottom: -10, right: -10 })
        .hitTestBehavior(HitTestMode.None)
  }

  build() {
    if (!this.isHolidayOver) {
      Stack() {
        // 动态背景
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [['#D32F2F', 0.0], ['#B71C1C', 1.0]]
          })
          .borderRadius(24)
           
        // 装饰层
        this.FuDecoration()
        this.LanternDecoration()
        
        // 内容层
        Row() {
           // 左侧图标：foreground
           Image($r('app.media.foreground'))
             .width(48)
             .height(48)
             .borderRadius(10)
             .objectFit(ImageFit.Contain)
             .margin({ right: 14 })
             .flexShrink(0)
  
           // 中间文字
           Column() {
              Text(this.isExpired ? '春节假期中' : '距离 2026 春节还有')
                 .fontSize(14)
                 .fontColor('#FFCDD2') // 浅红
                 .margin({ bottom: 4 })
              
              Text(this.countdownText)
                 .fontSize(18)
                 .fontWeight(FontWeight.Bold)
                 .fontColor('#FFD700') // 金色
                 .fontFamily('HarmonyOS Sans SC')
           }
           .alignItems(HorizontalAlign.Start)
           .layoutWeight(1)
  
           // 右侧提醒
           Column() {
              // 提醒铃铛
              SymbolGlyph(this.isReminderSet ? $r('sys.symbol.bell_fill') : $r('sys.symbol.bell'))
                .fontSize(24)
                .fontColor(this.isReminderSet ? ['#FFD700'] : ['#FFCDD2'])
                .onClick(() => {
                   this.toggleReminder();
                })
           }
           .margin({ left: 8 })
        }
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(84) // 固定高度，与普通卡片(约80-90)接近
      .clip(true)
      .borderRadius(24)
      .shadow({ 
        radius: 20, 
        color: 'rgba(211, 47, 47, 0.4)', // 红色阴影
        offsetY: 8 
      })
      .border({
         width: 1.5,
         color: `rgba(255, 215, 0, ${this.breathingOpacity})` 
      })
      .scale({ x: this.isPressed ? 0.96 : 1, y: this.isPressed ? 0.96 : 1 })
      .animation({
         curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear,
         duration: this.isAnimationEnabled ? undefined : 0
      })
      .gesture(
          GestureGroup(GestureMode.Exclusive,
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                try {
                  vibrator.startVibration({ type: 'time', duration: 40 }, { id: 0, usage: 'touch' });
                } catch (e) {}
                this.isPressed = false;
              })
          )
      )
      .onTouch((event: TouchType | TouchEvent) => {
         // 处理 TouchEvent 或 TouchType (API 兼容性)
         const type = typeof event === 'number' ? event : (event as TouchEvent).type;
         if (type === TouchType.Down) {
            this.isPressed = true;
         } else if (type === TouchType.Up || type === TouchType.Cancel) {
            this.isPressed = false;
         }
      })
    }
  }
}
