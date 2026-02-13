@Component
export struct BackgroundWatermark {
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;
  @StorageLink('watermarkImage') watermarkImage: string = '';
  @StorageLink('watermarkOpacity') watermarkOpacity: number = 0.2;
  @StorageLink('watermarkOffsetX') watermarkOffsetX: number = 0;
  @StorageLink('watermarkOffsetY') watermarkOffsetY: number = 0;

  // Text Watermark States
  @StorageLink('isTextWatermarkEnabled') isTextWatermarkEnabled: boolean = false;
  @StorageLink('watermarkText') watermarkText: string = '记得订阅';

  build() {
    Stack() {
      // 1. Custom Image Watermark (Highest Priority)
      if (this.watermarkImage) {
        Image(this.watermarkImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.watermarkOpacity)
          .translate({ x: this.watermarkOffsetX, y: this.watermarkOffsetY })
          .hitTestBehavior(HitTestMode.None)
          .hitTestBehavior(HitTestMode.None)
      } 

      // 2. Text Watermark (AccountDL - Persistent if enabled)
      if (this.isTextWatermarkEnabled && this.isNewYearTheme) {
         Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceAround, alignContent: FlexAlign.SpaceAround }) {
           ForEach([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20], (item: number) => {
             Text(this.watermarkText)
               .fontSize(20)
               .fontWeight(FontWeight.Bold)
               .fontColor(this.isNewYearTheme ? Color.White : $r('app.color.text_primary'))
               .opacity(0.06)
               .rotate({ angle: -30 })
               .margin(40)
           })
         }
         .width('100%')
         .height('100%')
         .hitTestBehavior(HitTestMode.None)
      }

      // 3. New Year Festive Pattern (Fallback if enabled and in New Year theme)
      if (this.isNewYearTheme && this.isNewYearWatermarkEnabled) {
          Column() {
             // 9 Rows x 5 Cols Grid (Expanded for overflow)
             ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], (row: number) => {
               Row() {
                  ForEach([1, 2, 3, 4, 5], (col: number) => {
                     // Cycle through elements: Fu -> Coin -> Flower
                     Text((row + col) % 3 === 0 ? '福' : ((row + col) % 3 === 1 ? '◎' : '❀'))
                       .fontSize((row + col) % 3 === 0 ? 60 : 50)
                       .fontWeight(FontWeight.Bold)
                       .fontColor($r('app.color.new_year_watermark'))
                       .opacity($r('app.float.watermark_opacity_deco'))
                       .rotate({ angle: (row * col) % 2 === 0 ? 5 : -5 }) 
                  })
               }
               .width('100%')
               .justifyContent(FlexAlign.SpaceEvenly)
             })
          }
          .width('120%')
          .height('120%')
          .position({ x: '-10%', y: '-10%' })
          .justifyContent(FlexAlign.SpaceEvenly)
          .hitTestBehavior(HitTestMode.None)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
