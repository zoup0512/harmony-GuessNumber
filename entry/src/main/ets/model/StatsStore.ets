/**
 * StatsStore.ets — 解谜记录本地持久化（@ohos.data.preferences）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class Stats {
  played: number = 0;
  wins: number = 0;
  best: number = 0; // 成功破解的最少消耗机会，含提示和 AI；0 表示暂无
}

const PREF_NAME: string = 'guess_stats';
const KEY_PLAYED: string = 'played';
const KEY_WINS: string = 'wins';
const KEY_BEST: string = 'best';
const KEY_TUTORIAL: string = 'tutorial_done';
const KEY_TUTORIAL_VOICE: string = 'tutorial_voice_enabled';

export class StatsStore {
  private static queue: Promise<void> = Promise.resolve();

  private static async pref(ctx: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(ctx, PREF_NAME);
  }

  private static statsKey(digits: number): string {
    if (digits !== 3 && digits !== 4 && digits !== 5) {
      throw new Error('Unsupported challenge difficulty');
    }
    return 'challenge_v2_' + digits.toString();
  }

  private static enqueue(operation: () => Promise<Stats>): Promise<Stats> {
    const result = StatsStore.queue.then(operation);
    StatsStore.queue = result.then(() => {}, () => {});
    return result;
  }

  private static async readStats(p: preferences.Preferences, key: string): Promise<Stats> {
    const raw = await p.get(key, '') as string;
    if (raw === '') {
      return new Stats();
    }
    const saved = JSON.parse(raw) as Stats;
    if (!Number.isInteger(saved.played) || saved.played < 0 ||
      !Number.isInteger(saved.wins) || saved.wins < 0 || saved.wins > saved.played ||
      !Number.isInteger(saved.best) || saved.best < 0 ||
      (saved.wins === 0 ? saved.best !== 0 : saved.best === 0)) {
      throw new Error('Invalid challenge statistics');
    }
    const stats = new Stats();
    stats.played = saved.played;
    stats.wins = saved.wins;
    stats.best = saved.best;
    return stats;
  }

  static load(ctx: common.Context, digits: number): Promise<Stats> {
    return StatsStore.enqueue(async (): Promise<Stats> => {
      const key = StatsStore.statsKey(digits);
      const p = await StatsStore.pref(ctx);
      return await StatsStore.readStats(p, key);
    });
  }

  // 旧版只有汇总，不能据此推断或分配难度。
  static loadLegacy(ctx: common.Context): Promise<Stats> {
    return StatsStore.enqueue(async (): Promise<Stats> => {
      const p = await StatsStore.pref(ctx);
      const stats = new Stats();
      stats.played = await p.get(KEY_PLAYED, 0) as number;
      stats.wins = await p.get(KEY_WINS, 0) as number;
      stats.best = await p.get(KEY_BEST, 0) as number;
      return stats;
    });
  }

  static recordResult(ctx: common.Context, digits: number, win: boolean, attempts: number): Promise<Stats> {
    return StatsStore.enqueue(async (): Promise<Stats> => {
      const key = StatsStore.statsKey(digits);
      if (!Number.isInteger(attempts) || attempts <= 0) {
        throw new Error('Invalid consumed opportunities');
      }
      const p = await StatsStore.pref(ctx);
      const stats = await StatsStore.readStats(p, key);
      stats.played++;
      if (win) {
        stats.wins++;
        if (stats.best === 0 || attempts < stats.best) {
          stats.best = attempts;
        }
      }
      await p.put(key, JSON.stringify(stats));
      await p.flush();
      return stats;
    });
  }

  /** 新手引导是否已完成（含跳过） */
  static async isTutorialDone(ctx: common.Context): Promise<boolean> {
    const p = await StatsStore.pref(ctx);
    return await p.get(KEY_TUTORIAL, false) as boolean;
  }

  static async isTutorialVoiceEnabled(ctx: common.Context): Promise<boolean> {
    const p = await StatsStore.pref(ctx);
    return await p.get(KEY_TUTORIAL_VOICE, false) as boolean;
  }

  static async setTutorialVoiceEnabled(ctx: common.Context, enabled: boolean): Promise<void> {
    const p = await StatsStore.pref(ctx);
    await p.put(KEY_TUTORIAL_VOICE, enabled);
    await p.flush();
  }

  /** 标记新手引导已完成 */
  static async setTutorialDone(ctx: common.Context): Promise<void> {
    const p = await StatsStore.pref(ctx);
    await p.put(KEY_TUTORIAL, true);
    await p.flush();
  }
}
