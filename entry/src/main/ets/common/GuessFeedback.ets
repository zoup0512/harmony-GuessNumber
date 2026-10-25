import { Theme } from './Theme';

@Component
export struct FeedbackIcon {
  @Prop exact: boolean = true;
  @Prop iconSize: number = 22;

  build() {
    Shape() {
      Path()
        .commands('M6 3 H18 Q21 3 21 6 V18 Q21 21 18 21 H6 Q3 21 3 18 V6 Q3 3 6 3 Z')
        .fill(Color.Transparent)
        .stroke(this.exact ? Theme.POSITION_EXACT : Theme.POSITION_MISPLACED)
        .strokeWidth(1.8)
      if (this.exact) {
        Path()
          .commands('M7.5 12 L10.5 15 L16.5 9')
          .fill(Color.Transparent)
          .stroke(Theme.POSITION_EXACT)
          .strokeWidth(1.8)
          .strokeLineCap(LineCapStyle.Round)
          .strokeLineJoin(LineJoinStyle.Round)
      } else {
        Path()
          .commands('M7 9 H17 M14.5 6.5 L17 9 L14.5 11.5 M17 15 H7 M9.5 12.5 L7 15 L9.5 17.5')
          .fill(Color.Transparent)
          .stroke(Theme.POSITION_MISPLACED)
          .strokeWidth(1.8)
          .strokeLineCap(LineCapStyle.Round)
          .strokeLineJoin(LineJoinStyle.Round)
      }
    }
    .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    .width(this.iconSize)
    .height(this.iconSize)
    .accessibilityLevel('no')
  }
}

@Component
export struct FeedbackBadge {
  @Prop count: number = 0;
  @Prop exact: boolean = true;

  build() {
    Row({ space: 6 }) {
      FeedbackIcon({ exact: this.exact })
      Text(this.exact ? '正位' : '错位')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT)
      Text(this.count.toString())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.exact ? Theme.POSITION_EXACT_BG : Theme.POSITION_MISPLACED_BG)
    .borderRadius(10)
    .accessibilityGroup(true)
    .accessibilityText((this.exact ? '正位 ' : '错位 ') + this.count.toString() + ' 个，' +
      (this.exact ? '数字和位置都正确' : '数字正确，位置不对'))
  }
}

@Component
export struct GuessFeedback {
  @Prop exact: number = 0;
  @Prop misplaced: number = 0;

  build() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      FeedbackBadge({ count: this.exact, exact: true })
        .margin({ right: 8, bottom: 6 })
      FeedbackBadge({ count: this.misplaced, exact: false })
        .margin({ bottom: 6 })
    }
    .width('100%')
  }
}
