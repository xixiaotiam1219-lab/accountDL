@Component
export struct NewYearWatermark {
  @StorageLink('isNewYearTheme') isNewYearTheme: boolean = false;
  @StorageLink('isNewYearWatermarkEnabled') isNewYearWatermarkEnabled: boolean = true;

  build() {
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 600 }))
    }
  }
}
