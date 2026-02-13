import { floatingBall } from '@kit.ArkUI';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import hilog from '@ohos.hilog';

const DOMAIN: number = 0xF811;
const TAG: string = '[FloatingBallManager]';

/**
 * 闪控球管理器
 * 封装闪控球的创建、启动、更新、停止等操作
 */
export class FloatingBallManager {
  private static instance: FloatingBallManager;
  private controller: floatingBall.FloatingBallController | undefined = undefined;
  private onClickCallback: (() => void) | undefined = undefined;
  private onStopCallback: (() => void) | undefined = undefined;
  private isReturningFromBall: boolean = false;

  private constructor() {}

  public static getInstance(): FloatingBallManager {
    if (!FloatingBallManager.instance) {
      FloatingBallManager.instance = new FloatingBallManager();
    }
    return FloatingBallManager.instance;
  }

  /**
   * 检查设备是否支持闪控球
   */
  public isSupported(): boolean {
    try {
      return floatingBall.isFloatingBallEnabled();
    } catch (e) {
      hilog.error(DOMAIN, TAG, `isFloatingBallEnabled error: ${e}`);
      return false;
    }
  }

  /**
   * 创建闪控球控制器
   */
  public async create(context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (this.controller) {
        hilog.info(DOMAIN, TAG, 'Controller already exists');
        return true;
      }
      
      this.controller = await floatingBall.create({
        context: context
      });
      
      hilog.info(DOMAIN, TAG, 'FloatingBall controller created');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Create controller error: ${e}`);
      return false;
    }
  }

  /**
   * 启动闪控球
   * @param title 标题
   * @param content 内容
   * @param icon 图标
   * @param onClick 点击回调
   * @param onStop 停止回调
   */
  public async start(
    title: string,
    content: string,
    icon?: image.PixelMap,
    onClick?: () => void,
    onStop?: () => void
  ): Promise<boolean> {
    if (!this.controller) {
      hilog.error(DOMAIN, TAG, 'Controller not created');
      return false;
    }

    try {
      // 保存回调
      this.onClickCallback = onClick;
      this.onStopCallback = onStop;

      // 注册点击事件
      this.controller.on('click', () => {
        hilog.info(DOMAIN, TAG, 'FloatingBall clicked');
        this.onClickCallback?.();
      });

      // 注册状态变化事件
      this.controller.on('stateChange', (state: floatingBall.FloatingBallState) => {
        hilog.info(DOMAIN, TAG, `FloatingBall state: ${state}`);
        if (state === floatingBall.FloatingBallState.STOPPED) {
          this.cleanup();
          this.onStopCallback?.();
        }
      });

      // 启动闪控球 - 使用强调文本布局
      const params: floatingBall.FloatingBallParams = {
        template: floatingBall.FloatingBallTemplate.EMPHATIC,
        title: title,
        content: content,
        backgroundColor: '#FF6B6B',
        icon: icon
      };

      await this.controller.startFloatingBall(params);
      hilog.info(DOMAIN, TAG, 'FloatingBall started');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Start error: ${e}`);
      return false;
    }
  }

  /**
   * 更新闪控球内容
   */
  public async update(title: string, content: string, icon?: image.PixelMap): Promise<boolean> {
    if (!this.controller) {
      return false;
    }

    try {
      const params: floatingBall.FloatingBallParams = {
        template: floatingBall.FloatingBallTemplate.EMPHATIC,
        title: title,
        content: content,
        backgroundColor: '#4CAF50',  // 更新后变绿色
        icon: icon
      };

      await this.controller.updateFloatingBall(params);
      hilog.info(DOMAIN, TAG, 'FloatingBall updated');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Update error: ${e}`);
      return false;
    }
  }

  /**
   * 恢复应用主窗口
   */
  public async restoreMainWindow(bundleName: string, abilityName: string): Promise<boolean> {
    if (!this.controller) {
      return false;
    }

    try {
      const want: Want = {
        bundleName: bundleName,
        abilityName: abilityName
      };
      await this.controller.restoreMainWindow(want);
      hilog.info(DOMAIN, TAG, 'Main window restored');
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Restore error: ${e}`);
      return false;
    }
  }

  /**
   * 停止闪控球
   */
  public async stop(): Promise<void> {
    if (!this.controller) {
      return;
    }

    try {
      await this.controller.stopFloatingBall();
      hilog.info(DOMAIN, TAG, 'FloatingBall stopped');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Stop error: ${e}`);
    }
  }

  /**
   * 清理资源
   */
  private cleanup(): void {
    if (this.controller) {
      try {
        this.controller.off('click');
        this.controller.off('stateChange');
      } catch (e) {
        // 忽略清理错误
      }
    }
    this.controller = undefined;
    this.onClickCallback = undefined;
    this.onStopCallback = undefined;
  }

  /**
   * 获取控制器实例
   */
  public getController(): floatingBall.FloatingBallController | undefined {
    return this.controller;
  }

  /**
   * 设置/获取是否通过球返回的标志
   */
  public setReturningFromBall(val: boolean): void {
    this.isReturningFromBall = val;
  }

  public getReturningFromBall(): boolean {
    return this.isReturningFromBall;
  }
}
