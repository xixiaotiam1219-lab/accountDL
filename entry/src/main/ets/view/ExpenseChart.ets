import { curves } from '@kit.ArkUI';

// 定义点的接口
interface ChartPoint {
  x: number;
  y: number;
}

@Component
export struct ExpenseChart {
  @Prop @Watch('onDataChanged') monthlyData: number[] = [];
  @Prop @Watch('onDataChanged') labels: string[] = [];
  @Prop @Watch('onDataChanged') isVip: boolean = false;
  @Prop @Watch('onDataChanged') showVipTheme: boolean = true;
  @Prop @Watch('onDataChanged') isNewYearTheme: boolean = false;
  
  // Unified Animation System
  @StorageLink('isAnimationEnabled') isAnimationEnabled: boolean = true;
  @StorageLink('animationDuration') animationDuration: number = 400;
  @StorageLink('animationDamping') animationDamping: number = 0.5;
  @StorageLink('animationResponse') animationResponse: number = 0.6
  
  @State animProgress: number = 0; // 动画进度 0-1
  
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  
  // 计算 Canvas 需要的宽度（基于数据点数量）
  getCanvasWidth(): number {
    // 每个数据点占 60px，最小宽度 100%
    return Math.max(this.monthlyData.length * 60, 360);
  }

  onDataChanged() {
    this.drawChart();
  }

  aboutToAppear() {
    if (this.isAnimationEnabled) {
      animateTo({
        curve: curves.springMotion(this.animationResponse, this.animationDamping),
        onFinish: () => {
          // 确保动画结束时绘制完整
          this.animProgress = 1;
          this.drawChart();
        }
      }, () => {
        this.animProgress = 1;
      });
    } else {
      this.animProgress = 1;
    }
  }

  build() {
    Scroll() {
      Column() {
        Canvas(this.context)
          .width(this.getCanvasWidth())
          .height(200)
          .onReady(() => {
            this.drawChart();
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
             this.drawChart();
          })
      }
      .width(this.getCanvasWidth())
      .height(200)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(200)
  }

  drawChart() {
    const ctx = this.context;
    const width = this.getCanvasWidth();
    const height = 200;
    
    ctx.clearRect(0, 0, width, height);
    
    if (this.monthlyData.length === 0) return;

    // 应用动画进度：影响 Y 轴高度或整体透明度
    const globalAlpha = this.animProgress;
    ctx.globalAlpha = 0.2 + 0.8 * globalAlpha; // 留一点底色

    const maxVal = Math.max(...this.monthlyData, 100);
    const paddingLeft = 16;
    const paddingRight = 30;
    const paddingTop = 30;
    const paddingBottom = 35;
    const chartHeight = height - paddingTop - paddingBottom;
    const chartWidth = width - paddingLeft - paddingRight;
    const pointCount = this.monthlyData.length;
    const pointGap = chartWidth / (pointCount - 1 || 1);

    // 绘制网格线
    ctx.strokeStyle = '#333333';
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 4; i++) {
      const y = paddingTop + (chartHeight / 4) * i;
      ctx.beginPath();
      ctx.moveTo(paddingLeft, y);
      ctx.lineTo(width - paddingRight, y);
      ctx.stroke();
    }

    // 计算所有点的坐标
    const points: ChartPoint[] = [];
    this.monthlyData.forEach((value, index) => {
      const x = paddingLeft + index * pointGap;
      // 动画点坐标：value 乘以进度
      const animatedValue = value * this.animProgress;
      const y = paddingTop + chartHeight - (animatedValue / maxVal) * chartHeight;
      const point: ChartPoint = { x: x, y: y };
      points.push(point);
    });

    // 绘制填充区域
    ctx.beginPath();
    ctx.moveTo(paddingLeft, paddingTop + chartHeight);
    points.forEach((p, i) => {
        ctx.lineTo(p.x, p.y);
    });
    ctx.lineTo(points[points.length - 1].x, paddingTop + chartHeight);
    ctx.closePath();
    
    const gradient = ctx.createLinearGradient(0, paddingTop, 0, paddingTop + chartHeight);
    if (this.isNewYearTheme) {
       gradient.addColorStop(0, 'rgba(255, 36, 0, 0.4)');
       gradient.addColorStop(1, 'rgba(255, 36, 0, 0.05)');
    } else if (this.showVipTheme) {
      gradient.addColorStop(0, 'rgba(230, 192, 123, 0.4)');
      gradient.addColorStop(1, 'rgba(230, 192, 123, 0.05)');
    } else {
      gradient.addColorStop(0, 'rgba(10, 89, 247, 0.4)');
      gradient.addColorStop(1, 'rgba(10, 89, 247, 0.05)');
    }
    ctx.fillStyle = gradient;
    ctx.fill();

    // 绘制折线
    ctx.beginPath();
    ctx.strokeStyle = this.isNewYearTheme ? '#FF2400' : (this.showVipTheme ? '#E6C07B' : '#0A59F7');
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    
    points.forEach((p, i) => {
      if (i === 0) {
        ctx.moveTo(p.x, p.y);
      } else {
        ctx.lineTo(p.x, p.y);
      }
    });
    ctx.stroke();

    // 绘制数据点和标签
    points.forEach((p, index) => {
      const value = this.monthlyData[index];
      
      // 数据点
      ctx.beginPath();
      ctx.fillStyle = this.isNewYearTheme ? '#FF2400' : (this.showVipTheme ? '#E6C07B' : '#0A59F7');
      ctx.arc(p.x, p.y, 4, 0, Math.PI * 2);
      ctx.fill();
      
      // 白色内圈
      ctx.beginPath();
      ctx.fillStyle = '#FFFFFF';
      ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
      ctx.fill();

      // 数值标签（只显示非零值, 且动画进度足够高时）
      if (value > 0 && this.animProgress > 0.8) {
        ctx.fillStyle = '#AAAAAA';
        ctx.font = '10vp sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(`¥${value.toFixed(0)}`, p.x, p.y - 10);
      }

      // 月份标签
      ctx.fillStyle = '#888888';
      ctx.font = '11vp sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(this.labels[index], p.x, height - paddingBottom + 18);
    });
    
    // 重置 Alpha
    ctx.globalAlpha = 1.0;
  }
}
