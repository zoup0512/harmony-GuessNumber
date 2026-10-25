import { Theme } from './Theme';

/**
 * DeleteKeyIcon — 删除键图标（左向箭头 + ×）
 * ⌫ 字形在部分设备字体中墨迹偏左，textAlign 无法保证视觉居中，
 * 改用固定 24×24 视口自绘，由容器决定居中。
 */
@Component
export struct DeleteKeyIcon {
  @Prop iconSize: number = 22;
  @Prop color: string = Theme.TEXT_FAINT;

  build() {
    Shape() {
      // 主体（左尖角五边形）与 × 合为一个 Path，避免 if 分支漏掉视口变换。
      Path()
        .commands('M3 12 L8 5 Q8.5 4.3 9.4 4.3 H18.6 Q20.6 4.3 20.6 6.3 V17.7 Q20.6 19.7 18.6 19.7 H9.4 Q8.5 19.7 8 19 Z ' +
          'M11.6 9.3 L16.9 14.7 M16.9 9.3 L11.6 14.7')
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth('1.8px')
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    // Path 命令使用 px，视口与描边必须使用相同单位。
    .viewPort({ x: '0px', y: '0px', width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize)
    .accessibilityLevel('no')
  }
}
