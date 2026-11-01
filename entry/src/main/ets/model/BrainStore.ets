/**
 * BrainStore.ets — 六维脑力画像的本地持久化（仅保存在本设备）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BrainSession } from './BrainProfile';

const PREF_NAME: string = 'guess_stats';
const KEY_SESSIONS: string = 'brain_sessions_v1';
/** 最多保留的局数，足够覆盖本期 + 上期对比 */
const MAX_SESSIONS: number = 40;

function validNumber(v: number, min: number, max: number): boolean {
  return typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
}

export class BrainStore {
  private static queue: Promise<void> = Promise.resolve();

  private static enqueue(operation: () => Promise<BrainSession[]>): Promise<BrainSession[]> {
    const result = BrainStore.queue.then(operation);
    BrainStore.queue = result.then(() => {}, () => {});
    return result;
  }

  private static sanitize(item: BrainSession): BrainSession | undefined {
    if (item === null || item === undefined) {
      return undefined;
    }
    if (!validNumber(item.d, 3, 5) || !validNumber(item.g, 0, 100) || !validNumber(item.used, 0, 100) ||
      !validNumber(item.max, 1, 100) || !validNumber(item.sec, 0, 864000) ||
      !validNumber(item.cons, 0, 100) || !validNumber(item.slips, 0, 100) ||
      !validNumber(item.move, 0, 1) || !validNumber(item.explore, 0, 1) ||
      !validNumber(item.ai, 0, 10) || !validNumber(item.bestA, 0, 5) || typeof item.win !== 'boolean') {
      return undefined;
    }
    const s = new BrainSession();
    s.t = validNumber(item.t, 0, Number.MAX_SAFE_INTEGER) ? item.t : 0;
    s.d = item.d;
    s.win = item.win;
    s.used = item.used;
    s.max = item.max;
    s.sec = item.sec;
    s.g = item.g;
    s.cons = item.cons;
    s.slips = item.slips;
    s.move = item.move;
    s.explore = item.explore;
    s.open = typeof item.open === 'string' ? item.open : '';
    s.hint = item.hint === true;
    s.ai = item.ai;
    s.bestA = item.bestA;
    return s;
  }

  private static async read(p: preferences.Preferences): Promise<BrainSession[]> {
    const raw = await p.get(KEY_SESSIONS, '') as string;
    if (raw === '') {
      return [];
    }
    const parsed = JSON.parse(raw) as BrainSession[];
    const out: BrainSession[] = [];
    if (!Array.isArray(parsed)) {
      return out;
    }
    for (let i = 0; i < parsed.length; i++) {
      const s = BrainStore.sanitize(parsed[i]);
      if (s !== undefined) {
        out.push(s);
      }
    }
    return out;
  }

  /** 读取全部记录，按时间从旧到新 */
  static load(ctx: common.Context): Promise<BrainSession[]> {
    return BrainStore.enqueue(async (): Promise<BrainSession[]> => {
      const p = await preferences.getPreferences(ctx, PREF_NAME);
      return await BrainStore.read(p);
    });
  }

  static append(ctx: common.Context, session: BrainSession): Promise<BrainSession[]> {
    return BrainStore.enqueue(async (): Promise<BrainSession[]> => {
      const p = await preferences.getPreferences(ctx, PREF_NAME);
      let list: BrainSession[] = [];
      try {
        list = await BrainStore.read(p);
      } catch (e) {
        list = []; // 损坏的数据不阻塞新记录
      }
      list.push(session);
      if (list.length > MAX_SESSIONS) {
        list = list.slice(list.length - MAX_SESSIONS);
      }
      await p.put(KEY_SESSIONS, JSON.stringify(list));
      await p.flush();
      return list;
    });
  }
}
