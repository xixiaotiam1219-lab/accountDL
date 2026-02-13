import { updateManager } from '@kit.AppGalleryKit';
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'UpdateManager';

export class UpdateManager {
  private static instance: UpdateManager;
  private hasNewVersionKey = 'hasNewVersion';

  private constructor() {}

  public static getInstance(): UpdateManager {
    if (!UpdateManager.instance) {
      UpdateManager.instance = new UpdateManager();
    }
    return UpdateManager.instance;
  }

  /**
   * 检查更新
   * @param context UIAbilityContext
   * @param silent 是否静默检查 (不显示 Loading 和 Toast)
   * @returns Promise<void>
   */
  async checkUpdate(context: common.UIAbilityContext, silent: boolean = true): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Checking for updates... silent: %{public}b', silent);
      const checkResult = await updateManager.checkAppUpdate(context);
      hilog.info(DOMAIN, TAG, "Succeeded in checking Result updateAvailable:" + checkResult.updateAvailable);
      
      if (checkResult.updateAvailable) {
        AppStorage.setOrCreate(this.hasNewVersionKey, true);
        const resultCode = await updateManager.showUpdateDialog(context);
        hilog.info(DOMAIN, TAG, "Succeeded in showing UpdateDialog resultCode:" + resultCode);
      } else {
        AppStorage.setOrCreate(this.hasNewVersionKey, false);
      }
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `checkAppUpdate/showUpdateDialog onError.code is ${err.code}, message is ${err.message}`);
    }
  }
}
