import { curves } from '@kit.ArkUI';

export interface PieData {
  name: string;
  value: number;
  color: string;
  percentage: number;
}

export interface PieLabel {
  name: string;
  percentage: string;
  x: number;
  y: number;
  align: TextAlign;
  color: string | number | Resource;
  subColor: string | number | Resource;
}

@Component
export struct PieChart {
  @Prop @Watch('onDataChanged') data: PieData[] = [];
  @Prop @Watch('onDataChanged') isNewYearTheme: boolean = false;
  @Prop @Watch('onDataChanged') showVipTheme: boolean = false;

  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6

  @State animProgress: number = 0;
  @State canvasWidth: number = 0;
  @State canvasHeight: number = 0;
  @State labels: PieLabel[] = [];

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  onDataChanged() {
    this.draw();
  }

  aboutToAppear() {
    if (this.isAnimationEnabled) {
      animateTo({
        curve: curves.springMotion(this.animationResponse, this.animationDamping),
        onFinish: () => {
          this.animProgress = 1;
          this.draw();
        }
      }, () => {
        this.animProgress = 1;
      });
    } else {
      this.animProgress = 1;
    }
  }

  build() {
    Column() {
      Stack() {
        Canvas(this.context)
        .width('100%')
        .height(240)
        .onReady(() => {
          this.draw();
        })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.canvasWidth = newValue.width as number;
          this.canvasHeight = newValue.height as number;
          this.draw();
        })
        
      // Overlay Text Labels
      if (this.animProgress > 0.8) {
        ForEach(this.labels, (label: PieLabel) => {
          Column() {
             Text(label.name)
               .fontSize(11)
               .fontColor(label.color)
               .maxLines(1)
               .textOverflow({ overflow: TextOverflow.MARQUEE })
               .textAlign(label.align)
               .width(80) // Limit width to trigger marquee
             Text(label.percentage)
               .fontSize(10)
               .fontColor(label.subColor)
               .textAlign(label.align)
               .width(80)
          }
          .position({ x: label.x, y: label.y })
          .markAnchor({ x: label.align === TextAlign.End ? '100%' : '0%', y: '50%' })
          .alignItems(label.align === TextAlign.End ? HorizontalAlign.End : HorizontalAlign.Start)
        })
      }
    }
    .width('100%')
    
    // Legend Area
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.data, (item: PieData) => {
        Row() {
          Circle().width(8).height(8).fill(item.color).margin({ right: 4 })
          Text(item.name)
            .fontSize(10)
            .fontColor(this.isNewYearTheme || this.showVipTheme ? '#DDDDDD' : $r('app.color.text_secondary'))
        }
        .margin({ right: 12, bottom: 4 })
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
    }
  }
  
  draw() {
    if (this.canvasWidth === 0 || this.canvasHeight === 0) return;
    
    const ctx = this.context;
    const width = this.canvasWidth;
    const height = this.canvasHeight;
    const radius = Math.min(width, height) / 2 * 0.6; 
    const centerX = width / 2;
    const centerY = height / 2;

    ctx.clearRect(0, 0, width, height);

    if (this.data.length === 0) {
      this.labels = [];
      return;
    }

    let startAngle = -Math.PI / 2; 
    const newLabels: PieLabel[] = [];

    this.data.forEach((item) => {
      const sweepAngle = (item.percentage / 100) * (Math.PI * 2) * this.animProgress;
      const endAngle = startAngle + sweepAngle;

      ctx.beginPath();
      ctx.moveTo(centerX, centerY);
      ctx.arc(centerX, centerY, radius, startAngle, endAngle);
      ctx.closePath();
      ctx.fillStyle = item.color;
      ctx.fill();

      // Draw Lines and Calculate Label Positions (only if percentage is significant)
      if (item.percentage > 3 && this.animProgress > 0.8) {
        const midAngle = startAngle + sweepAngle / 2;
        
        // 1. Line Start
        const lineStartRadius = radius * 1.05;
        const lineStartX = centerX + Math.cos(midAngle) * lineStartRadius;
        const lineStartY = centerY + Math.sin(midAngle) * lineStartRadius;

        // 2. Elbow
        const elbowRadius = radius * 1.25;
        const elbowX = centerX + Math.cos(midAngle) * elbowRadius;
        const elbowY = centerY + Math.sin(midAngle) * elbowRadius;

        // 3. End Point
        const isRightSide = Math.cos(midAngle) >= 0;
        const extension = 20;
        const endX = isRightSide ? elbowX + extension : elbowX - extension;
        const endY = elbowY;

        // Draw Line
        ctx.beginPath();
        ctx.strokeStyle = this.isNewYearTheme || this.showVipTheme ? '#FFFFFF' : '#888888'; // Keep line gray in standard mode for now, or adapt if needed
        ctx.lineWidth = 1;
        ctx.moveTo(lineStartX, lineStartY);
        ctx.lineTo(elbowX, elbowY);
        ctx.lineTo(endX, endY);
        ctx.stroke();
        
        const textPadding = 4;
        const textX = isRightSide ? endX + textPadding : endX - textPadding;

        newLabels.push({
          name: item.name,
          percentage: `${item.percentage.toFixed(1)}%`,
          x: textX,
          y: endY,
          align: isRightSide ? TextAlign.Start : TextAlign.End,
          color: this.isNewYearTheme || this.showVipTheme ? '#FFFFFF' : $r('app.color.text_primary'),
          subColor: this.isNewYearTheme || this.showVipTheme ? '#DDDDDD' : $r('app.color.text_secondary')
        });
      }

      startAngle += (item.percentage / 100) * (Math.PI * 2); 
    });
    
    // Draw hole for Donut chart effect
    ctx.beginPath();
    ctx.arc(centerX, centerY, radius * 0.55, 0, Math.PI * 2);
    ctx.globalCompositeOperation = 'destination-out';
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
    
    // Update labels state only if changed to avoid loop
    if (JSON.stringify(this.labels) !== JSON.stringify(newLabels)) {
       this.labels = newLabels;
    }
  }
}