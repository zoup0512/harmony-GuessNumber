/**
 * RadarChart.ets — 六维雷达图
 * 实线多边形为本期，虚线为上期；顶点按维度着色，逐轴弹出动画。
 * 轴标签为独立 Text，可点击、可被无障碍读取。
 */
import { DIM_COUNT, DIMENSIONS, DimensionInfo } from '../model/BrainProfile';
import { Theme } from './Theme';

const LABEL_W: number = 72;
const LABEL_H: number = 42;

@Component
export struct RadarChart {
  @Prop @Watch('onValuesChanged') values: number[] = [0, 0, 0, 0, 0, 0];
  @Prop @Watch('requestDraw') previous: number[] = [];
  @Prop @Watch('requestDraw') selected: number = -1;
  @Prop @Watch('onValuesChanged') placeholder: boolean = false;
  @Prop @Watch('requestDraw') chartSize: number = 300;
  onSelect: (index: number) => void = (index: number): void => {};
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;
  private animId: number = -1;
  private animStart: number = 0;
  private progress: number[] = [1, 1, 1, 1, 1, 1];

  aboutToDisappear(): void {
    this.stopAnim();
  }

  onValuesChanged(): void {
    this.startAnim();
  }

  requestDraw(): void {
    this.draw();
  }

  private stopAnim(): void {
    if (this.animId >= 0) {
      clearInterval(this.animId);
      this.animId = -1;
    }
  }

  private startAnim(): void {
    if (!this.ready) {
      return;
    }
    this.stopAnim();
    this.animStart = Date.now();
    this.progress = [0, 0, 0, 0, 0, 0];
    this.animId = setInterval(() => {
      const elapsed = Date.now() - this.animStart;
      let done = true;
      for (let i = 0; i < DIM_COUNT; i++) {
        const t = Math.max(0, Math.min(1, (elapsed - i * 70) / 650));
        this.progress[i] = RadarChart.easeOutBack(t);
        if (t < 1) {
          done = false;
        }
      }
      this.draw();
      if (done) {
        this.stopAnim();
      }
    }, 16);
  }

  private static easeOutBack(t: number): number {
    const c1 = 1.4;
    const c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  }

  private radius(): number {
    return this.chartSize / 2 - 50;
  }

  private angle(i: number): number {
    return -Math.PI / 2 + i * Math.PI * 2 / DIM_COUNT;
  }

  private pointX(i: number, r: number): number {
    return this.chartSize / 2 + r * Math.cos(this.angle(i));
  }

  private pointY(i: number, r: number): number {
    return this.chartSize / 2 + r * Math.sin(this.angle(i));
  }

  private tracePolygon(values: number[], scale: number[]): void {
    const r = this.radius();
    this.ctx.beginPath();
    for (let i = 0; i < DIM_COUNT; i++) {
      const v = Math.max(0, values[i] ?? 0) / 100 * scale[i];
      const x = this.pointX(i, r * v);
      const y = this.pointY(i, r * v);
      if (i === 0) {
        this.ctx.moveTo(x, y);
      } else {
        this.ctx.lineTo(x, y);
      }
    }
    this.ctx.closePath();
  }

  private draw(): void {
    if (!this.ready) {
      return;
    }
    const c = this.ctx;
    const size = this.chartSize;
    const cx = size / 2;
    const cy = size / 2;
    const r = this.radius();
    const full: number[] = [1, 1, 1, 1, 1, 1];
    c.clearRect(0, 0, size, size);
    c.lineJoin = 'round';

    // 网格：四层六边形，由外向内交替填充
    for (let level = 4; level >= 1; level--) {
      const ring: number[] = [];
      for (let i = 0; i < DIM_COUNT; i++) {
        ring.push(level * 25);
      }
      this.tracePolygon(ring, full);
      c.fillStyle = level % 2 === 0 ? '#F1F6F3' : '#FFFFFF';
      c.fill();
      c.strokeStyle = Theme.STROKE;
      c.lineWidth = 1;
      c.stroke();
    }
    // 轴线
    for (let i = 0; i < DIM_COUNT; i++) {
      c.beginPath();
      c.moveTo(cx, cy);
      c.lineTo(this.pointX(i, r), this.pointY(i, r));
      c.strokeStyle = this.selected === i ? DIMENSIONS[i].color : Theme.STROKE;
      c.lineWidth = this.selected === i ? 1.5 : 1;
      c.stroke();
    }

    if (this.placeholder) {
      c.setLineDash([5, 5]);
      this.tracePolygon([55, 55, 55, 55, 55, 55], this.progress);
      c.fillStyle = 'rgba(92,109,102,0.08)';
      c.fill();
      c.strokeStyle = '#A5B2AC';
      c.lineWidth = 1.5;
      c.stroke();
      c.setLineDash([]);
      return;
    }

    // 上期（虚线）
    if (this.previous.length === DIM_COUNT) {
      c.setLineDash([5, 4]);
      this.tracePolygon(this.previous, full);
      c.strokeStyle = '#8E9C95';
      c.lineWidth = 1.5;
      c.stroke();
      c.setLineDash([]);
    }

    // 本期
    const gradient = c.createRadialGradient(cx, cy, 0, cx, cy, r);
    gradient.addColorStop(0, 'rgba(35,122,99,0.12)');
    gradient.addColorStop(1, 'rgba(35,122,99,0.34)');
    this.tracePolygon(this.values, this.progress);
    c.fillStyle = gradient;
    c.fill();
    c.strokeStyle = Theme.PRIMARY;
    c.lineWidth = 2.5;
    c.stroke();

    // 顶点
    for (let i = 0; i < DIM_COUNT; i++) {
      const v = Math.max(0, this.values[i] ?? 0) / 100 * this.progress[i];
      const x = this.pointX(i, r * v);
      const y = this.pointY(i, r * v);
      if (this.selected === i) {
        c.beginPath();
        c.arc(x, y, 11, 0, Math.PI * 2);
        c.fillStyle = DIMENSIONS[i].bg;
        c.fill();
      }
      c.beginPath();
      c.arc(x, y, this.selected === i ? 6.5 : 5, 0, Math.PI * 2);
      c.fillStyle = DIMENSIONS[i].color;
      c.fill();
      c.strokeStyle = '#FFFFFF';
      c.lineWidth = 2;
      c.stroke();
    }
  }

  private nearestAxis(x: number, y: number): number {
    const dx = x - this.chartSize / 2;
    const dy = y - this.chartSize / 2;
    if (Math.sqrt(dx * dx + dy * dy) < 14) {
      return -1;
    }
    const a = Math.atan2(dy, dx) + Math.PI / 2;
    const step = Math.PI * 2 / DIM_COUNT;
    return ((Math.round(a / step) % DIM_COUNT) + DIM_COUNT) % DIM_COUNT;
  }

  private labelText(i: number): string {
    return this.placeholder ? '--' : (this.values[i] ?? 0).toString();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.ctx)
        .width(this.chartSize)
        .height(this.chartSize)
        .onReady(() => {
          this.ready = true;
          this.startAnim();
        })
        .onAreaChange(() => this.draw())
        .accessibilityLevel('no')
        .onClick((e: ClickEvent) => {
          const idx = this.nearestAxis(e.x, e.y);
          if (idx >= 0) {
            this.onSelect(idx);
          }
        })

      ForEach(DIMENSIONS, (d: DimensionInfo, i: number) => {
        Column({ space: 1 }) {
          Text(DIMENSIONS[i].name)
            .fontSize(12)
            .fontWeight(this.selected === i ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.selected === i ? DIMENSIONS[i].color : Theme.TEXT_SUB)
          Text(this.labelText(i))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.placeholder ? Theme.TEXT_FAINT : DIMENSIONS[i].color)
        }
        .width(LABEL_W)
        .height(LABEL_H)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor(this.selected === i ? DIMENSIONS[i].bg : Color.Transparent)
        .position({
          x: this.pointX(i, this.radius() + 28) - LABEL_W / 2,
          y: this.pointY(i, this.radius() + 24) - LABEL_H / 2
        })
        .accessibilityText(DIMENSIONS[i].name + ' ' + this.labelText(i) + ' 分' +
          (this.selected === i ? '，已选中' : ''))
        .onClick(() => this.onSelect(i))
      }, (d: DimensionInfo, i: number) => d.name + i.toString())
    }
    .width(this.chartSize)
    .height(this.chartSize)
  }
}
