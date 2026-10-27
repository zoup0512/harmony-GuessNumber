import { GamePage } from '../views/GamePage';
import { TutorialPage } from '../views/TutorialPage';
import { Stats, StatsStore } from '../model/StatsStore';
import { DIFFICULTIES, Difficulty } from '../model/GameEngine';
import { Theme } from '../common/Theme';
import { FeedbackIcon, GuessFeedback } from '../common/GuessFeedback';
import { BoardIcon } from '../common/BoardIcon';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();
  @State stats: Stats = new Stats();
  @State legacyStats: Stats = new Stats();
  @State statsLoading: boolean = true;
  @State statsError: boolean = false;
  @State selectedDigits: number = 4;
  @State showRules: boolean = false;
  private statsRequest: number = 0;

  aboutToAppear(): void {
    this.loadStats();
    this.checkFirstLaunch();
  }

  loadStats(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    const digits = this.selectedDigits;
    const request = ++this.statsRequest;
    this.statsLoading = true;
    this.statsError = false;
    StatsStore.load(ctx, digits).then((s: Stats) => {
      if (request === this.statsRequest && digits === this.selectedDigits) {
        this.stats = s;
        this.statsLoading = false;
      }
    }).catch(() => {
      if (request === this.statsRequest && digits === this.selectedDigits) {
        this.statsLoading = false;
        this.statsError = true;
      }
    });
    StatsStore.loadLegacy(ctx).then((s: Stats) => {
      this.legacyStats = s;
    }).catch(() => {});
  }

  statsValue(value: number): string {
    return this.statsLoading || this.statsError ? '--' : value.toString();
  }

  difficultyName(): string {
    for (let i = 0; i < DIFFICULTIES.length; i++) {
      if (DIFFICULTIES[i].digits === this.selectedDigits) {
        return DIFFICULTIES[i].name;
      }
    }
    return '';
  }

  checkFirstLaunch(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    StatsStore.isTutorialDone(ctx).then((done: boolean) => {
      if (!done) {
        setTimeout(() => {
          this.pathStack.pushPathByName('tutorial', '', () => {
            this.loadStats();
          });
        }, 150);
      }
    });
  }

  solveRateText(): string {
    if (this.statsLoading || this.statsError || this.stats.played === 0) {
      return '--';
    }
    return Math.round(this.stats.wins * 100 / this.stats.played).toString() + '%';
  }

  @Builder
  PagesMap(name: string) {
    if (name === 'game') {
      GamePage()
    } else if (name === 'tutorial') {
      TutorialPage()
    }
  }

  @Builder
  HeroTiles() {
    Row({ space: 8 }) {
      ForEach(['1', '2', '3', '4'], (digit: string) => {
        Text(digit)
          .fontSize(25)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
          .width(48)
          .height(52)
          .textAlign(TextAlign.Center)
          .backgroundColor(Theme.CARD)
          .borderRadius(Theme.R_TILE)
          .borderWidth(1)
          .borderColor(Theme.STROKE)
      }, (digit: string) => digit)
    }
  }

  @Builder
  StatCell(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT)
      Text(label)
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
    }
    .layoutWeight(1)
  }

  @Builder
  StatsCard() {
    Column({ space: 14 }) {
      Row() {
        this.StatCell(this.statsValue(this.stats.played), '挑战局数')
        this.VDivider()
        this.StatCell(this.solveRateText(), '破解率')
        this.VDivider()
        this.StatCell(this.statsValue(this.stats.wins), '累计破解')
      }
      .width('100%')
      Divider().color(Theme.STROKE)
      Row() {
        Text('最佳破解')
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
        Blank()
        Text(this.statsLoading || this.statsError || this.stats.best === 0
          ? '--' : this.stats.best.toString() + ' 次机会')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  @Builder
  VDivider() {
    Column()
      .width(1)
      .height(26)
      .backgroundColor(Theme.STROKE)
  }

  @Builder
  DifficultyCard(d: Difficulty) {
    Column({ space: 7 }) {
      Text(d.name)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedDigits === d.digits ? Theme.PRIMARY : Theme.TEXT)
      Text(d.digits.toString() + ' 位数字')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
      Text(d.attempts.toString() + ' 次机会')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
    }
    .layoutWeight(1)
    .padding({ top: 16, bottom: 16, left: 4, right: 4 })
    .backgroundColor(this.selectedDigits === d.digits ? Theme.PRIMARY_BG : Theme.CARD)
    .borderRadius(Theme.R_CARD - 4)
    .borderWidth(this.selectedDigits === d.digits ? 2 : 1)
    .borderColor(this.selectedDigits === d.digits ? Theme.PRIMARY : Theme.STROKE)
    .accessibilityText(d.name + '，' + d.digits.toString() + ' 位数字，' + d.attempts.toString() + ' 次机会' +
      (this.selectedDigits === d.digits ? '，已选中' : ''))
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectedDigits = d.digits;
      this.loadStats();
    })
  }

  @Builder
  RulesSheet() {
    Column({ space: 14 }) {
      Text('玩法规则')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
      Scroll() {
        Column({ space: 12 }) {
          this.RuleLine('grid', '系统随机生成一组各位互不相同的数字（首位可以为 0），你要在限定次数内猜中它。')
          this.FeedbackRule(true, '正位：数字对、位置也对。例如答案 5234，猜 5346，数字 5 位置正确，正位 1 个。')
          this.FeedbackRule(false, '错位：数字对、位置不对。上例中 3 和 4 在答案里，但位置不对，错位 2 个。')
          GuessFeedback({ exact: 1, misplaced: 2 })
          Text('实际对局只给数量，不标出具体数字；两类不重复计数。双向箭头表示需要换位，不限定为相邻交换。')
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
            .lineHeight(20)
          this.RuleLine('keyboard', '键盘会自动禁用已输入的数字，避免重复；数字输满后自动提交，无需手动确认。')
          this.RuleLine('hint', '每局可用一次提示，随机揭示一位数字，但会消耗 1 次机会。')
          this.RuleLine('analysis', 'AI 分析每局可用 2 次（每次消耗 1 次机会）：只根据已有线索推理，告诉你剩余可能、数字判定，并推荐下一猜。')
          this.RuleLine('flag', '猜中即破解成功；用完机会后公布答案。计时仅记录用时，不会超时失败。')
          this.RuleLine('grid', '我的记录按难度分别统计：挑战局数为已结束的正式挑战数，破解率为其中成功破解的比例，累计破解为成功次数。中途退出和教学练习不计。')
          this.RuleLine('hint', '最佳破解为成功时消耗的最少机会，包含猜测、提示和 AI 分析。')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: '55%' })
      .scrollBar(BarState.Auto)
      Text('知道了')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.ON_PRIMARY)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(48)
        .backgroundColor(Theme.PRIMARY)
        .borderRadius(Theme.R_KEY)
        .onClick(() => {
          this.showRules = false;
        })
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 10, bottom: 30 })
  }

  @Builder
  FeedbackRule(exact: boolean, text: string) {
    Row({ space: 10 }) {
      FeedbackIcon({ exact: exact })
      Text(text)
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
        .lineHeight(21)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  RuleLine(icon: string, text: string) {
    Row({ space: 10 }) {
      BoardIcon({ kind: icon, iconSize: 18 })
      Text(text)
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
        .lineHeight(21)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Scroll() {
          Column() {
            this.HeroTiles()
            Text('数字解密')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.TEXT)
              .margin({ top: 18 })
            Text('读懂线索，享受想通的那一刻')
              .fontSize(14)
              .fontColor(Theme.TEXT_SUB)
              .margin({ top: 8 })
            Row({ space: 18 }) {
              Row({ space: 5 }) {
                FeedbackIcon({ exact: true, iconSize: 16 })
                Text('数字与位置都对')
                  .fontSize(12)
                  .fontColor(Theme.TEXT_SUB)
              }
              Row({ space: 5 }) {
                FeedbackIcon({ exact: false, iconSize: 16 })
                Text('数字对，位置不对')
                  .fontSize(12)
                  .fontColor(Theme.TEXT_SUB)
              }
            }
            .margin({ top: 18, bottom: 28 })

            Text('选择难度')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 12 })
            Row({ space: 10 }) {
              ForEach(DIFFICULTIES, (d: Difficulty) => {
                this.DifficultyCard(d)
              }, (d: Difficulty) => d.digits.toString())
            }
            .width('100%')

            Text('我的记录 · ' + this.difficultyName())
              .fontSize(13)
              .fontColor(Theme.TEXT_SUB)
              .alignSelf(ItemAlign.Start)
              .margin({ top: 24, bottom: 10 })
            this.StatsCard()
            if (this.statsError) {
              Text('记录读取失败，点击重试')
                .fontSize(12)
                .fontColor(Theme.PRIMARY)
                .margin({ top: 10 })
                .onClick(() => this.loadStats())
            } else if (this.statsLoading) {
              Text('正在读取记录…')
                .fontSize(12)
                .fontColor(Theme.TEXT_SUB)
                .margin({ top: 10 })
            }
            Text('仅统计已结束的正式挑战；中途退出和教学练习不计。最佳包含猜测、提示和 AI 消耗的机会。')
              .fontSize(12)
              .fontColor(Theme.TEXT_SUB)
              .lineHeight(19)
              .width('100%')
              .margin({ top: 10 })
            if (this.legacyStats.played > 0) {
              Text('旧版历史汇总：挑战 ' + this.legacyStats.played.toString() + ' 局 · 破解 ' +
                this.legacyStats.wins.toString() + ' 局\n历史记录已保留，因未记录难度，不纳入以上分难度统计。')
                .fontSize(12)
                .fontColor(Theme.TEXT_SUB)
                .lineHeight(19)
                .width('100%')
                .margin({ top: 10 })
            }
          }
          .width('100%')
          .padding({ top: 20, bottom: 20 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        Text('开始一局')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.ON_PRIMARY)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(54)
          .backgroundColor(Theme.PRIMARY)
          .borderRadius(Theme.R_KEY)
          .onClick(() => {
            this.pathStack.pushPathByName('game', this.selectedDigits, () => {
              this.loadStats();
            });
          })

        Row({ space: 4 }) {
          Text('玩法规则')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .padding(14)
            .onClick(() => {
              this.showRules = true;
            })
            .bindSheet($$this.showRules, this.RulesSheet(), {
              height: SheetSize.FIT_CONTENT,
              backgroundColor: Theme.SHEET,
              showClose: true,
              dragBar: true
            })
          Text('·')
            .fontSize(14)
            .fontColor(Theme.TEXT_FAINT)
          Text('新手教学')
            .fontSize(14)
            .fontColor(Theme.PRIMARY)
            .padding(14)
            .onClick(() => {
              this.pathStack.pushPathByName('tutorial', '');
            })
        }
        .margin({ top: 4 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, top: 48, bottom: 20 })
    }
    .mode(NavigationMode.Stack)
    .navDestination(this.PagesMap)
    .hideTitleBar(true)
    .backgroundColor(Theme.BG_TOP)
    .width('100%')
    .height('100%')
  }
}
