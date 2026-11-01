/**
 * BrainProfile.ets — 六维脑力画像
 *
 * 每局正式挑战结束后，根据玩家公开的推理过程（猜测序列与反馈）提取一份 BrainSession，
 * 再由最近若干局加权汇总出六个维度的 0–100 分：
 *   记忆力   不再使用已被线索排除的数字，也不把数字放回已证明错误的位置
 *   注意力   每次猜测都同时符合此前全部线索
 *   速度     平均每次猜测的思考用时，对比该难度的参考用时
 *   灵活性   相邻猜测之间敢于调换位置，并尝试不同难度
 *   问题解决 是否破解、消耗多少机会、对提示与 AI 的依赖
 *   想象力   开局阶段覆盖更多不同数字，开局猜法多变
 * 结果仅作游戏表现参考，不是医学或心理测评。
 */
import { GameEngine, GuessRecord } from './GameEngine';

export class BrainSession {
  t: number = 0;          // 结束时间戳
  d: number = 4;          // 位数
  win: boolean = false;
  used: number = 0;       // 消耗机会（含提示 / AI）
  max: number = 8;        // 总机会
  sec: number = 0;        // 用时（秒）
  g: number = 0;          // 猜测次数
  cons: number = 0;       // 与此前全部线索相容的猜测数（不含首猜）
  slips: number = 0;      // 出现"遗忘线索"的猜测数（不含首猜）
  move: number = 0;       // 相邻猜测平均换位比例 0..1
  explore: number = 0;    // 前两猜覆盖不同数字的比例 0..1
  open: string = '';      // 开局猜测
  hint: boolean = false;
  ai: number = 0;         // AI 分析使用次数
  bestA: number = 0;      // 单次最多正位
}

export interface DimensionInfo {
  name: string;
  color: string;
  bg: string;
  slogan: string;
  how: string;
  tip: string;
}

export const DIM_COUNT: number = 6;

export const DIMENSIONS: DimensionInfo[] = [
  {
    name: '记忆力', color: '#D9773F', bg: '#FBEFE6',
    slogan: '记住每条线索告诉你的事',
    how: '看你会不会再次用到已经出局的数字，或者把数字放回早已证明不对的位置。',
    tip: '每次猜之前，先在心里念一遍：哪些数字已经出局了？'
  },
  {
    name: '注意力', color: '#3D6D96', bg: '#E8EFF6',
    slogan: '把每一条线索都看清楚',
    how: '看你的每一次猜测，是否同时符合之前所有的正位和错位提示。',
    tip: '提交前从上往下核对一遍记录，确认新猜法和每一条都不打架。'
  },
  {
    name: '速度', color: '#B98A12', bg: '#FAF3DE',
    slogan: '想得又快又稳',
    how: '平均每次猜测的思考时间，和这个难度的参考用时做比较。',
    tip: '先求对、再求快。熟悉规则以后，可以给自己定一个小目标时间。'
  },
  {
    name: '灵活性', color: '#7461A5', bg: '#F0ECF7',
    slogan: '换个角度想问题',
    how: '看相邻两次猜测里你调换了多少位置，以及有没有挑战不同难度。',
    tip: '错位多的时候，大胆把数字挪个位置；也去试试没玩过的难度。'
  },
  {
    name: '问题解决', color: '#237A63', bg: '#E6F2EC',
    slogan: '用更少的步骤找到答案',
    how: '看你是否破解成功、消耗了几次机会，以及多依赖提示和 AI。',
    tip: '求助前先自己多想一步。每少用一次提示，你就更厉害一点。'
  },
  {
    name: '想象力', color: '#C2577A', bg: '#F9EAF0',
    slogan: '敢于尝试新组合',
    how: '看前两次猜测覆盖了多少不同的数字，以及每局开局是否有新花样。',
    tip: '开局别总猜 1234，试试 5、6、7、8、9、0 这些不常用的数字。'
  }
];

export interface BadgeInfo {
  name: string;
  desc: string;
}

export const BADGES: BadgeInfo[] = [
  { name: '六边形战士', desc: '六项能力都达到 70 分' },
  { name: '闪电脑', desc: '速度达到 90 分' },
  { name: '过目不忘', desc: '至少 3 局且记忆力达到 95 分' },
  { name: '百变魔方', desc: '入门、经典、大师都挑战过' },
  { name: '独立侦探', desc: '最近 3 局都不靠提示和 AI 破解' },
  { name: '坚持之星', desc: '累计完成 10 局正式挑战' }
];

export class TrainingPlan {
  dim: number = 0;
  digits: number = 3;
  title: string = '';
  detail: string = '';
}

export class BrainReport {
  total: number = 0;           // 已记录的总局数
  count: number = 0;           // 本期统计局数
  scores: number[] = [0, 0, 0, 0, 0, 0];
  previous: number[] = [];     // 上期六维；局数不足时为空
  previousCount: number = 0;
  overall: number = 0;
  previousOverall: number = -1;
  trend: number[] = [];        // 本期每局综合分，从旧到新
  trendWins: boolean[] = [];
  wins: number = 0;
  badges: boolean[] = [false, false, false, false, false, false];
  lastDigits: number = 4;
}

/** 本期统计窗口（最近 N 局） */
export const WINDOW: number = 10;
/** 上期至少需要的局数，才展示对比 */
const MIN_COMPARE: number = 3;

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function speedTarget(digits: number): number {
  if (digits <= 3) {
    return 15;
  }
  return digits === 4 ? 20 : 28;
}

export class BrainProfile {
  /** 由一局的公开猜测序列（从旧到新）提取推理特征 */
  static analyzeSession(digits: number, chrono: GuessRecord[], win: boolean, used: number, max: number,
    seconds: number, hint: boolean, ai: number): BrainSession {
    const s = new BrainSession();
    s.t = Date.now();
    s.d = digits;
    s.win = win;
    s.used = used;
    s.max = max;
    s.sec = seconds;
    s.g = chrono.length;
    s.hint = hint;
    s.ai = ai;
    s.open = chrono.length > 0 ? chrono[0].guess : '';

    const excluded: boolean[] = [];
    for (let i = 0; i < 10; i++) {
      excluded.push(false);
    }
    const wrongPos: boolean[] = [];
    for (let i = 0; i < digits * 10; i++) {
      wrongPos.push(false);
    }
    let moveSum = 0;

    for (let i = 0; i < chrono.length; i++) {
      const guess = chrono[i].guess;
      if (i > 0) {
        let consistent = true;
        let slip = false;
        for (let j = 0; j < i; j++) {
          const ab = GameEngine.computeAB(guess, chrono[j].guess);
          if (ab[0] !== chrono[j].a || ab[1] !== chrono[j].b) {
            consistent = false;
          }
          if (chrono[j].guess === guess) {
            slip = true;
          }
        }
        for (let p = 0; p < guess.length; p++) {
          const dgt = guess.charCodeAt(p) - 48;
          if (dgt >= 0 && dgt <= 9 && (excluded[dgt] || wrongPos[p * 10 + dgt])) {
            slip = true;
          }
        }
        if (consistent) {
          s.cons++;
        }
        if (slip) {
          s.slips++;
        }
        const prev = chrono[i - 1].guess;
        let changed = 0;
        for (let p = 0; p < guess.length; p++) {
          if (guess.charAt(p) !== prev.charAt(p)) {
            changed++;
          }
        }
        moveSum += changed / Math.max(1, digits);
      }

      // 吸收这条线索带来的确定信息
      const r = chrono[i];
      s.bestA = Math.max(s.bestA, r.a);
      for (let p = 0; p < guess.length; p++) {
        const dgt = guess.charCodeAt(p) - 48;
        if (dgt < 0 || dgt > 9) {
          continue;
        }
        if (r.a + r.b === 0) {
          excluded[dgt] = true;
        }
        if (r.a === 0) {
          wrongPos[p * 10 + dgt] = true;
        }
      }
      if (r.a + r.b === digits) {
        for (let dgt = 0; dgt < 10; dgt++) {
          if (guess.indexOf(dgt.toString()) < 0) {
            excluded[dgt] = true;
          }
        }
      }
    }

    s.move = chrono.length > 1 ? moveSum / (chrono.length - 1) : 0;
    const early = Math.min(2, chrono.length);
    if (early > 0) {
      const seen: boolean[] = [false, false, false, false, false, false, false, false, false, false];
      let distinct = 0;
      for (let i = 0; i < early; i++) {
        const guess = chrono[i].guess;
        for (let p = 0; p < guess.length; p++) {
          const dgt = guess.charCodeAt(p) - 48;
          if (dgt >= 0 && dgt <= 9 && !seen[dgt]) {
            seen[dgt] = true;
            distinct++;
          }
        }
      }
      s.explore = distinct / Math.min(10, digits * early);
    }
    return s;
  }

  /** 单局基础分：[记忆, 注意, 速度, 换位, 问题解决, 开局探索] */
  private static baseScores(s: BrainSession): number[] {
    const later = s.g - 1;
    const memory = later > 0 ? clamp(100 * (1 - s.slips / later), 10, 100) : 75;
    const attention = later > 0 ? clamp(100 * s.cons / later, 10, 100) : 75;

    const target = speedTarget(s.d);
    const perGuess = s.sec / Math.max(1, s.g);
    const speed = perGuess <= target ? 100 : clamp(100 * Math.pow(target / perGuess, 0.8), 15, 100);

    const move = later > 0 ? clamp(100 * s.move / 0.7, 10, 100) : 60;

    let solve = 0;
    if (s.win) {
      solve = 55 + 45 * (s.max - s.used) / Math.max(1, s.max - 1);
    } else {
      solve = 10 + 35 * s.bestA / Math.max(1, s.d);
    }
    solve -= (s.hint ? 5 : 0) + s.ai * 8;
    solve = clamp(solve, 5, 100);

    const explore = clamp(100 * s.explore, 0, 100);
    return [memory, attention, speed, move, solve, explore];
  }

  /** 按时间加权（越新越重）汇总一组局的六维分 */
  static aggregate(list: BrainSession[]): number[] {
    const sums: number[] = [0, 0, 0, 0, 0, 0];
    let wsum = 0;
    const difficulty: number[] = [];
    const openings: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const w = i + 1;
      const base = BrainProfile.baseScores(list[i]);
      for (let k = 0; k < DIM_COUNT; k++) {
        sums[k] += base[k] * w;
      }
      wsum += w;
      if (difficulty.indexOf(list[i].d) < 0) {
        difficulty.push(list[i].d);
      }
      if (list[i].open !== '' && openings.indexOf(list[i].open) < 0) {
        openings.push(list[i].open);
      }
    }
    const out: number[] = [0, 0, 0, 0, 0, 0];
    if (wsum === 0) {
      return out;
    }
    for (let k = 0; k < DIM_COUNT; k++) {
      out[k] = sums[k] / wsum;
    }
    out[3] = 0.75 * out[3] + 25 * difficulty.length / 3;
    out[5] = 0.7 * out[5] + 30 * openings.length / list.length;
    for (let k = 0; k < DIM_COUNT; k++) {
      out[k] = Math.round(clamp(out[k], 0, 100));
    }
    return out;
  }

  static average(values: number[]): number {
    if (values.length === 0) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < values.length; i++) {
      sum += values[i];
    }
    return Math.round(sum / values.length);
  }

  /** sessions 需按时间从旧到新排列 */
  static buildReport(sessions: BrainSession[]): BrainReport {
    const report = new BrainReport();
    report.total = sessions.length;
    if (sessions.length === 0) {
      return report;
    }
    const end = sessions.length;
    const recent = sessions.slice(Math.max(0, end - WINDOW), end);
    const prev = sessions.slice(Math.max(0, end - WINDOW * 2), Math.max(0, end - WINDOW));
    report.count = recent.length;
    report.scores = BrainProfile.aggregate(recent);
    report.overall = BrainProfile.average(report.scores);
    if (prev.length >= MIN_COMPARE) {
      report.previous = BrainProfile.aggregate(prev);
      report.previousCount = prev.length;
      report.previousOverall = BrainProfile.average(report.previous);
    }
    for (let i = 0; i < recent.length; i++) {
      report.trend.push(BrainProfile.average(BrainProfile.aggregate([recent[i]])));
      report.trendWins.push(recent[i].win);
      if (recent[i].win) {
        report.wins++;
      }
    }
    report.lastDigits = recent[recent.length - 1].d;

    const allDigits: number[] = [];
    for (let i = 0; i < sessions.length; i++) {
      if (allDigits.indexOf(sessions[i].d) < 0) {
        allDigits.push(sessions[i].d);
      }
    }
    let allHigh = true;
    for (let k = 0; k < DIM_COUNT; k++) {
      if (report.scores[k] < 70) {
        allHigh = false;
      }
    }
    let independent = recent.length >= 3;
    for (let i = Math.max(0, recent.length - 3); i < recent.length && independent; i++) {
      const s = recent[i];
      if (!s.win || s.hint || s.ai > 0) {
        independent = false;
      }
    }
    report.badges = [
      allHigh,
      report.scores[2] >= 90,
      recent.length >= 3 && report.scores[0] >= 95,
      allDigits.length >= 3,
      independent,
      sessions.length >= 10
    ];
    return report;
  }

  static strongest(scores: number[]): number {
    let best = 0;
    for (let k = 1; k < scores.length; k++) {
      if (scores[k] > scores[best]) {
        best = k;
      }
    }
    return best;
  }

  static weakest(scores: number[]): number {
    let worst = 0;
    for (let k = 1; k < scores.length; k++) {
      if (scores[k] < scores[worst]) {
        worst = k;
      }
    }
    return worst;
  }

  static levelTitle(overall: number): string {
    if (overall >= 85) {
      return '解密大师';
    }
    if (overall >= 70) {
      return '逻辑小达人';
    }
    if (overall >= 55) {
      return '推理小能手';
    }
    if (overall >= 40) {
      return '好奇小侦探';
    }
    return '脑力萌芽';
  }

  static stars(overall: number): string {
    const n = clamp(Math.round(overall / 20), 1, 5);
    let s = '';
    for (let i = 0; i < 5; i++) {
      s += i < n ? '★' : '☆';
    }
    return s;
  }

  /** 根据最弱维度给出下一局训练建议 */
  static plan(report: BrainReport): TrainingPlan {
    const plan = new TrainingPlan();
    const dim = BrainProfile.weakest(report.scores);
    plan.dim = dim;
    const winRate = report.count > 0 ? report.wins / report.count : 0;
    switch (dim) {
      case 0:
        plan.digits = 3;
        plan.title = '入门局 · 线索记忆练习';
        plan.detail = '数字少更好记。每猜一次，就说出一个已经出局的数字。';
        break;
      case 1:
        plan.digits = Math.max(3, report.lastDigits - 1);
        plan.title = '降一档 · 逐条核对练习';
        plan.detail = '难度放低一点，把注意力全用在“新猜法是否符合每条线索”上。';
        break;
      case 2:
        plan.digits = 3;
        plan.title = '入门局 · 快速反应练习';
        plan.detail = '在熟悉的难度上，试着比上一局少用一点时间。';
        break;
      case 3:
        plan.digits = report.lastDigits === 4 ? 5 : 4;
        plan.title = '换个难度 · 灵活变通练习';
        plan.detail = '换一个难度玩一局，遇到错位就大胆调换位置。';
        break;
      case 4:
        plan.digits = winRate >= 0.7 ? Math.min(5, report.lastDigits + 1) : report.lastDigits;
        plan.title = winRate >= 0.7 ? '升一档 · 独立破解挑战' : '同难度 · 少求助挑战';
        plan.detail = '这一局先不用提示和 AI，看看能不能自己想通。';
        break;
      default:
        plan.digits = 4;
        plan.title = '经典局 · 新奇开局练习';
        plan.detail = '开局前两猜尽量用上不同的数字，比如 5 6 7 8 和 9 0 1 2。';
        break;
    }
    return plan;
  }
}
