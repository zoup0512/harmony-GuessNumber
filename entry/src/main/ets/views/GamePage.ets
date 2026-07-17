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
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [KEY_DELETE, '0', KEY_SUBMIT]
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

  // ---------- UI ----------

  @Builder
  ResultBadge(count: number, medal: string, color: string) {
    Row({ space: 3 }) {
      Text(medal)
        .fontSize(14)
      Text('×' + count.toString())
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor('rgba(255,255,255,0.06)')
    .borderRadius(999)
  }

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
          .backgroundColor('rgba(255,255,255,0.08)')
          .borderRadius(Theme.R_TILE - 4)
      }, (ch: string, idx: number) => idx.toString() + '_' + ch)
    }
  }

  @Builder
  Header() {
    Row() {
      // 返回
      Text('‹')
        .fontSize(34)
        .fontColor(Theme.TEXT)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .backgroundColor(Theme.CARD)
        .borderRadius(999)
        .onClick(() => {
          this.stopTimer();
          this.pathStack.pop();
        })

      Blank()

      // 计时
      Row({ space: 4 }) {
        Text('⏱')
          .fontSize(14)
        Text(this.timeText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.CARD)
      .borderRadius(999)

      Blank()

      // 剩余机会
      Row({ space: 4 }) {
        Text('❤')
          .fontSize(13)
          .fontColor(Theme.GOLD)
        Text(this.attemptsLeft.toString() + ' / ' + this.maxAttempts.toString())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(Theme.CARD)
      .borderRadius(999)
    }
    .width('100%')
  }

  @Builder
  AttemptPips() {
    Row({ space: 6 }) {
      ForEach(this.pipArray(), (used: boolean, idx: number) => {
        Circle()
          .width(8)
          .height(8)
          .fill(used ? Theme.GOLD : 'rgba(255,255,255,0.18)')
      }, (used: boolean, idx: number) => idx.toString() + '_' + (used ? '1' : '0'))
    }
    .margin({ top: 10 })
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
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        ForEach(this.slotArray(), (ch: string, idx: number) => {
          Text(ch)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.GOLD)
            .width(54)
            .height(64)
            .textAlign(TextAlign.Center)
            .backgroundColor(ch === '' ? 'rgba(255,255,255,0.05)' : 'rgba(245,180,65,0.12)')
            .borderRadius(Theme.R_TILE)
            .borderWidth(1.5)
            .borderColor(idx === this.current.length && !this.finished
              ? Theme.GOLD : Theme.STROKE)
        }, (ch: string, idx: number) => idx.toString() + '_' + ch)
      }
      if (this.hintText !== '') {
        Text('💡 ' + this.hintText)
          .fontSize(13)
          .fontColor(Theme.GOLD)
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
        Text('🔐')
          .fontSize(34)
          .opacity(0.6)
        Text('输入一组互不相同的数字，开始破解')
          .fontSize(13)
          .fontColor(Theme.TEXT_FAINT)
        Text('🥇 金牌 = 数字和位置都对　🥈 银牌 = 数字对、位置错')
          .fontSize(12)
          .fontColor(Theme.TEXT_FAINT)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        ForEach(this.records, (rec: GuessRecord) => {
          ListItem() {
            Row() {
              Text('#' + rec.index.toString())
                .fontSize(12)
                .fontColor(Theme.TEXT_FAINT)
                .width(30)
              this.GuessTiles(rec.guess, 34, 18)
              Blank()
              this.ResultBadge(rec.a, '🥇', Theme.GOLD)
              Row().width(6)
              this.ResultBadge(rec.b, '🥈', Theme.SILVER)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(Theme.CARD)
            .borderRadius(Theme.R_CARD - 6)
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
        Text('🤖')
          .fontSize(22)
        Text('AI 军师分析')
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
            .fontColor('#7EE1FF')
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
      .backgroundColor('rgba(126,225,255,0.07)')
      .borderRadius(Theme.R_CARD - 6)
      .borderWidth(1)
      .borderColor('rgba(126,225,255,0.25)')
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
              .fontColor(this.aiDigitStatus(ch) === 'in' ? '#0F2A1D'
                : (this.aiDigitStatus(ch) === 'out' ? 'rgba(244,242,255,0.28)' : Theme.TEXT))
              .width(28)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.aiDigitStatus(ch) === 'in' ? Theme.GREEN
                : (this.aiDigitStatus(ch) === 'out' ? 'rgba(240,97,109,0.12)' : 'rgba(255,255,255,0.07)'))
              .borderRadius(8)
              .decoration(this.aiDigitStatus(ch) === 'out'
                ? { type: TextDecorationType.LineThrough, color: Theme.RED }
                : { type: TextDecorationType.None })
          }, (ch: string) => ch)
        }
        Row({ space: 14 }) {
          Text('🟩 必定包含')
            .fontSize(11)
            .fontColor(Theme.TEXT_FAINT)
          Text('❌ 必定排除')
            .fontSize(11)
            .fontColor(Theme.TEXT_FAINT)
          Text('⬜ 尚不确定')
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
          Row() {
            this.GuessTiles(this.ai.bestGuess, 40, 20)
            Blank()
            Text('一键填入')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1B1030')
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
              .borderRadius(999)
              .onClick(() => {
                this.showAi = false;
                this.current = this.ai.bestGuess;
                this.scheduleAutoSubmit();
              })
          }
          .width('100%')
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
      Row() {
        // AI 军师
        Row({ space: 4 }) {
          Text('🤖')
            .fontSize(13)
          Text(this.aiUsesLeft > 0
            ? 'AI 军师 ×' + this.aiUsesLeft.toString() + '（耗 1 次机会）'
            : 'AI 军师已下班')
            .fontSize(13)
            .fontColor(this.aiUsesLeft > 0 ? '#7EE1FF' : Theme.TEXT_FAINT)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.aiUsesLeft > 0 ? 'rgba(126,225,255,0.10)' : 'rgba(255,255,255,0.04)')
        .borderRadius(999)
        .borderWidth(1)
        .borderColor(this.aiUsesLeft > 0 ? 'rgba(126,225,255,0.35)' : 'rgba(255,255,255,0.08)')
        .onClick(() => this.requestAi())
        .bindSheet($$this.showAi, this.AiSheet(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: '#1D1838',
          showClose: true,
          dragBar: true
        })

        Blank()

        // 揭示一位提示
        Row({ space: 4 }) {
          Text('💡')
            .fontSize(13)
          Text(this.hintUsed ? '提示已用' : '提示（耗 1 次机会）')
            .fontSize(13)
            .fontColor(this.hintUsed ? Theme.TEXT_FAINT : Theme.GOLD)
        }
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.hintUsed ? 'rgba(255,255,255,0.04)' : 'rgba(245,180,65,0.12)')
        .borderRadius(999)
        .onClick(() => this.requestHint())
      }
      .width('100%')

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
      Text('⌫')
        .fontSize(22)
        .fontColor(this.current.length > 0 ? Theme.RED : Theme.TEXT_FAINT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(Theme.CARD)
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.onKey(key))
    } else if (key === KEY_SUBMIT) {
      Text('✓ 破解')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.current.length === this.digits ? '#1B1030' : Theme.TEXT_FAINT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .linearGradient(this.current.length === this.digits
          ? { angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] }
          : { angle: 135, colors: [['rgba(255,255,255,0.06)', 0], ['rgba(255,255,255,0.06)', 1]] })
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.onKey(key))
    } else {
      Text(key)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.digitKeyDisabled(key) ? Theme.TEXT_FAINT : Theme.TEXT)
        .textAlign(TextAlign.Center)
        .height(52)
        .layoutWeight(1)
        .backgroundColor(this.digitKeyDisabled(key) ? 'rgba(255,255,255,0.03)' : Theme.CARD_STRONG)
        .borderRadius(Theme.R_KEY)
        .enabled(!this.digitKeyDisabled(key))
        .onClick(() => this.onKey(key))
    }
  }

  @Builder
  ResultOverlay() {
    Column() {
      Column({ space: 14 }) {
        Text(this.win ? '🎉' : '💥')
          .fontSize(52)
        Text(this.win ? '破解成功！' : '解密失败')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.win ? Theme.GREEN : Theme.RED)
        Text(this.win
          ? '用时 ' + this.timeText() + ' · 共 ' + this.engine.attemptsUsed.toString() + ' 次尝试'
          : '机会已用完，正确密码是：')
          .fontSize(14)
          .fontColor(Theme.TEXT_SUB)
        this.GuessTiles(this.engine.secret, 44, 24)
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
            .fontColor('#1B1030')
            .textAlign(TextAlign.Center)
            .height(48)
            .layoutWeight(1)
            .linearGradient({ angle: 135, colors: [[Theme.GOLD, 0], [Theme.GOLD_DEEP, 1]] })
            .borderRadius(999)
            .onClick(() => this.startGame(this.digits))
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('84%')
      .padding(24)
      .backgroundColor('#1D1838')
      .borderRadius(24)
      .borderWidth(1)
      .borderColor(Theme.STROKE)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(8,8,20,0.72)')
    .transition(TransitionEffect.OPACITY.animation({ duration: 260 }))
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.Header()
          this.AttemptPips()
          this.CurrentInput()
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
    .linearGradient({ angle: 180, colors: [[Theme.BG_TOP, 0], [Theme.BG_BOTTOM, 1]] })
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
