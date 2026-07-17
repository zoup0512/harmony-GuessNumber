/**
 * GameEngine.ets — 1A2B 猜数字核心逻辑
 *
 * 与原 C 程序的对应关系：
 *   CreateNum()  -> GameEngine.generateSecret()   生成各位互不相同的随机数字
 *   JudgeA()     -> judge() 中的 a 计数            数字对且位置对
 *   JudgeB()     -> judge() 中的 b 计数            数字对但位置错
 *   JudgeInput() -> 由键盘输入规则天然保证          （重复数字直接禁用按键）
 */

/** 一条猜测记录 */
export interface GuessRecord {
  index: number;   // 第几次猜测（从 1 开始）
  guess: string;   // 猜测的数字串
  a: number;       // xA：数字对且位置对
  b: number;       // yB：数字对但位置错
}

/** 难度配置 */
export interface Difficulty {
  digits: number;      // 位数
  attempts: number;    // 允许的猜测次数
  name: string;        // 显示名
  desc: string;        // 描述
}

export const DIFFICULTIES: Difficulty[] = [
  { digits: 3, attempts: 6, name: '入门', desc: '3 位密码 · 6 次机会' },
  { digits: 4, attempts: 8, name: '经典', desc: '4 位密码 · 8 次机会' },
  { digits: 5, attempts: 10, name: '大师', desc: '5 位密码 · 10 次机会' }
];

/** AI 军师的分析结论（只基于公开的历史线索推理，不偷看答案） */
export class AiAdvice {
  candidateCount: number = 0;    // 与全部线索相容的候选密码数量
  mustInclude: string[] = [];    // 逻辑上必定包含的数字
  mustExclude: string[] = [];    // 逻辑上必定排除的数字
  bestGuess: string = '';        // 推荐的下一步猜测
  summary: string = '';          // 一句话总结
}

export class GameEngine {
  secret: string = '';
  digits: number = 4;
  maxAttempts: number = 8;
  attemptsUsed: number = 0;
  hintUsed: boolean = false;

  /** 开始一局新游戏 */
  start(digits: number, attempts: number): void {
    this.digits = digits;
    this.maxAttempts = attempts;
    this.attemptsUsed = 0;
    this.hintUsed = false;
    this.secret = GameEngine.generateSecret(digits);
  }

  /** 生成各位互不相同的随机数字（Fisher–Yates 洗牌，允许首位为 0，与原版一致） */
  static generateSecret(n: number): string {
    const pool: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    let s = '';
    for (let i = 0; i < n; i++) {
      s += pool[i].toString();
    }
    return s;
  }

  /** 静态判定：计算 guess 相对 secret 的 [A, B] */
  static computeAB(secret: string, guess: string): number[] {
    let a = 0;
    let b = 0;
    for (let i = 0; i < guess.length; i++) {
      const pos = secret.indexOf(guess.charAt(i));
      if (pos === i) {
        a++;
      } else if (pos >= 0) {
        b++;
      }
    }
    return [a, b];
  }

  /** 判定一次猜测，返回记录（自动累计次数） */
  judge(guess: string): GuessRecord {
    const ab = GameEngine.computeAB(this.secret, guess);
    this.attemptsUsed++;
    const rec: GuessRecord = { index: this.attemptsUsed, guess: guess, a: ab[0], b: ab[1] };
    return rec;
  }

  /** 额外消耗一次机会（供提示 / AI 军师使用） */
  spendAttempt(): void {
    this.attemptsUsed++;
  }

  /** 剩余次数 */
  attemptsLeft(): number {
    return this.maxAttempts - this.attemptsUsed;
  }

  /**
   * 使用一次提示：从尚未被任何历史猜测"猜对位置"的位里，随机揭示一位。
   * 代价为消耗一次猜测机会，每局限一次。
   * 返回揭示文案，如 "第 2 位是 7"；不可用时返回空串。
   */
  useHint(pastGuesses: string[]): string {
    if (this.hintUsed || this.attemptsLeft() <= 1) {
      return '';
    }
    const candidates: number[] = [];
    for (let i = 0; i < this.digits; i++) {
      let confirmed = false;
      for (let g = 0; g < pastGuesses.length; g++) {
        if (pastGuesses[g].charAt(i) === this.secret.charAt(i)) {
          confirmed = true;
          break;
        }
      }
      if (!confirmed) {
        candidates.push(i);
      }
    }
    if (candidates.length === 0) {
      return '';
    }
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    this.hintUsed = true;
    this.attemptsUsed++; // 提示消耗一次机会
    return '第 ' + (pick + 1).toString() + ' 位是 ' + this.secret.charAt(pick);
  }

  // ==================== AI 军师 ====================

  /** 递归生成全部各位互不相同的 n 位数字排列 */
  private static buildPerms(n: number, prefix: string, used: boolean[], out: string[]): void {
    if (prefix.length === n) {
      out.push(prefix);
      return;
    }
    for (let d = 0; d <= 9; d++) {
      if (!used[d]) {
        used[d] = true;
        GameEngine.buildPerms(n, prefix + d.toString(), used, out);
        used[d] = false;
      }
    }
  }

  /**
   * AI 军师分析：完全基于公开的历史线索（records）做约束求解，不接触真实答案。
   * 1. 枚举全部候选密码，保留与每条 xAyB 线索都相容的；
   * 2. 推断"必含 / 必排除"的数字（在所有候选中都出现 / 都不出现）；
   * 3. 推荐下一步猜测：候选较少时用期望剩余候选数最小化（Knuth 式贪心），
   *    否则从候选中随机取一个合法猜测。
   */
  static analyze(n: number, records: GuessRecord[]): AiAdvice {
    const all: string[] = [];
    const used: boolean[] = [false, false, false, false, false, false, false, false, false, false];
    GameEngine.buildPerms(n, '', used, all);

    // 1. 过滤：候选 c 必须对每条历史记录复现出相同的 A/B
    const cands: string[] = [];
    for (let i = 0; i < all.length; i++) {
      const c = all[i];
      let ok = true;
      for (let r = 0; r < records.length; r++) {
        const ab = GameEngine.computeAB(c, records[r].guess);
        if (ab[0] !== records[r].a || ab[1] !== records[r].b) {
          ok = false;
          break;
        }
      }
      if (ok) {
        cands.push(c);
      }
    }

    const advice = new AiAdvice();
    advice.candidateCount = cands.length;
    if (cands.length === 0) {
      advice.summary = '线索出现矛盾，AI 也一头雾水…';
      return advice;
    }

    // 2. 数字判定
    for (let d = 0; d <= 9; d++) {
      const ch = d.toString();
      let inAll = true;
      let inNone = true;
      for (let i = 0; i < cands.length; i++) {
        if (cands[i].indexOf(ch) >= 0) {
          inNone = false;
        } else {
          inAll = false;
        }
        if (!inAll && !inNone) {
          break;
        }
      }
      if (inAll) {
        advice.mustInclude.push(ch);
      } else if (inNone) {
        advice.mustExclude.push(ch);
      }
    }

    // 3. 推荐猜测
    if (cands.length === 1) {
      advice.bestGuess = cands[0];
      advice.summary = '答案已被逻辑锁定，就是它！';
    } else if (cands.length <= 150) {
      // Knuth 式贪心：选使"期望剩余候选数"最小的猜测
      let best = cands[0];
      let bestScore = Number.MAX_VALUE;
      for (let g = 0; g < cands.length; g++) {
        const guess = cands[g];
        const buckets = new Map<string, number>();
        for (let c = 0; c < cands.length; c++) {
          const ab = GameEngine.computeAB(cands[c], guess);
          const key = ab[0].toString() + '_' + ab[1].toString();
          buckets.set(key, (buckets.get(key) ?? 0) + 1);
        }
        let score = 0;
        buckets.forEach((v: number) => {
          score += v * v; // Σ(桶大小²)/N = 期望剩余候选数
        });
        if (score < bestScore) {
          bestScore = score;
          best = guess;
        }
      }
      advice.bestGuess = best;
      advice.summary = cands.length <= 10
        ? '胜利在望，按推荐猜大概率一击致命'
        : '范围已大幅收窄，推荐的猜测信息量最大';
    } else {
      advice.bestGuess = cands[Math.floor(Math.random() * cands.length)];
      advice.summary = '可能性还很多，先用推荐猜测多套点线索';
    }
    return advice;
  }
}
