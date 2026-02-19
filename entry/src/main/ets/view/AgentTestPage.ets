/*
 * 这是一个极简的智能体测试页，用于验证 Intent Executor 的连通性。
 * 集成了 FunctionComponent 以支持真实的智能体交互测试。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PromptAction, window } from '@kit.ArkUI';
import InsightIntentExecutorImpl from '../entryability/InsightIntentExecutorImpl';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { FunctionComponent, FunctionController } from '@kit.AgentFrameworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Builder
export function AgentTestPageBuilder(name: string, param: Object) {
  AgentTestPage()
}

@Component
export struct AgentTestPage {
  @State logText: string = '等待测试...\n';
  private executor: InsightIntentExecutorImpl = new InsightIntentExecutorImpl();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  
  // Agent Props
  private controller: FunctionController = new FunctionController();
  // 使用与 HomeView 一致的 Agent ID
  private agentId: string = 'agent8e0a95d14e744348995f208388a951c2';

  build() {
    HdsNavDestination() {
      Column({ space: 16 }) {
        Text("智能体通信连通性测试")
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10 })

        // 1. FunctionComponent 测试区 (用户要求的原生组件)
        Column({ space: 8 }) {
          Text("原生智能体组件 (FunctionComponent)")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start)
          
          Row() {
            if (deviceInfo.distributionOSApiVersion >= 60100) {
              FunctionComponent({
                agentId: this.agentId,
                onError: (err: BusinessError) => {
                  this.logError(`Agent err: ${JSON.stringify(err)}`);
                },
                options: {
                  title: '点击唤起智能体', 
                  queryText: '使用显示全部订阅工具，直接打印工具返回的数据包'
                },
                controller: this.controller
              })
              .height(50)
              .layoutWeight(1)
            } else {
              Text("当前系统版本不支持 FunctionComponent")
                .fontColor(Color.Red)
            }
          }
          .width('100%')
          .padding(8)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
        }

        Divider().color($r('app.color.divider_color'))

        // 2. 内部模拟执行测试区
        Column({ space: 8 }) {
          Text("内部逻辑模拟 (直接触发 Executor)")
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start)

          Button("模拟触发 GetAllRecords")
            .width('100%')
            .height(45)
            .onClick(async () => {
              await this.runInternalTest('GetAllRecords');
            })
        }

        // 3. 日志区
        Text("执行日志:")
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)

        TextArea({ text: this.logText })
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .padding(10)
          .focusable(false)

        Button("清除日志")
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.logText = '';
          })
      }
      .width('100%')
      .height('100%')
      .padding(20)
    }
  }

  logError(msg: string) {
    this.logText += `[${new Date().toLocaleTimeString()}] ERROR: ${msg}\n`;
    hilog.error(0x0001, 'AgentTestPage', msg);
  }

  async runInternalTest(name: string) {
    this.logText += `[${new Date().toLocaleTimeString()}] 开始模拟内部意图: ${name}\n`;
    try {
      const result = await this.executor.onExecuteInUIAbilityBackgroundMode(name, {});
      this.logText += `[结果] Code: ${result.code}\n`;
      this.logText += `[原始数据] ${JSON.stringify(result.result, null, 2)}\n\n`;
    } catch (e) {
      this.logError(`执行异常: ${JSON.stringify(e)}`);
    }
  }
}
