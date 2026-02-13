import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 网络状态监测工具
 * 用于实时监听应用网络连通性
 */
export class NetworkMonitor {
  private static instance: NetworkMonitor;
  private netHandle: connection.NetHandle | null = null;
  private conn: connection.NetConnection | null = null;

  private constructor() {
    this.conn = connection.createNetConnection();
  }

  public static getInstance(): NetworkMonitor {
    if (!NetworkMonitor.instance) {
      NetworkMonitor.instance = new NetworkMonitor();
    }
    return NetworkMonitor.instance;
  }

  /**
   * 开始监听网络
   */
  public startMonitoring(): void {
    if (!this.conn) return;

    // 乐观初始化：默认认为在线，避免启动时因 undefined 跳过同步
    AppStorage.setOrCreate('isOnline', true);

    // 初始化检查
    connection.hasDefaultNet().then((has) => {
      AppStorage.setOrCreate('isOnline', has);
    }).catch((err: BusinessError) => {
      AppStorage.setOrCreate('isOnline', false);
    });

    // 监听网络可用
    this.conn.on('netAvailable', (data) => {
      this.netHandle = data;
      AppStorage.setOrCreate('isOnline', true);
      console.info('Network is available');
    });

    // 监听网络丢失
    this.conn.on('netLost', () => {
      this.netHandle = null;
      AppStorage.setOrCreate('isOnline', false);
      console.warn('Network is lost');
    });

    // 监听网络不可用
    this.conn.on('netUnavailable', () => {
      this.netHandle = null;
      AppStorage.setOrCreate('isOnline', false);
      console.error('Network is unavailable');
    });

    this.conn.register((err: BusinessError) => {
      if (err) {
        console.error('Network register failed: ' + JSON.stringify(err));
      }
    });
  }

  /**
   * 停止监听
   */
  public stopMonitoring(): void {
    if (this.conn) {
      this.conn.unregister((err) => {
        console.info('Network unregister');
      });
    }
  }
}
