/**
 * GamePage.ets — 对局页面
 * 顶部：返回 / 计时 / 剩余机会
 * 中部：当前输入瓷砖 + 猜测历史（最新在上）
 * 底部：定制数字键盘（自动禁用已用数字，杜绝非法输入）+ 提示
 * 结束：结果浮层（揭示答案 / 再来一局 / 返回主页）
 */
import { GameEngine, GuessRecord, DIFFICULTIES, Difficulty, AiAdvice } from '../model/GameEngine';
import { StatsStore } from '../model/StatsStore';
import { Theme } from '../common/Theme';
import { FeedbackBadge, FeedbackIcon } from '../common/GuessFeedback';
import { DeleteKeyIcon } from '../common/DeleteKeyIcon';
import { BoardIcon } from '../common/BoardIcon';
import { common } from '@kit.AbilityKit';

const KEY_DELETE: string = 'DEL';
const KEY_SUBMIT: string = 'OK';
const AI_MAX_USES: number = 2;

@Component
export struct GamePage {
  @Consume('pathStack') pathStack: NavPathStack;
  private engine: GameEngine = new GameEngine();
  @State digits: number = 4;
  @State current: string = '';
  @State records: GuessRecord[] = [];
  @State attemptsLeft: number = 8;
  @State maxAttempts: number = 8;
  @State finished: boolean = false;
  @State win: boolean = false;
  @State seconds: number = 0;
  @State hintText: string = '';
  @State hintUsed: boolean = false;
  @State statsSaved: boolean = false;
  @State showAi: boolean = false;
  @State aiUsesLeft: number = AI_MAX_USES;
  @State ai: AiAdvice = new AiAdvice();
  private timerId: number = -1;
  private keyRows: string[][] = [
    ['1', '2', '3', '4'],
    ['5', '6', '7', '8'],
    ['9', '0', KEY_DELETE, KEY_SUBMIT]
  ];

  aboutToDisappear(): void {
    this.stopTimer();
  }

  startGame(digits: number): void {
    let attempts = 8;
    for (let i = 0; i < DIFFICULTIES.length; i++) {
      const d: Difficulty = DIFFICULTIES[i];
      if (d.digits === digits) {
        attempts = d.attempts;
        break;
      }
    }
    this.digits = digits;
    this.maxAttempts = attempts;
    this.engine.start(digits, attempts);
    this.records = [];
    this.current = '';
    this.attemptsLeft = attempts;
    this.finished = false;
    this.win = false;
    this.seconds = 0;
    this.hintText = '';
    this.hintUsed = false;
    this.statsSaved = false;
    this.showAi = false;
    this.aiUsesLeft = AI_MAX_USES;
    this.ai = new AiAdvice();
    this.stopTimer();
    this.timerId = setInterval(() => {
      if (!this.finished) {
        this.seconds++;
      }
    }, 1000);
  }

  stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  timeText(): string {
    const m = Math.floor(this.seconds / 60);
    const s = this.seconds % 60;
    const mm = m < 10 ? '0' + m.toString() : m.toString();
    const ss = s < 10 ? '0' + s.toString() : s.toString();
    return mm + ':' + ss;
  }

  onKey(key: string): void {
    if (this.finished) {
      return;
    }
    if (key === KEY_DELETE) {
      if (this.current.length > 0) {
        this.current = this.current.substring(0, this.current.length - 1);
      }
      return;
    }
    if (key === KEY_SUBMIT) {
      this.submit();
      return;
    }
    // 数字键：长度未满且不重复（对应原 C 版 JudgeInput 的输入校验）
    if (this.current.length < this.digits && this.current.indexOf(key) < 0) {
      this.current += key;
      // 输满位数后自动破解
      if (this.current.length === this.digits) {
        this.scheduleAutoSubmit();
      }
    }
  }

  /** 延时 280ms 自动提交：让最后一位瓷砖先完成渲染，也给误触留出删除窗口 */
  scheduleAutoSubmit(): void {
    setTimeout(() => {
      if (!this.finished && this.current.length === this.digits) {
        this.submit();
      }
    }, 280);
  }

  submit(): void {
    if (this.current.length !== this.digits || this.finished) {
      return;
    }
    const rec = this.engine.judge(this.current);
    const next: GuessRecord[] = [rec];
    for (let i = 0; i < this.records.length; i++) {
      next.push(this.records[i]);
    }
    this.records = next;
    this.current = '';
    this.attemptsLeft = this.engine.attemptsLeft();
    if (rec.a === this.digits) {
      this.endGame(true);
    } else if (this.attemptsLeft <= 0) {
      this.endGame(false);
    }
  }

  /** 召唤 AI 军师：消耗 1 次机会，每局限 AI_MAX_USES 次 */
  requestAi(): void {
    if (this.finished) {
      return;
    }
    if (this.aiUsesLeft <= 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '本局 AI 军师已下班（每局限 ' + AI_MAX_USES.toString() + ' 次）',
        duration: 2000
      });
      return;
    }
    if (this.attemptsLeft <= 1) {
      this.getUIContext().getPromptAction().showToast({
        message: '剩余机会不足，无法召唤 AI 军师',
        duration: 2000
      });
      return;
    }
    // 只把公开的历史线索交给 AI 做约束求解
    const history: GuessRecord[] = [];
    for (let i = 0; i < this.records.length; i++) {
      history.push(this.records[i]);
    }
    this.ai = GameEngine.analyze(this.digits, history);
    this.engine.spendAttempt();
    this.attemptsLeft = this.engine.attemptsLeft();
    this.aiUsesLeft--;
    this.showAi = true;
  }

  /** AI 视角下数字 ch 的判定：'in' 必含 / 'out' 排除 / 'unknown' 未知 */
  aiDigitStatus(ch: string): string {
    if (this.ai.mustInclude.indexOf(ch) >= 0) {
      return 'in';
    }
    if (this.ai.mustExclude.indexOf(ch) >= 0) {
      return 'out';
    }
    return 'unknown';
  }

  requestHint(): void {
    if (this.finished || this.hintUsed) {
      return;
    }
    const past: string[] = [];
    for (let i = 0; i < this.records.length; i++) {
      past.push(this.records[i].guess);
    }
    const text = this.engine.useHint(past);
    if (text !== '') {
      this.hintText = text;
      this.hintUsed = true;
      this.attemptsLeft = this.engine.attemptsLeft();
      this.getUIContext().getPromptAction().showToast({
        message: '提示：' + text + '（消耗 1 次机会）',
        duration: 2500
      });
    } else {
      this.getUIContext().getPromptAction().showToast({
        message: '剩余机会不足，无法使用提示',
        duration: 2000
      });
    }
  }

  endGame(win: boolean): void {
    this.win = win;
    this.finished = true;
    this.stopTimer();
    if (!this.statsSaved) {
      this.statsSaved = true;
      const ctx = this.getUIContext().getHostContext() as common.Context;
      StatsStore.recordResult(ctx, win, this.engine.attemptsUsed);
    }
  }

  digitKeyDisabled(key: string): boolean {
    return this.finished ||
      this.current.length >= this.digits ||
      this.current.indexOf(key) >= 0;
  }

  aiAvailable(): boolean {
    return !this.finished && this.attemptsLeft > 1 && this.aiUsesLeft > 0;
  }

  hintAvailable(): boolean {
    return !this.finished && this.attemptsLeft > 1 && !this.hintUsed;
  }

  // ---------- UI ----------

  @Builder
  GuessTiles(guess: string, size: number, fontSize: number) {
    Row({ space: 6 }) {
      ForEach(guess.split(''), (ch: string) => {
        Text(ch)
          .fontSize(fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
          .width(size)
          .height(size)
          .textAlign(TextAlign.Center)
          .backgroundColor(Theme.CARD_STRONG)
          .borderRadius(Theme.R_TILE - 4)
      }, (ch: string, idx: number) => idx.toString() + '_' + ch)
    }
  }

  historyTileSize(guess: string): number {
    return guess.length === 3 ? 44 : (guess.length === 4 ? 40 : 34);
  }

  @Builder
  Header() {
    Row({ space: 10 }) {
      Row() {
        Shape() {
          Path()
            .commands('M15.5 5.5 L9 12 L15.5 18.5')
            .fill(Color.Transparent)
            .stroke(Theme.TEXT)
            .strokeWidth('2.4px')
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
        }
        .viewPort({ x: '0px', y: '0px', width: '24px', height: '24px' })
        .width(24)
        .height(24)
      }
      .justifyContent(FlexAlign.Center)
      .width(44)
      .height(44)
      .backgroundColor(Theme.CARD)
      .borderRadius(Theme.R_KEY)
      .accessibilityText('返回')
      .onClick(() => {
        this.stopTimer();
        this.pathStack.pop();
      })
      Text(this.digits.toString() + ' 位数字')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT)
      Blank()
      Row({ space: 5 }) {
        BoardIcon({ kind: 'clock', iconSize: 16 })
        Text(this.timeText())
          .fontSize(13)
          .fontColor(Theme.TEXT_SUB)
      }
    }
    .width('100%')
  }

  @Builder
  AttemptPips() {
    Row() {
      Text('剩余 ' + this.attemptsLeft.toString() + ' / ' + this.maxAttempts.toString() + ' 次机会')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
      Blank()
      Row({ space: 5 }) {
        ForEach(this.pipArray(), (used: boolean, idx: number) => {
          Circle()
            .width(6)
            .height(6)
            .fill(used ? Theme.STROKE : Theme.PRIMARY)
        }, (used: boolean, idx: number) => idx.toString() + '_' + (used ? '1' : '0'))
      }
      .accessibilityLevel('no')
    }
    .width('100%')
    .margin({ top: 12 })
  }

  pipArray(): boolean[] {
    const arr: boolean[] = [];
    const used = this.maxAttempts - this.attemptsLeft;
    for (let i = 0; i < this.maxAttempts; i++) {
      arr.push(i < used);
    }
    return arr;
  }

  @Builder
  CurrentInput() {
    Column({ space: 10 }) {
      Text('输入不重复的数字 · 输满自动提交')
        .fontSize(12)
        .fontColor(Theme.TEXT_SUB)
      Row({ space: 8 }) {
        ForEach(this.slotArray(), (ch: string, idx: number) => {
          Text(ch)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.PRIMARY)
            .width(this.digits === 5 ? 48 : 54)
            .height(60)
            .textAlign(TextAlign.Center)
            .backgroundColor(ch === '' ? Theme.CARD : Theme.PRIMARY_BG)
            .borderRadius(Theme.R_TILE)
            .borderWidth(1.5)
            .borderColor(idx === this.current.length && !this.finished
              ? Theme.PRIMARY : Theme.STROKE)
        }, (ch: string, idx: number) => idx.toString() + '_' + ch)
      }
      if (this.hintText !== '') {
        Text('提示：' + this.hintText)
          .fontSize(13)
          .fontColor(Theme.PRIMARY)
          .opacity(0.9)
      }
    }
    .margin({ top: 18 })
  }

  slotArray(): string[] {
    const arr: string[] = [];
    for (let i = 0; i < this.digits; i++) {
      arr.push(i < this.current.length ? this.current.charAt(i) : '');
    }
    return arr;
  }

  @Builder
  History() {
    if (this.records.length === 0) {
      Column({ space: 6 }) {
        BoardIcon({ kind: 'grid', iconSize: 30, color: Theme.STROKE })
        Text('每一次尝试，都会带来新线索')
          .fontSize(13)
          .fontColor(Theme.TEXT_FAINT)
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            FeedbackIcon({ exact: true })
            Text('正位：数字和位置都对')
              .fontSize(12)
              .fontColor(Theme.TEXT_SUB)
          }
          Row({ space: 6 }) {
            FeedbackIcon({ exact: false })
            Text('错位：数字对、位置不对')
              .fontSize(12)
              .fontColor(Theme.TEXT_SUB)
          }
        }
        .alignItems(HorizontalAlign.Start)
        Text('只给数量，不标出具体数字；两类不重复计数')
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.records, (rec: GuessRecord) => {
          ListItem() {
            Column({ space: 8 }) {
              Row() {
                Text('#' + rec.index.toString())
                  .fontSize(12)
                  .fontColor(Theme.TEXT_FAINT)
                  .width(30)
                this.GuessTiles(rec.guess, this.historyTileSize(rec.guess), 18)
              }
              .width('100%')
              Row({ space: 10 }) {
                FeedbackBadge({ count: rec.a, exact: true })
                FeedbackBadge({ count: rec.b, exact: false })
              }
              .margin({ left: 30 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD - 4)
            .borderWidth(1)
            .borderColor(Theme.STROKE)
          }
        }, (rec: GuessRecord) => rec.index.toString())
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 14 })
      .scrollBar(BarState.Off)
    }
  }

  /** AI 军师分析面板 */
  @Builder
  AiSheet() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        BoardIcon({ kind: 'analysis', iconSize: 22, color: Theme.PRIMARY })
        Text('AI 线索分析')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Blank()
        Text('本局还可召唤 ' + this.aiUsesLeft.toString() + ' 次')
          .fontSize(12)
          .fontColor(Theme.TEXT_FAINT)
      }
      .width('100%')

      // 结论概览
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('剩余可能密码')
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
          Text(this.ai.candidateCount.toString())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.PRIMARY)
          Text('组')
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
        }
        Text(this.ai.summary)
          .fontSize(13)
          .fontColor(Theme.TEXT_SUB)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(Theme.PRIMARY_BG)
      .borderRadius(Theme.R_CARD - 6)
      .borderWidth(1)
      .borderColor(Theme.STROKE)
      .alignItems(HorizontalAlign.Start)

      // 数字判定盘
      Column({ space: 8 }) {
        Text('数字判定（由历史线索逻辑推出）')
          .fontSize(13)
          .fontColor(Theme.TEXT_SUB)
          .alignSelf(ItemAlign.Start)
        Row({ space: 6 }) {
          ForEach(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'], (ch: string) => {
            Text(ch)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.aiDigitStatus(ch) === 'in' ? Theme.PRIMARY
                : (this.aiDigitStatus(ch) === 'out' ? Theme.TEXT_FAINT : Theme.TEXT))
              .layoutWeight(1)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.aiDigitStatus(ch) === 'in' ? Theme.PRIMARY_BG
                : (this.aiDigitStatus(ch) === 'out' ? Theme.RED_BG : Theme.CARD_STRONG))
              .borderRadius(8)
              .decoration(this.aiDigitStatus(ch) === 'out'
                ? { type: TextDecorationType.LineThrough, color: Theme.RED }
                : { type: TextDecorationType.None })
          }, (ch: string) => ch)
        }
        .width('100%')
        Row({ space: 8 }) {
          Text('绿色：必定包含')
            .fontSize(11)
            .fontColor(Theme.TEXT_FAINT)
          Text('划线：必定排除')
            .fontSize(11)
            .fontColor(Theme.TEXT_FAINT)
          Text('灰底：尚不确定')
            .fontSize(11)
            .fontColor(Theme.TEXT_FAINT)
        }
      }
      .width('100%')

      // 推荐猜测
      if (this.ai.bestGuess !== '') {
        Column({ space: 10 }) {
          Text('推荐下一步（信息量最优）')
            .fontSize(13)
            .fontColor(Theme.TEXT_SUB)
            .alignSelf(ItemAlign.Start)
          this.GuessTiles(this.ai.bestGuess, this.digits === 5 ? 34 : 40, 20)
          Text('填入并提交')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.ON_PRIMARY)
            .textAlign(TextAlign.Center)
            .height(44)
            .width('100%')
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(Theme.R_KEY)
            .onClick(() => {
              this.showAi = false;
              this.current = this.ai.bestGuess;
              this.scheduleAutoSubmit();
            })
        }
        .width('100%')
        .padding(14)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.R_CARD - 6)
      }

      Text('AI 只根据你已获得的线索推理，从不偷看答案 · 本次已消耗 1 次机会')
        .fontSize(11)
        .fontColor(Theme.TEXT_FAINT)
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 8, bottom: 30 })
  }

  @Builder
  Keypad() {
    Column({ space: 10 }) {
      // 提示 & AI 军师
      Row({ space: 10 }) {
        // AI 军师
        Column({ space: 2 }) {
          Text(this.aiUsesLeft > 0
            ? 'AI 分析 · 余 ' + this.aiUsesLeft.toString() + ' 次'
            : 'AI 分析已用完')
            .fontSize(13)
            .fontColor(this.aiAvailable() ? Theme.TEXT_SUB : Theme.DISABLED_TEXT)
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.aiUsesLeft <= 0 ? '本局次数已用完' : (this.attemptsLeft <= 1 ? '需保留最后一次机会' : '耗 1 次机会'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SUB)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .justifyContent(FlexAlign.Center)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(Theme.BG_TOP)
        .borderRadius(Theme.R_KEY)
        .borderWidth(1)
        .borderColor(Theme.STROKE)
        .enabled(this.aiAvailable())
        .onClick(() => this.requestAi())
        .bindSheet($$this.showAi, this.AiSheet(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: Theme.SHEET,
          showClose: true,
          dragBar: true
        })

        // 揭示一位提示
        Column({ space: 2 }) {
          Text(this.hintUsed ? '提示已用完' : '揭示一位')
            .fontSize(13)
            .fontColor(this.hintAvailable() ? Theme.TEXT_SUB : Theme.DISABLED_TEXT)
            .width('100%')
            .textAlign(TextAlign.Center)
          Text(this.hintUsed ? '每局限 1 次' : (this.attemptsLeft <= 1 ? '需保留最后一次机会' : '耗 1 次机会'))
            .fontSize(11)
            .fontColor(Theme.TEXT_SUB)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 48 })
        .justifyContent(FlexAlign.Center)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(Theme.BG_TOP)
        .borderRadius(Theme.R_KEY)
        .borderWidth(1)
        .borderColor(Theme.STROKE)
        .enabled(this.hintAvailable())
        .onClick(() => this.requestHint())
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      ForEach(this.keyRows, (row: string[], rIdx: number) => {
        Row({ space: 10 }) {
          ForEach(row, (key: string) => {
            this.KeyButton(key)
          }, (key: string) => key)
        }
        .width('100%')
      }, (row: string[], rIdx: number) => rIdx.toString())
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  KeyButton(key: string) {
    if (key === KEY_DELETE) {
      Row() {
        DeleteKeyIcon({ iconSize: 24, color: this.current.length > 0 ? Theme.RED : Theme.TEXT_FAINT })
      }
      .justifyContent(FlexAlign.Center)
      .height(52)
      .layoutWeight(1)
      .backgroundColor(Theme.CARD)
      .borderRadius(Theme.R_KEY)
      .accessibilityText('删除')
      .onClick(() => this.onKey(key))
    } else if (key === KEY_SUBMIT) {
      Text('提交')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.current.length === this.digits ? Theme.ON_PRIMARY : Theme.DISABLED_TEXT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(this.current.length === this.digits ? Theme.PRIMARY : Theme.KEY_DISABLED)
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.onKey(key))
    } else {
      Text(key)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.digitKeyDisabled(key) ? Theme.DISABLED_TEXT : Theme.TEXT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(this.digitKeyDisabled(key) ? Theme.KEY_DISABLED : Theme.CARD)
        .borderRadius(Theme.R_KEY)
        .enabled(!this.digitKeyDisabled(key))
        .onClick(() => this.onKey(key))
    }
  }

  @Builder
  ResultOverlay() {
    Column() {
      Column({ space: 14 }) {
        BoardIcon({ kind: this.win ? 'check' : 'flag', iconSize: 44, color: this.win ? Theme.GREEN : Theme.TEXT_SUB })
        Text(this.win ? '这组数字，想通了！' : '再差一点，下局继续')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Text(this.win
          ? '用时 ' + this.timeText() + ' · 共 ' + this.engine.attemptsUsed.toString() + ' 次尝试'
          : '机会已用完，正确密码是：')
          .fontSize(14)
          .fontColor(Theme.TEXT_SUB)
        this.GuessTiles(this.engine.secret, this.digits === 5 ? 38 : 44, 24)
        Row({ space: 12 }) {
          Text('返回主页')
            .fontSize(16)
            .fontColor(Theme.TEXT)
            .textAlign(TextAlign.Center)
            .height(48)
            .layoutWeight(1)
            .backgroundColor(Theme.CARD_STRONG)
            .borderRadius(999)
            .onClick(() => {
              this.stopTimer();
              this.pathStack.pop();
            })
          Text('再来一局')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.ON_PRIMARY)
            .textAlign(TextAlign.Center)
            .height(48)
            .layoutWeight(1)
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(999)
            .onClick(() => this.startGame(this.digits))
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('84%')
      .padding(24)
      .backgroundColor(Theme.SHEET)
      .borderRadius(24)
      .borderWidth(1)
      .borderColor(Theme.STROKE)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.MASK)
    .transition(TransitionEffect.OPACITY.animation({ duration: 260 }))
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.Header()
          this.AttemptPips()
          this.CurrentInput()
          Row() {
            Text('推理记录')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.TEXT)
            Blank()
            Text(this.records.length > 0 ? '最新在上' : '等待第一条线索')
              .fontSize(12)
              .fontColor(Theme.TEXT_FAINT)
          }
          .width('100%')
          .margin({ top: 22 })
          this.History()
          this.Keypad()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 18, top: 52, bottom: 24 })

        if (this.finished) {
          this.ResultOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.BG_TOP)
    .onReady((ctx: NavDestinationContext) => {
      const digits = ctx.pathInfo.param as number;
      this.startGame(digits > 0 ? digits : 4);
    })
    .onBackPressed(() => {
      this.stopTimer();
      this.pathStack.pop();
      return true;
    })
  }
}
