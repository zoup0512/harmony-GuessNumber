/**
 * TutorialPage.ets — 新手引导（四步渐进式）
 * Step 0 目标认知：藏起来的密码是什么
 * Step 1 读懂反馈：以 答案5234 / 猜5346 为例，分阶段讲解正位与错位数量（核心步骤）
 * Step 2 推理策略：三条关键思维
 * Step 3 上手练习：3 位迷你实战局（复用 GameEngine，不限次数，教练实时解读）
 */
import { GameEngine, GuessRecord } from '../model/GameEngine';
import { StatsStore } from '../model/StatsStore';
import { Theme } from '../common/Theme';
import { FeedbackBadge } from '../common/GuessFeedback';
import { DeleteKeyIcon } from '../common/DeleteKeyIcon';
import { common } from '@kit.AbilityKit';

const DEMO_ANSWER: string = '5234';
const DEMO_GUESS: string = '5346';
const KEY_DELETE: string = 'DEL';
const KEY_SUBMIT: string = 'OK';

/** 策略卡片数据 */
interface StrategyCard {
  code: string;
  exact: number;
  misplaced: number;
  tip: string;
}

const STRATEGIES: StrategyCard[] = [
  { code: '125', exact: 0, misplaced: 0, tip: '正位和错位都是 0，说明 1、2、5 都不在密码里，可以全部排除。' },
  { code: '367', exact: 0, misplaced: 2, tip: '有 2 个数字在密码里，但都不在本次猜测的位置；仅凭这条反馈，还不知道具体是哪两个。' },
  { code: '768', exact: 1, misplaced: 2, tip: '这次 3 个数字都在密码里，其中 1 个位置正确、2 个位置错误。结合多轮反馈继续推理，不能仅凭汇总确定该保留哪个位置。' }
];

@Component
export struct TutorialPage {
  @Consume('pathStack') pathStack: NavPathStack;
  @State step: number = 0;          // 当前步骤 0..3
  @State revealStage: number = 0;   // Step1 讲解进度：0 未开始 / 1 讲正位 / 2 讲错位 / 3 出结果
  // —— 练习局状态 ——
  @State pCurrent: string = '';
  @State pRecords: GuessRecord[] = [];
  @State pWon: boolean = false;
  @State coach: string = '试着输入 3 个不同的数字，输满后会自动破解';
  private engine: GameEngine = new GameEngine();
  private keyRows: string[][] = [
    ['1', '2', '3', '4'],
    ['5', '6', '7', '8'],
    ['9', '0', KEY_DELETE, KEY_SUBMIT]
  ];

  aboutToAppear(): void {
    this.engine.start(3, 999); // 练习局：3 位，不限次数
  }

  finish(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    StatsStore.setTutorialDone(ctx);
    this.pathStack.pop();
  }

  // ---------- 练习局逻辑 ----------

  onPracticeKey(key: string): void {
    if (this.pWon) {
      return;
    }
    if (key === KEY_DELETE) {
      if (this.pCurrent.length > 0) {
        this.pCurrent = this.pCurrent.substring(0, this.pCurrent.length - 1);
      }
      return;
    }
    if (key === KEY_SUBMIT) {
      if (this.pCurrent.length === 3) {
        const rec = this.engine.judge(this.pCurrent);
        const next: GuessRecord[] = [rec];
        for (let i = 0; i < this.pRecords.length; i++) {
          next.push(this.pRecords[i]);
        }
        this.pRecords = next;
        this.pCurrent = '';
        this.updateCoach(rec);
      }
      return;
    }
    if (this.pCurrent.length < 3 && this.pCurrent.indexOf(key) < 0) {
      this.pCurrent += key;
      // 与正式对局一致：输满位数自动破解
      if (this.pCurrent.length === 3) {
        setTimeout(() => {
          if (!this.pWon && this.pCurrent.length === 3) {
            this.onPracticeKey(KEY_SUBMIT);
          }
        }, 280);
      }
    }
  }

  /** 教练：解释这次正位与错位的汇总数量 */
  updateCoach(rec: GuessRecord): void {
    if (rec.a === 3) {
      this.pWon = true;
      this.coach = '正位 3，错位 0：所有数字和位置都正确，破解成功！';
      return;
    }
    if (rec.a === 0 && rec.b === 0) {
      this.coach = '正位 0，错位 0：' + rec.guess.split('').join('、') + ' 都不在密码里，把它们全部排除！';
      return;
    }
    let text = '正位 ' + rec.a.toString() + '，错位 ' + rec.b.toString() + '：';
    if (rec.a > 0) {
      text += '有 ' + rec.a.toString() + ' 个数字位置完全正确';
    }
    if (rec.b > 0) {
      text += (rec.a > 0 ? '；' : '') + '有 ' + rec.b.toString() + ' 个数字对了但位置放错';
    }
    text += '。只给数量，不标出具体数字；两类不重复计数。结合多轮反馈推理一下！';
    this.coach = text;
  }

  practiceKeyDisabled(key: string): boolean {
    return this.pWon || this.pCurrent.length >= 3 || this.pCurrent.indexOf(key) >= 0;
  }

  // ---------- 通用小组件 ----------

  @Builder
  Tile(ch: string, size: number, fontSize: number, color: string, borderClr: string, dim: number) {
    Text(ch)
      .fontSize(fontSize)
      .fontWeight(FontWeight.Bold)
      .fontColor(color)
      .width(size)
      .height(size * 1.18)
      .textAlign(TextAlign.Center)
      .backgroundColor('rgba(255,255,255,0.08)')
      .borderRadius(Theme.R_TILE)
      .borderWidth(2)
      .borderColor(borderClr)
      .opacity(dim)
      .animation({ duration: 240, curve: Curve.EaseOut })
  }

  @Builder
  FeedbackTiles(guess: string, tileSize: number) {
    Row({ space: 6 }) {
      ForEach(guess.split(''), (ch: string, idx: number) => {
        Text(ch)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width(tileSize)
          .height(tileSize)
          .textAlign(TextAlign.Center)
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(Theme.R_TILE - 4)
      }, (ch: string, idx: number) => idx.toString() + '_' + ch)
    }
  }

  @Builder
  FeedbackRow(exact: number, misplaced: number, width: number, leftInset: number) {
    Row() {
      FeedbackBadge({ count: exact, exact: true })
      Blank()
      FeedbackBadge({ count: misplaced, exact: false })
    }
    .width(width)
    .alignSelf(ItemAlign.Start)
    .margin({ left: leftInset })
  }

  @Builder
  StepDots() {
    Row({ space: 6 }) {
      ForEach([0, 1, 2, 3], (i: number) => {
        Column()
          .width(this.step === i ? 18 : 7)
          .height(7)
          .borderRadius(999)
          .backgroundColor(this.step === i ? Theme.GOLD : 'rgba(255,255,255,0.2)')
          .animation({ duration: 200, curve: Curve.EaseOut })
      }, (i: number) => i.toString())
    }
  }

  // ---------- 各步骤内容 ----------

  @Builder
  Step0Goal() {
    Column({ space: 22 }) {
      Text('第 1 步 · 你的目标')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)
      Row({ space: 10 }) {
        ForEach(['?', '?', '?', '?'], (ch: string, idx: number) => {
          this.Tile(ch, 52, 26, Theme.GOLD, Theme.STROKE, 1)
        }, (ch: string, idx: number) => idx.toString())
      }
      Text('系统在暗中记下了一组数字密码\n各位数字互不相同，首位也可能是 0')
        .fontSize(16)
        .fontColor(Theme.TEXT)
        .textAlign(TextAlign.Center)
        .lineHeight(26)
      Text('你的任务：在限定次数内把它猜出来。\n别担心，每次猜测系统都会给你线索。')
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
        .textAlign(TextAlign.Center)
        .lineHeight(22)
    }
    .width('100%')
  }

  @Builder
  Step1Feedback() {
    Column({ space: 16 }) {
      Text('第 2 步 · 看懂反馈（最关键！）')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)

      Column({ space: 6 }) {
        Text('假设密码是（仅演示用）')
          .fontSize(12)
          .fontColor(Theme.TEXT_FAINT)
        Row({ space: 8 }) {
          ForEach(DEMO_ANSWER.split(''), (ch: string, idx: number) => {
            this.Tile(ch, 40, 20, Theme.TEXT, Theme.STROKE, 0.85)
          }, (ch: string, idx: number) => 'a' + idx.toString())
        }
      }

      Text('⬇ 你猜了')
        .fontSize(12)
        .fontColor(Theme.TEXT_FAINT)

      Column() {
        this.FeedbackTiles(DEMO_GUESS, 42)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 6 })

      // 讲解文案随阶段变化
      Column({ space: 8 }) {
        if (this.revealStage === 0) {
          Text('点击下方按钮，看看系统怎么给线索')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .textAlign(TextAlign.Center)
        }
        if (this.revealStage >= 1) {
          Text('对照已公布的演示答案，「5」数字对、位置也对，计为 1 个正位。')
            .fontSize(14)
            .fontColor(Theme.POSITION_EXACT)
            .lineHeight(22)
        }
        if (this.revealStage >= 2) {
          Text('「3」「4」在演示答案里，但位置错，计为 2 个错位；正位的「5」不再计入错位。')
            .fontSize(14)
            .fontColor(Theme.POSITION_MISPLACED)
            .lineHeight(22)
          Text('「6」不在密码里，不计入正位或错位。')
            .fontSize(14)
            .fontColor(Theme.TEXT_FAINT)
        }
        if (this.revealStage >= 3) {
          Column({ space: 8 }) {
            Text('所以这次的汇总反馈是')
              .fontSize(14)
              .fontColor(Theme.TEXT)
            this.FeedbackRow(1, 2, 186, 6)
            Text('实际对局只给数量，不标出具体数字；两类不重复计数。')
              .fontSize(13)
              .fontColor(Theme.TEXT_SUB)
              .lineHeight(21)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
  }

  @Builder
  Step2Strategy() {
    Column({ space: 14 }) {
      Text('第 3 步 · 高手思维')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)
      Text('每条线索都在缩小范围，会推理才能又快又准')
        .fontSize(14)
        .fontColor(Theme.TEXT_SUB)
      ForEach(STRATEGIES, (s: StrategyCard, idx: number) => {
        Column({ space: 10 }) {
          Text('示例猜测')
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
          this.FeedbackTiles(s.code, 58)
          this.FeedbackRow(s.exact, s.misplaced, 186, 0)
          Text(s.tip)
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
            .lineHeight(20)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.R_CARD - 6)
        .borderWidth(1)
        .borderColor(Theme.STROKE)
      }, (s: StrategyCard, idx: number) => idx.toString())
      Text('💡 卡住时还能用一次「提示」，但会消耗 1 次机会')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .opacity(0.9)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Step3Practice() {
    Column({ space: 10 }) {
      Text('第 4 步 · 亲手试一局（3 位 · 不限次数）')
        .fontSize(13)
        .fontColor(Theme.GOLD)
        .letterSpacing(2)

      // 教练气泡
      Row({ space: 8 }) {
        Text('🧑‍🏫')
          .fontSize(18)
        Text(this.coach)
          .fontSize(13)
          .fontColor(this.pWon ? Theme.GREEN : Theme.TEXT)
          .lineHeight(19)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.pWon ? 'rgba(63,207,142,0.12)' : Theme.CARD)
      .borderRadius(Theme.R_CARD - 6)
      .borderWidth(1)
      .borderColor(this.pWon ? Theme.GREEN : Theme.STROKE)
      .animation({ duration: 200, curve: Curve.EaseOut })

      // 输入槽位
      Row({ space: 8 }) {
        ForEach([0, 1, 2], (i: number) => {
          Text(i < this.pCurrent.length ? this.pCurrent.charAt(i) : '')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.GOLD)
            .width(44)
            .height(50)
            .textAlign(TextAlign.Center)
            .backgroundColor('rgba(255,255,255,0.05)')
            .borderRadius(Theme.R_TILE - 2)
            .borderWidth(1.5)
            .borderColor(i === this.pCurrent.length && !this.pWon ? Theme.GOLD : Theme.STROKE)
        }, (i: number) => i.toString())
      }

      // 最近的猜测记录（最多显示 3 条）
      if (this.pRecords.length > 0) {
        Column({ space: 6 }) {
          ForEach(this.pRecords.slice(0, 3), (rec: GuessRecord) => {
            Column({ space: 8 }) {
              Row() {
                Text('#' + rec.index.toString())
                  .fontSize(11)
                  .fontColor(Theme.TEXT_FAINT)
                  .width(24)
                this.FeedbackTiles(rec.guess, 58)
              }
              .width('100%')
              this.FeedbackRow(rec.a, rec.b, 186, 24)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(Theme.CARD)
            .borderRadius(10)
          }, (rec: GuessRecord) => rec.index.toString())
        }
        .width('100%')
      }

      // 迷你键盘
      Column({ space: 8 }) {
        ForEach(this.keyRows, (row: string[], rIdx: number) => {
          Row({ space: 8 }) {
            ForEach(row, (key: string) => {
              if (key === KEY_DELETE) {
                Row() {
                  DeleteKeyIcon({ iconSize: 20, color: this.pCurrent.length > 0 ? Theme.RED : Theme.TEXT_FAINT })
                }
                .justifyContent(FlexAlign.Center)
                .height(42)
                .layoutWeight(1)
                .backgroundColor(Theme.CARD)
                .borderRadius(12)
                .accessibilityText('删除')
                .onClick(() => this.onPracticeKey(key))
              } else if (key === KEY_SUBMIT) {
                Text('✓ 破解')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.pCurrent.length === 3 ? '#1B1030' : Theme.TEXT_FAINT)
                  .textAlign(TextAlign.Center)
                  .height(42)
                  .layoutWeight(1)
                  .linearGradient(this.pCurrent.length === 3
                    ? { angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] }
                    : { angle: 135, colors: [['rgba(255,255,255,0.06)', 0], ['rgba(255,255,255,0.06)', 1]] })
                  .borderRadius(12)
                  .onClick(() => this.onPracticeKey(key))
              } else {
                Text(key)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.practiceKeyDisabled(key) ? Theme.TEXT_FAINT : Theme.TEXT)
                  .textAlign(TextAlign.Center)
                  .height(42)
                  .layoutWeight(1)
                  .backgroundColor(this.practiceKeyDisabled(key) ? 'rgba(255,255,255,0.03)' : Theme.CARD_STRONG)
                  .borderRadius(12)
                  .enabled(!this.practiceKeyDisabled(key))
                  .onClick(() => this.onPracticeKey(key))
              }
            }, (key: string) => key)
          }
          .width('100%')
        }, (row: string[], rIdx: number) => rIdx.toString())
      }
      .width('100%')
    }
    .width('100%')
  }

  // ---------- 底部导航 ----------

  primaryLabel(): string {
    if (this.step === 1 && this.revealStage < 3) {
      return this.revealStage === 0 ? '看讲解' : '继续';
    }
    if (this.step === 3) {
      return this.pWon ? '完成教学，出发！' : '我学会了，直接开始';
    }
    return '下一步';
  }

  onPrimary(): void {
    if (this.step === 1 && this.revealStage < 3) {
      this.revealStage++;
      return;
    }
    if (this.step < 3) {
      this.step++;
      return;
    }
    this.finish();
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：进度点 + 跳过
        Row() {
          this.StepDots()
          Blank()
          Text('跳过')
            .fontSize(14)
            .fontColor(Theme.TEXT_SUB)
            .padding(8)
            .onClick(() => this.finish())
        }
        .width('100%')

        // 内容区
        Scroll() {
          Column() {
            if (this.step === 0) {
              this.Step0Goal()
            } else if (this.step === 1) {
              this.Step1Feedback()
            } else if (this.step === 2) {
              this.Step2Strategy()
            } else {
              this.Step3Practice()
            }
          }
          .width('100%')
          .padding({ top: 18, bottom: 12 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        // 底部按钮
        Row({ space: 12 }) {
          if (this.step > 0) {
            Text('上一步')
              .fontSize(15)
              .fontColor(Theme.TEXT)
              .textAlign(TextAlign.Center)
              .height(50)
              .width(96)
              .backgroundColor(Theme.CARD_STRONG)
              .borderRadius(999)
              .onClick(() => {
                if (this.step === 1 && this.revealStage > 0) {
                  this.revealStage = 0;
                }
                this.step--;
              })
          }
          Text(this.primaryLabel())
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1B1030')
            .textAlign(TextAlign.Center)
            .height(50)
            .layoutWeight(1)
            .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
            .borderRadius(999)
            .onClick(() => this.onPrimary())
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 22, right: 22, top: 52, bottom: 24 })
    }
    .hideTitleBar(true)
    .linearGradient({ angle: 180, colors: [[Theme.BG_TOP, 0], [Theme.BG_BOTTOM, 1]] })
    .onBackPressed(() => {
      this.finish();
      return true;
    })
  }
}
