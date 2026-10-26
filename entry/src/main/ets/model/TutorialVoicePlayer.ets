import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { resourceManager } from '@kit.LocalizationKit';

export type TutorialVoiceState = 'idle' | 'loading' | 'playing' | 'paused' | 'completed' | 'error';

export class TutorialVoicePlayer {
  private player: media.AVPlayer | undefined = undefined;
  private rawPath: string = '';
  private generation: number = 0;
  private startingGeneration: number = -1;
  private disposed: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  private loadTimer: number = -1;

  private resources: resourceManager.ResourceManager;
  private onState: (state: TutorialVoiceState) => void;

  constructor(resources: resourceManager.ResourceManager, onState: (state: TutorialVoiceState) => void) {
    this.resources = resources;
    this.onState = onState;
  }

  private current(generation: number): boolean {
    return !this.disposed && generation === this.generation;
  }

  private clearLoadTimer(): void {
    if (this.loadTimer !== -1) {
      clearTimeout(this.loadTimer);
      this.loadTimer = -1;
    }
  }

  private enqueue(action: () => Promise<void>, generation: number): void {
    this.queue = this.queue.then(action).catch((): void => {
      this.fail(generation);
    });
  }

  private fail(generation: number): void {
    if (!this.current(generation)) {
      return;
    }
    this.generation++;
    this.clearLoadTimer();
    this.onState('error');
    this.queue = this.queue.then((): Promise<void> => this.releaseCurrent()).catch((): void => {});
  }

  private async releaseCurrent(): Promise<void> {
    const player = this.player;
    const path = this.rawPath;
    this.player = undefined;
    this.rawPath = '';
    // rawfile handles are closed by path, so releases and new opens must stay serialized.
    try {
      if (player && player.state !== 'released') {
        await player.release();
      }
    } finally {
      if (path.length > 0) {
        await this.resources.closeRawFd(path);
      }
    }
  }

  play(id: string): void {
    if (this.disposed) {
      return;
    }
    const generation = ++this.generation;
    this.clearLoadTimer();
    this.onState('loading');
    this.loadTimer = setTimeout((): void => this.fail(generation), 8000);
    this.enqueue(async (): Promise<void> => {
      await this.releaseCurrent();
      if (!this.current(generation)) {
        return;
      }
      const player = await media.createAVPlayer();
      this.player = player;
      if (!this.current(generation)) {
        await this.releaseCurrent();
        return;
      }
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (!this.current(generation)) {
          return;
        }
        if (state === 'initialized') {
          this.enqueue(async (): Promise<void> => {
            if (this.current(generation)) {
              player.audioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_GAME, rendererFlags: 0 };
              await player.prepare();
            }
          }, generation);
        } else if (state === 'prepared') {
          this.enqueue(async (): Promise<void> => {
            if (this.current(generation)) {
              this.startPlayback(player, generation);
            }
          }, generation);
        } else if (state === 'playing') {
          this.clearLoadTimer();
          this.onState('playing');
        } else if (state === 'paused') {
          this.onState('paused');
        } else if (state === 'completed') {
          this.clearLoadTimer();
          this.onState('completed');
          this.enqueue(async (): Promise<void> => {
            if (this.current(generation)) {
              await this.releaseCurrent();
            }
          }, generation);
        }
      });
      player.on('error', (): void => this.fail(generation));
      player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (this.current(generation) &&
          (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
            event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP)) {
          this.stop();
        }
      });
      player.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo): void => {
        if (this.current(generation) &&
          info.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE) {
          this.stop();
        }
      });
      const path = 'tutorial/zh-CN/' + id + '.wav';
      const fd = await this.resources.getRawFd(path);
      this.rawPath = path;
      if (!this.current(generation)) {
        await this.releaseCurrent();
        return;
      }
      player.fdSrc = { fd: fd.fd, offset: fd.offset, length: fd.length };
    }, generation);
  }

  private startPlayback(player: media.AVPlayer, generation: number): void {
    if (!this.current(generation) || this.startingGeneration === generation) {
      return;
    }
    this.startingGeneration = generation;
    // Native playback startup must not block cancellation or accept duplicate resume requests.
    player.play().then((): void => {
      if (this.startingGeneration === generation) {
        this.startingGeneration = -1;
      }
    }).catch((): void => {
      if (this.startingGeneration === generation) {
        this.startingGeneration = -1;
      }
      this.fail(generation);
    });
  }

  pause(): void {
    if (this.player?.state !== 'playing') {
      this.stop();
      return;
    }
    const generation = this.generation;
    this.enqueue(async (): Promise<void> => {
      if (this.current(generation) && this.player?.state === 'playing') {
        await this.player.pause();
      }
    }, generation);
  }

  resume(): void {
    const generation = this.generation;
    this.enqueue(async (): Promise<void> => {
      if (this.current(generation) && this.player?.state === 'paused') {
        this.startPlayback(this.player, generation);
      }
    }, generation);
  }

  stop(): void {
    const generation = ++this.generation;
    this.clearLoadTimer();
    if (!this.disposed) {
      this.onState('idle');
    }
    this.enqueue((): Promise<void> => this.releaseCurrent(), generation);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.stop();
    this.disposed = true;
  }
}
