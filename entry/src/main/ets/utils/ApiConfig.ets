/**
 * API 配置文件
 * 集中管理所有后端 API 地址
 */

// 后端服务基础地址
export const API_BASE_URL = 'https://jddy.sjyxxt.tech';

// 智谱 AI 配置
export const ZHIPU_API_BASE_URL = 'https://open.bigmodel.cn/api/paas/v4';
export const ZHIPU_API_TOKEN = '0b2a7b0901214a3b99d1c09f904fe552.YTMlfRF6wogmB14u';
export const ZHIPU_MODEL = 'glm-4v-flash';


interface ApiEndpoints {
  LOGIN: string;
  PUSH_TEST: string;
  UPDATE_PUSH_TOKEN: string;
  DELETE_PUSH_TOKEN: string;
  SYNC_PULL: string;
  SYNC_PUSH: string;
  CHECK_UPDATE: string;
}

// API 端点
export const API_ENDPOINTS: ApiEndpoints = {
  // 用户认证
  LOGIN: `${API_BASE_URL}/api/login`,
  
  // 推送服务
  PUSH_TEST: `${API_BASE_URL}/api/push/test`,
  UPDATE_PUSH_TOKEN: `${API_BASE_URL}/api/user/push-token`, // Using correct main.py endpoint
  DELETE_PUSH_TOKEN: `${API_BASE_URL}/api/user/push-token`, // DELETE method
  
  // 数据同步
  SYNC_PULL: `${API_BASE_URL}/api/user/sync/pull`,
  SYNC_PUSH: `${API_BASE_URL}/api/user/sync/push`,

  // 版本更新
  CHECK_UPDATE: `${API_BASE_URL}/api/app/latest`
};
