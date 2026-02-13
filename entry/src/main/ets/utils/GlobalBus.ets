import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'GlobalBus';
const DOMAIN = 0x0000;

export const EVENT_SYNC_COMPLETED = 'EVENT_SYNC_COMPLETED';
export const EVENT_LOGOUT = 'EVENT_LOGOUT';
export const EVENT_LOGIN = 'EVENT_LOGIN';
export const EVENT_DATA_CHANGED = 'EVENT_DATA_CHANGED';
export const EVENT_THEME_CHANGED = 'EVENT_THEME_CHANGED';
export const EVENT_NOTIFY_PERMISSION_GRANTED = 'EVENT_NOTIFY_PERMISSION_GRANTED';

export class GlobalBus {
  public static publish(event: string) {
    const options: commonEventManager.CommonEventPublishData = {
      data: ''
    };
    commonEventManager.publish(event, options, (err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, `Publish ${event} failed, code: ${err.code}`);
      } else {
        hilog.info(DOMAIN, TAG, `Publish ${event} success`);
      }
    });
  }

  public static async subscribe(event: string, callback: () => void): Promise<commonEventManager.CommonEventSubscriber> {
    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [event]
    };
    
    return new Promise((resolve, reject) => {
      commonEventManager.createSubscriber(subscribeInfo, (err: BusinessError, subscriber: commonEventManager.CommonEventSubscriber) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `Create subscriber failed, code: ${err.code}`);
          reject(err);
          return;
        }
        commonEventManager.subscribe(subscriber, (err: BusinessError, data: commonEventManager.CommonEventData) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `Subscribe failed, code: ${err.code}`);
            return;
          }
          if (data.event === event) {
            callback();
          }
        });
        resolve(subscriber);
      });
    });
  }

  public static unsubscribe(subscriber: commonEventManager.CommonEventSubscriber) {
    if (subscriber) {
      commonEventManager.unsubscribe(subscriber, (err: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `Unsubscribe failed, code: ${err.code}`);
        }
      });
    }
  }
}
