import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'IapManager';
const DOMAIN = 0x0000;

export interface ProductInfo {
  id: string;
  name: string;
  desc: string;
  price: string; // Formatted price (e.g. "¥15.00")
  originalPrice?: string;
}

export class IapManager {
  private static instance: IapManager;
  private uiContext: common.UIAbilityContext | null = null;

  private constructor() {}

  public static getInstance(): IapManager {
    if (!IapManager.instance) {
      IapManager.instance = new IapManager();
    }
    return IapManager.instance;
  }

  public setContext(context: common.UIAbilityContext) {
    this.uiContext = context;
  }

  /**
   * 检查当前环境是否支持 IAP
   */
  public async checkEnvironment(): Promise<boolean> {
    if (!this.uiContext) {
      hilog.error(DOMAIN, TAG, 'Context not set');
      return false;
    }

    try {
      await iap.queryEnvironmentStatus(this.uiContext);
      hilog.info(DOMAIN, TAG, 'IAP Environment Normal');
      
      // Check Sandbox status for debugging
      try {
        const isSandbox = await iap.isSandboxActivated(this.uiContext);
        hilog.info(DOMAIN, TAG, `IAP Sandbox Activated: ${isSandbox}`);
      } catch (sandboxErr) {
        const err = sandboxErr as BusinessError;
        hilog.warn(DOMAIN, TAG, `Check Sandbox failed: ${err.code} - ${err.message}`);
      }

      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `IAP Check failed: ${err.code} - ${err.message}`);
      return false;
    }
  }

  /**
   * 查询商品信息
   * @param productIds 商品 ID 列表
   */
  public async queryProducts(productIds: string[]): Promise<ProductInfo[]> {
    if (!this.uiContext) {
      hilog.error(DOMAIN, TAG, 'Context not set');
      return [];
    }

    try {
      // 这里的 ProductType 需要根据实际商品类型调整
      // 如果混合了 CONSUMABLE 和 AUTORENEWABLE，可能需要分两次查，或者只查一种
      // 假设会员是自动续期订阅 (AUTORENEWABLE) 或 消耗型 (CONSUMABLE，若是买断)
      // 注意：queryProducts 一次只能查一种类型，或者需要分别调用
      // 为了简化，假设我们这里只处理自动续期订阅 (Pro Monthly) 和 消耗型 (Lifetime，如果作为消耗型商品)
      // 但通常 queryProducts 参数需要指定 productType。
      // 我们先尝试查询 AUTORENEWABLE
      
      const params: iap.QueryProductsParameter = {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: productIds
      };

      const result = await iap.queryProducts(this.uiContext, params);
      hilog.info(DOMAIN, TAG, `Query Products success: ${result.length} items`);
      
      return result.map((p: iap.Product): ProductInfo => ({
        id: p.id || '',
        name: p.name || '',
        desc: p.description || '',
        price: p.price || '',
        originalPrice: p.originalLocalPrice || p.price || ''
      }));

    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, `Query products failed: ${err.code} - ${err.message}`);
      return [];
    }
  }
  
  /**
   * 查询消耗型商品 (Lifetime 买断)
   */
  public async queryConsumableProducts(productIds: string[]): Promise<ProductInfo[]> {
      if (!this.uiContext) return [];
      try {
          const params: iap.QueryProductsParameter = {
            productType: iap.ProductType.CONSUMABLE,
            productIds: productIds
          };
          const result = await iap.queryProducts(this.uiContext, params);
          return result.map((p: iap.Product): ProductInfo => ({
            id: p.id || '',
            name: p.name || '',
            desc: p.description || '',
            price: p.price || '',
            originalPrice: p.originalLocalPrice || p.price || ''
          }));
      } catch (error) {
          hilog.error(DOMAIN, TAG, `Query Consumable failed: ${JSON.stringify(error)}`);
          return [];
      }
  }

  /**
   * 查询非续期订阅商品
   */
  public async queryNonRenewingProducts(productIds: string[]): Promise<ProductInfo[]> {
      if (!this.uiContext) return [];
      try {
          const params: iap.QueryProductsParameter = {
            productType: iap.ProductType.NONRENEWABLE,
            productIds: productIds
          };
          const result = await iap.queryProducts(this.uiContext, params);
          hilog.info(DOMAIN, TAG, `Query NonRenewing success: ${result.length} items from ${productIds}`);
          return result.map((p: iap.Product): ProductInfo => ({
            id: p.id || '',
            name: p.name || '',
            desc: p.description || '',
            price: p.price || '',
            originalPrice: p.originalLocalPrice || p.price || ''
          }));
      } catch (error) {
          hilog.error(DOMAIN, TAG, `Query NonRenewing failed: ${JSON.stringify(error)}`);
          return [];
      }
  }

  /**
   * 确认交易 (发货)
   * 消耗型/非续期订阅商品在支付成功后必须调用此接口
   */
  public async finishPurchase(purchaseData: InAppPurchaseData, type: iap.ProductType): Promise<void> {
    if (!this.uiContext) return;
    try {
      if (!purchaseData.purchaseToken || !purchaseData.purchaseOrderId) {
          hilog.warn(DOMAIN, TAG, 'finishPurchase: invalid data');
          return;
      }
      
      const params: iap.FinishPurchaseParameter = {
        productType: type,
        purchaseToken: purchaseData.purchaseToken,
        purchaseOrderId: purchaseData.purchaseOrderId
      };
      
      await iap.finishPurchase(this.uiContext, params);
      hilog.info(DOMAIN, TAG, 'Finish Purchase success');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Finish Purchase failed: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 查询未完成订单 (补单)
   */
  public async queryUnfinishedPurchases(type: iap.ProductType): Promise<InAppPurchaseData[]> {
    if (!this.uiContext) return [];
    try {
        const params: iap.QueryPurchasesParameter = {
          productType: type,
          queryType: iap.PurchaseQueryType.UNFINISHED
        };
        
        const res = await iap.queryPurchases(this.uiContext, params);
        if (res && res.purchaseDataList) {
            hilog.info(DOMAIN, TAG, `Found ${res.purchaseDataList.length} unfinished orders`);
            return res.purchaseDataList.map(json => JSON.parse(json) as InAppPurchaseData);
        }
        return [];
    } catch (e) {
        hilog.error(DOMAIN, TAG, `Query unfinished failed: ${JSON.stringify(e)}`);
        return [];
    }
  }

  public async createPurchase(productId: string, type: iap.ProductType): Promise<InAppPurchaseData | null> {
    if (!this.uiContext) {
      throw new Error('Context not set');
    }

    try {
      const params: iap.PurchaseParameter = {
        productId: productId,
        productType: type,
        developerPayload: 'test_payload_' + Date.now()
      };

      const result = await iap.createPurchase(this.uiContext, params);
      
      if (!result || !result.purchaseData) {
        hilog.error(DOMAIN, TAG, 'Purchase result empty');
        return null;
      }
      
      const purchaseDataObj = JSON.parse(result.purchaseData) as InAppPurchaseData;
      hilog.info(DOMAIN, TAG, `Purchase success: ${purchaseDataObj.purchaseOrderId}`);
      
      return purchaseDataObj;

    } catch (error) {
      const err = error as BusinessError;
      // 1001860000: User cancelled
      if (err.code === 1001860000) {
        hilog.info(DOMAIN, TAG, 'User cancelled purchase');
        return null; // Silent return
      }
      hilog.error(DOMAIN, TAG, `Purchase failed: ${err.code} - ${err.message}`);
      // ArkTS strict mode requires throwing Error objects
      throw new Error(`IAP Error ${err.code}: ${err.message}`);
    }
  }
}

// Ensure PurchaseData interface exists if not exported by kit
// Based on docs: InAppPurchaseData
export interface InAppPurchaseData {
    applicationId?: string;
    autoRenewStatus?: number;
    orderId?: string;
    packageDesc?: string;
    productId?: string;
    productName?: string;
    purchaseOrderId?: string;
    purchaseTime?: number;
    purchaseToken?: string;
    purchaseType?: number;
    developerPayload?: string;
}
