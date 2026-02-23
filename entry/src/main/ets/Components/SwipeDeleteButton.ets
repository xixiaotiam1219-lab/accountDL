import { SubscriptionModel } from '../model/SubscriptionModel';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export  struct SwipeDeleteButton {
  @Prop item: SubscriptionModel;
  @Prop isStart: boolean = false;
  onDelete: (item: SubscriptionModel) => void = () => {};
  @State isPressed: boolean = false;
  @State lightSource: hdsEffect.PointLightSourceType = hdsEffect.PointLightSourceType.NONE;
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;
  @StorageLink('isOnline') isOnline: boolean = true;

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.trash')).fontSize(24).fontColor([Color.White])
    }
    .width(48).height(48)
    .backgroundColor(Color.Red)
    .margin({
      bottom: 12,
      left: this.isStart ? 24 : 0,
      right: this.isStart ? 0 : 24
    })
    .zIndex(1)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.lightSource,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
      })
      .buildEffect())
    .scale({ x: this.isPressed ? 0.9 : 1, y: this.isPressed ? 0.9 : 1 })
    .animation({ duration: this.isAnimationEnabled ? 150 : 0, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        if (this.isAnimationEnabled && this.isPointLightEnabled) {
          this.isPressed = true;
          this.lightSource = hdsEffect.PointLightSourceType.BRIGHT;
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isPressed = false;
        this.lightSource = hdsEffect.PointLightSourceType.NONE;
      }
    })
    .onClick(() => {
      this.onDelete(this.item);
    })
  }
}
