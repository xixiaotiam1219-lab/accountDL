import { curves } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';

@Component
export struct AddMenuSheet {
  @Consume('pageStack') pageStack: NavPathStack;
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('showVipTheme') showVipTheme: boolean = true;
  
  // Animation Settings
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6;
  @StorageLink('isPointLightEnabled') isPointLightEnabled: boolean = true;

  @StorageLink('showAddSheet') @Watch('onAddSheetChange') showAddSheet: boolean = false;
  
  @State addSheetCard1Visible: boolean = false;
  @State addSheetCard2Visible: boolean = false;
  @State addSheetCard3Visible: boolean = false;
  @State pressedIndex: number = -1; // 记录当前按下的按钮索引

  aboutToAppear() {
    // Initialize state based on current valid
    if (this.showAddSheet) {
        this.onAddSheetChange();
    }
  }

  onAddSheetChange() {
    if (this.showAddSheet) {
      this.addSheetCard1Visible = false;
      this.addSheetCard2Visible = false;
      this.addSheetCard3Visible = false;

      if (this.isAnimationEnabled) {
        const duration = this.animationDuration;
        const damping = this.animationDamping;
        const response = this.animationResponse;

        // Staggered animation for list items
        setTimeout(() => {
            animateTo({ curve: curves.springMotion(response, damping) }, () => {
                this.addSheetCard1Visible = true;
            })
        }, 50);

        setTimeout(() => {
            animateTo({ curve: curves.springMotion(response, damping) }, () => {
                this.addSheetCard2Visible = true;
            })
        }, 150);

        setTimeout(() => {
            animateTo({ curve: curves.springMotion(response, damping) }, () => {
                this.addSheetCard3Visible = true;
            })
        }, 250);
      } else {
         this.addSheetCard1Visible = true;
         this.addSheetCard2Visible = true;
         this.addSheetCard3Visible = true;
      }
    } else {
        // Reset
         this.addSheetCard1Visible = false;
         this.addSheetCard2Visible = false;
         this.addSheetCard3Visible = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      // 添加服务订阅
      Row({ space: 16 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.plus_circle'))
            .fontSize(32)
            .fontColor([this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
        }
        .width(56)
        .height(56)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text('添加服务订阅')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('记录您的会员订阅服务')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 8, color: '#0A000000', offsetY: 2 })
      .opacity(this.addSheetCard1Visible ? 1 : 0)
      .translate({ y: this.addSheetCard1Visible ? 0 : 20 })
      .scale({ 
        x: this.addSheetCard1Visible ? (this.pressedIndex === 0 ? 0.95 : 1) : 0.9, 
        y: this.addSheetCard1Visible ? (this.pressedIndex === 0 ? 0.95 : 1) : 0.9 
      })
      .animation({ 
        duration: this.isAnimationEnabled ? this.animationDuration : 0,
        curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
      })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.pressedIndex === 0 ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (!this.isPointLightEnabled) return;
        if (event.type === TouchType.Down) {
          this.pressedIndex = 0;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedIndex = -1;
        }
      })
      .onClick(() => {
        this.showAddSheet = false;
        setTimeout(() => {
          this.pageStack.removeByName('AddSubscription');
          const params: Record<string, Object> = { 'initialType': 'subscription' };
          this.pageStack.pushPathByName('AddSubscription', params);
        }, 300);
      })

      // 添加团购订阅
      Row({ space: 16 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.bag'))
            .fontSize(32)
            .fontColor([this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
        }
        .width(56)
        .height(56)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text('添加团购订阅')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('记录您的团购券')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 8, color: '#0A000000', offsetY: 2 })
      .opacity(this.addSheetCard2Visible ? 1 : 0)
      .translate({ y: this.addSheetCard2Visible ? 0 : 20 })
      .scale({ 
        x: this.addSheetCard2Visible ? (this.pressedIndex === 1 ? 0.95 : 1) : 0.9, 
        y: this.addSheetCard2Visible ? (this.pressedIndex === 1 ? 0.95 : 1) : 0.9 
      })
      .animation({ 
        duration: this.isAnimationEnabled ? this.animationDuration : 0,
        curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
      })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.pressedIndex === 1 ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (!this.isPointLightEnabled) return;
        if (event.type === TouchType.Down) {
          this.pressedIndex = 1;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedIndex = -1;
        }
      })
      .onClick(() => {
        this.showAddSheet = false;
        setTimeout(() => {
          this.pageStack.removeByName('AddSubscription');
          const params: Record<string, Object> = { 'initialType': 'groupBuy' }; 
          this.pageStack.pushPathByName('AddSubscription', params);
        }, 300);
      })

      // 发现服务市场
      Row({ space: 16 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(32)
            .fontColor([this.isNewYearTheme ? '#FFD700' : (this.showVipTheme ? $r('app.color.vip_gold') : $r('app.color.brand_color'))])
        }
        .width(56)
        .height(56)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 4 }) {
          Text('推荐服务模板')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('浏览推荐的订阅服务模板')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(20)
      .shadow({ radius: 8, color: '#0A000000', offsetY: 2 })
      .opacity(this.addSheetCard3Visible ? 1 : 0)
      .translate({ y: this.addSheetCard3Visible ? 0 : 20 })
      .scale({ 
        x: this.addSheetCard3Visible ? (this.pressedIndex === 2 ? 0.95 : 1) : 0.9, 
        y: this.addSheetCard3Visible ? (this.pressedIndex === 2 ? 0.95 : 1) : 0.9 
      })
      .animation({ 
        duration: this.isAnimationEnabled ? this.animationDuration : 0,
        curve: this.isAnimationEnabled ? curves.springMotion(this.animationResponse, this.animationDamping) : Curve.Linear 
      })
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pointLight({
          sourceType: this.pressedIndex === 2 ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER
        })
        .buildEffect())
      .onTouch((event: TouchEvent) => {
        if (!this.isPointLightEnabled) return;
        if (event.type === TouchType.Down) {
          this.pressedIndex = 2;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedIndex = -1;
        }
      })
      .onClick(() => {
        this.showAddSheet = false;
        setTimeout(() => {
          this.pageStack.removeByName('SubscriptionMarketplace');
          this.pageStack.pushPathByName('SubscriptionMarketplace', null);
        }, 300);
      })
    }
    .width('100%')
    .padding(20)
  }
}
