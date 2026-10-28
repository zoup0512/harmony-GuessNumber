import { Theme } from './Theme';
import { GuessRecord } from '../model/GameEngine';

@Component
export struct HistoryColumns {
  build() {
    Row({ space: 6 }) {
      Text('次')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
        .width(28)
      Text('猜测数字')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
        .layoutWeight(1)
      Text('正位')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
        .width(42)
        .textAlign(TextAlign.Center)
      Text('错位')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
        .width(42)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .accessibilityText('次数、猜测数字、正位数量、错位数量；最新在上')
  }
}

@Component
export struct HistoryRecord {
  @Prop record: GuessRecord;
  @Prop latest: boolean = false;
  @State availableWidth: number = 284;

  stacked(): boolean {
    const fontScale = this.getUIContext().fp2px(16) / this.getUIContext().vp2px(16);
    return this.availableWidth < 148 + this.record.guess.length * 28 * fontScale;
  }

  @Builder
  Digits() {
    Row({ space: 4 }) {
      ForEach(this.record.guess.split(''), (digit: string, index: number) => {
        Text(digit)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
          .textAlign(TextAlign.Center)
          .constraintSize({ minWidth: 20, minHeight: 32 })
          .padding({ left: 2, right: 2 })
          .backgroundColor(Theme.CARD_STRONG)
          .borderRadius(5)
      }, (digit: string, index: number) => index.toString())
    }
  }

  @Builder
  Count(count: number, exact: boolean) {
    Text(count.toString())
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor(exact ? Theme.POSITION_EXACT : Theme.POSITION_MISPLACED)
      .textAlign(TextAlign.Center)
      .constraintSize({ minHeight: 30 })
      .width(42)
      .backgroundColor(exact ? Theme.POSITION_EXACT_BG : Theme.POSITION_MISPLACED_BG)
      .borderRadius(6)
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(this.record.index.toString().padStart(2, '0'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
          .width(28)
        this.Digits()
        Blank()
        if (!this.stacked()) {
          this.Count(this.record.a, true)
          this.Count(this.record.b, false)
        }
      }
      .width('100%')
      if (this.stacked()) {
        Row({ space: 6 }) {
          Text('正位')
            .fontSize(12)
            .fontColor(Theme.TEXT_SUB)
          this.Count(this.record.a, true)
          Text('错位')
            .fontSize(12)
            .fontColor(Theme.TEXT_SUB)
          this.Count(this.record.b, false)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .justifyContent(FlexAlign.Center)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(this.latest ? Theme.PRIMARY_BG : Theme.CARD)
    .borderWidth({ bottom: 1 })
    .borderColor(Theme.STROKE)
    .onAreaChange((oldArea: Area, area: Area) => {
      this.availableWidth = Number(area.width);
    })
    .accessibilityGroup(true)
    .accessibilityText('第 ' + this.record.index.toString() + ' 次，猜测 ' +
      this.record.guess.split('').join(' ') + '，正位 ' + this.record.a.toString() +
      ' 个，错位 ' + this.record.b.toString() + ' 个' + (this.latest ? '，最新记录' : ''))
  }
}
