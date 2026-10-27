import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Theme } from '../common/Theme';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate<boolean>('appForeground', false);
    hilog.info(0x0000, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    AppStorage.setOrCreate<boolean>('appForeground', false);
    hilog.info(0x0000, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      // 沉浸式：内容延伸到系统栏之下，浅色背景搭配深色文字与图标
      try {
        const win = windowStage.getMainWindowSync();
        win.setWindowLayoutFullScreen(true);
        win.setWindowSystemBarProperties({
          statusBarColor: Theme.BG_TOP,
          statusBarContentColor: Theme.TEXT,
          navigationBarColor: Theme.BG_BOTTOM,
          navigationBarContentColor: Theme.TEXT
        });
      } catch (e) {
        hilog.warn(0x0000, TAG, 'set immersive window failed');
      }
      hilog.info(0x0000, TAG, 'Content loaded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('appForeground', true);
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('appForeground', false);
  }
}
