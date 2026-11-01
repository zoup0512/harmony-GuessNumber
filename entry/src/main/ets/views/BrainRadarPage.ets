/**
 * BrainRadarPage.ets — 脑力雷达
 * 以六维雷达图为核心：脑力指数与称号、本期 / 上期对比、维度详解、
 * 今日训练建议、最近对局走势、成长徽章。
 */
import { common } from '@kit.AbilityKit';
import {
  BADGES, BadgeInfo, BrainProfile, BrainReport, BrainSession, DIM_COUNT, DIMENSIONS, DimensionInfo,
  TrainingPlan, WINDOW
} from '../model/BrainProfile';
import { BrainStore } from '../model/BrainStore';
import { DIFFICULTIES } from '../model/GameEngine';
import { RadarChart } from '../common/RadarChart';
import { Theme } from '../common/Theme';

@Component
export struct BrainRadarPage {
  @Consume('pathStack') pathStack: NavPathStack;
  @State report: BrainReport = new BrainReport();
  @State loading: boolean = true;
  @State loadError: boolean = false;
  @State selected: number = 0;
  @State compare: boolean = true;
  @State chartSize: number = 300;
  @State plan: TrainingPlan = new TrainingPlan();

  aboutToAppear(): void {
    this.load();
  }

  load(): void {
    const ctx = this.getUIContext().getHostContext() as common.Context;
    this.loading = true;
    this.loadError = false;
    BrainStore.load(ctx).then((list: BrainSession[]) => {
      const report = BrainProfile.buildReport(list);
      this.plan = BrainProfile.plan(report);
      this.selected = report.count > 0 ? BrainProfile.strongest(report.scores) : 0;
      this.report = report;
      this.loading = false;
    }).catch(() => {
      this.report = new BrainReport();
      this.loading = false;
      this.loadError = true;
    });
  }

  hasData(): boolean {
    return !this.loading && this.report.count > 0;
  }

  difficultyName(digits: number): string {
    for (let i = 0; i < DIFFICULTIES.length; i++) {
      if (DIFFICULTIES[i].digits === digits) {
        return DIFFICULTIES[i].name;
      }
    }
    return '';
  }

  startGame(digits: number): void {
    this.pathStack.pushPathByName('game', digits, () => {
      this.load();
    });
  }

  delta(i: number): number {
    if (this.report.previous.length !== DIM_COUNT) {
      return 0;
    }
    return this.report.scores[i] - this.report.previous[i];
  }

  deltaText(v: number): string {
    if (v > 0) {
      return '↑' + v.toString();
    }
    if (v < 0) {
      return '↓' + (-v).toString();
    }
    return '持平';
  }

  deltaColor(v: number): string {
    if (v > 0) {
      return Theme.PRIMARY;
    }
    return v < 0 ? Theme.RED : Theme.TEXT_FAINT;
  }

  hasPrevious(): boolean {
    return this.report.previous.length === DIM_COUNT;
  }

  comment(): string {
    if (!this.hasData()) {
      return '完成第一局正式挑战，就能点亮你的脑力雷达。';
    }
    const best = DIMENSIONS[BrainProfile.strongest(this.report.scores)].name;
    const weak = DIMENSIONS[BrainProfile.weakest(this.report.scores)].name;
    if (best === weak) {
      return '六项能力很均衡，继续保持！';
    }
    return '你的「' + best + '」最闪亮，「' + weak + '」还有成长空间。';
  }

  // ---------- UI ----------

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
      .onClick(() => this.pathStack.pop())
      Column({ space: 2 }) {
        Text('脑力雷达')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        Text('六维能力 · 每局推理自动生成')
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  ScoreHero() {
    Row({ space: 16 }) {
      Stack() {
        Column()
          .width(84)
          .height(84)
          .backgroundColor(Theme.PRIMARY_BG)
          .borderWidth(3)
          .borderColor(Theme.PRIMARY)
          .borderRadius(42)
        Column() {
          Text(this.hasData() ? this.report.overall.toString() : '--')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.PRIMARY)
          Text('脑力指数')
            .fontSize(10)
            .fontColor(Theme.TEXT_SUB)
        }
      }
      .width(84)
      .height(84)

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.hasData() ? BrainProfile.levelTitle(this.report.overall) : '等待点亮')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.TEXT)
          if (this.hasData() && this.report.previousOverall >= 0) {
            Text(this.deltaText(this.report.overall - this.report.previousOverall))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.deltaColor(this.report.overall - this.report.previousOverall))
          }
        }
        if (this.hasData()) {
          Text(BrainProfile.stars(this.report.overall))
            .fontSize(16)
            .fontColor('#D4A72C')
            .accessibilityText(Math.round(this.report.overall / 20).toString() + ' 颗星')
        }
        Text(this.comment())
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
          .lineHeight(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  @Builder
  RadarCard() {
    Column({ space: 10 }) {
      Row() {
        Text(this.hasData() ? '最近 ' + this.report.count.toString() + ' 局' : '六维脑力')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
        Blank()
        if (this.hasPrevious()) {
          Row({ space: 6 }) {
            Text('对比前 ' + this.report.previousCount.toString() + ' 局')
              .fontSize(12)
              .fontColor(Theme.TEXT_SUB)
            Toggle({ type: ToggleType.Switch, isOn: this.compare })
              .selectedColor(Theme.PRIMARY)
              .width(40)
              .height(24)
              .onChange((on: boolean) => {
                this.compare = on;
              })
          }
        }
      }
      .width('100%')

      Row() {
        RadarChart({
          values: this.report.scores,
          previous: this.compare && this.hasPrevious() ? this.report.previous : [],
          selected: this.hasData() ? this.selected : -1,
          placeholder: !this.hasData(),
          chartSize: this.chartSize,
          onSelect: (i: number): void => {
            this.selected = i;
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .onAreaChange((oldArea: Area, area: Area) => {
        const w = Number(area.width);
        if (w > 0) {
          this.chartSize = Math.min(360, w);
        }
      })

      if (this.hasData()) {
        Row({ space: 16 }) {
          Row({ space: 5 }) {
            Column().width(16).height(3).backgroundColor(Theme.PRIMARY).borderRadius(2)
            Text('本期').fontSize(11).fontColor(Theme.TEXT_SUB)
          }
          if (this.compare && this.hasPrevious()) {
            Row({ space: 5 }) {
              Row({ space: 2 }) {
                Column().width(5).height(2).backgroundColor('#8E9C95')
                Column().width(5).height(2).backgroundColor('#8E9C95')
              }
              Text('上期').fontSize(11).fontColor(Theme.TEXT_SUB)
            }
          }
          Text('点击维度查看详情').fontSize(11).fontColor(Theme.TEXT_FAINT)
        }
      } else if (!this.loading) {
        Column({ space: 10 }) {
          Text(this.loadError ? '记录读取失败' : '还没有脑力数据')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT)
          Text(this.loadError ? '点击下方按钮重新读取。'
            : '每完成一局正式挑战，雷达就会根据你的推理过程更新一次。新手教学不计入。')
            .fontSize(12)
            .fontColor(Theme.TEXT_SUB)
            .lineHeight(18)
            .textAlign(TextAlign.Center)
          Text(this.loadError ? '重新读取' : '来一局入门挑战')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.ON_PRIMARY)
            .textAlign(TextAlign.Center)
            .height(44)
            .width('70%')
            .backgroundColor(Theme.PRIMARY)
            .borderRadius(Theme.R_KEY)
            .onClick(() => {
              if (this.loadError) {
                this.load();
              } else {
                this.startGame(3);
              }
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  @Builder
  DimensionChip(d: DimensionInfo, i: number) {
    Column({ space: 6 }) {
      Row({ space: 5 }) {
        Column().width(8).height(8).backgroundColor(d.color).borderRadius(4)
        Text(d.name)
          .fontSize(12)
          .fontColor(this.selected === i ? d.color : Theme.TEXT_SUB)
          .fontWeight(this.selected === i ? FontWeight.Bold : FontWeight.Normal)
      }
      Row({ space: 4 }) {
        Text(this.report.scores[i].toString())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT)
        if (this.hasPrevious()) {
          Text(this.deltaText(this.delta(i)))
            .fontSize(11)
            .fontColor(this.deltaColor(this.delta(i)))
        }
      }
      .alignItems(VerticalAlign.Bottom)
      Stack({ alignContent: Alignment.Start }) {
        Column().width('100%').height(5).backgroundColor(Theme.CARD_STRONG).borderRadius(3)
        Column()
          .width(this.report.scores[i].toString() + '%')
          .height(5)
          .backgroundColor(d.color)
          .borderRadius(3)
          .animation({ duration: 600, curve: Curve.EaseOut })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor(this.selected === i ? d.bg : Theme.CARD)
    .borderRadius(Theme.R_CARD - 6)
    .borderWidth(this.selected === i ? 2 : 1)
    .borderColor(this.selected === i ? d.color : Theme.STROKE)
    .accessibilityText(d.name + ' ' + this.report.scores[i].toString() + ' 分' +
      (this.selected === i ? '，已选中' : ''))
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.selected = i;
    })
  }

  @Builder
  DimensionGrid() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.DimensionChip(DIMENSIONS[0], 0)
        this.DimensionChip(DIMENSIONS[1], 1)
        this.DimensionChip(DIMENSIONS[2], 2)
      }
      .width('100%')
      Row({ space: 10 }) {
        this.DimensionChip(DIMENSIONS[3], 3)
        this.DimensionChip(DIMENSIONS[4], 4)
        this.DimensionChip(DIMENSIONS[5], 5)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  DetailCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(DIMENSIONS[this.selected].name)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(DIMENSIONS[this.selected].color)
        Text(DIMENSIONS[this.selected].slogan)
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
          .layoutWeight(1)
        Text(this.report.scores[this.selected].toString())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(DIMENSIONS[this.selected].color)
      }
      .width('100%')
      this.DetailLine('游戏里怎么看', DIMENSIONS[this.selected].how)
      this.DetailLine('训练小妙招', DIMENSIONS[this.selected].tip)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DIMENSIONS[this.selected].bg)
    .borderRadius(Theme.R_CARD)
    .animation({ duration: 200, curve: Curve.EaseOut })
  }

  @Builder
  DetailLine(title: string, text: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT)
      Text(text)
        .fontSize(13)
        .fontColor(Theme.TEXT_SUB)
        .lineHeight(20)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PlanCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('今日训练')
          .fontSize(12)
          .fontColor(Theme.ON_PRIMARY)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(DIMENSIONS[this.plan.dim].color)
          .borderRadius(999)
        Text('重点提升 · ' + DIMENSIONS[this.plan.dim].name)
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
      }
      Text(this.plan.title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.TEXT)
      Text(this.plan.detail)
        .fontSize(13)
        .fontColor(Theme.TEXT_SUB)
        .lineHeight(20)
      Text('开始' + this.difficultyName(this.plan.digits) + '挑战')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.ON_PRIMARY)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(46)
        .backgroundColor(Theme.PRIMARY)
        .borderRadius(Theme.R_KEY)
        .onClick(() => this.startGame(this.plan.digits))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  @Builder
  TrendCard() {
    Column({ space: 12 }) {
      Row() {
        Text('最近对局走势')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
        Blank()
        Text('破解 ' + this.report.wins.toString() + ' / ' + this.report.count.toString())
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
      }
      .width('100%')
      Row({ space: 6 }) {
        ForEach(this.report.trend, (v: number, idx: number) => {
          Column({ space: 4 }) {
            Text(v.toString())
              .fontSize(10)
              .fontColor(Theme.TEXT_SUB)
            Column()
              .width('100%')
              .height(Math.max(6, v * 0.8))
              .backgroundColor(this.report.trendWins[idx] ? Theme.PRIMARY : '#B9C5BF')
              .borderRadius({ topLeft: 5, topRight: 5 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
          .height('100%')
          .accessibilityText('第 ' + (idx + 1).toString() + ' 局，' + v.toString() + ' 分，' +
            (this.report.trendWins[idx] ? '破解成功' : '未破解'))
        }, (v: number, idx: number) => idx.toString() + '_' + v.toString())
        // 占位，保证柱宽稳定
        ForEach(this.trendPadding(), (n: number) => {
          Column().layoutWeight(1)
        }, (n: number) => 'pad' + n.toString())
      }
      .width('100%')
      .height(104)
      .alignItems(VerticalAlign.Bottom)
      Row({ space: 14 }) {
        Row({ space: 5 }) {
          Column().width(10).height(10).backgroundColor(Theme.PRIMARY).borderRadius(2)
          Text('破解成功').fontSize(11).fontColor(Theme.TEXT_SUB)
        }
        Row({ space: 5 }) {
          Column().width(10).height(10).backgroundColor('#B9C5BF').borderRadius(2)
          Text('未破解').fontSize(11).fontColor(Theme.TEXT_SUB)
        }
        Blank()
        Text('从旧到新 →').fontSize(11).fontColor(Theme.TEXT_FAINT)
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

  trendPadding(): number[] {
    const pad: number[] = [];
    for (let i = this.report.trend.length; i < WINDOW; i++) {
      pad.push(i);
    }
    return pad;
  }

  @Builder
  BadgeItem(b: BadgeInfo, i: number) {
    Column({ space: 6 }) {
      Stack() {
        Polygon()
          .width(40)
          .height(44)
          .points([[20, 2], [38, 12], [38, 32], [20, 42], [2, 32], [2, 12]])
          .fill(this.report.badges[i] ? DIMENSIONS[i].bg : Theme.CARD_STRONG)
          .stroke(this.report.badges[i] ? DIMENSIONS[i].color : Theme.STROKE)
          .strokeWidth(2)
        Text(this.report.badges[i] ? '★' : '?')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.report.badges[i] ? DIMENSIONS[i].color : Theme.TEXT_FAINT)
      }
      .width(40)
      .height(44)
      Text(b.name)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.report.badges[i] ? Theme.TEXT : Theme.TEXT_SUB)
      Text(b.desc)
        .fontSize(10)
        .fontColor(Theme.TEXT_FAINT)
        .textAlign(TextAlign.Center)
        .lineHeight(14)
        .maxLines(2)
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .opacity(this.report.badges[i] ? 1 : 0.75)
    .accessibilityText(b.name + '，' + b.desc + '，' + (this.report.badges[i] ? '已获得' : '未获得'))
  }

  badgeCount(): number {
    let n = 0;
    for (let i = 0; i < this.report.badges.length; i++) {
      if (this.report.badges[i]) {
        n++;
      }
    }
    return n;
  }

  @Builder
  BadgeCard() {
    Column({ space: 12 }) {
      Row() {
        Text('成长徽章')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT)
        Blank()
        Text('已点亮 ' + this.badgeCount().toString() + ' / ' + BADGES.length.toString())
          .fontSize(12)
          .fontColor(Theme.TEXT_SUB)
      }
      .width('100%')
      Row({ space: 6 }) {
        this.BadgeItem(BADGES[0], 0)
        this.BadgeItem(BADGES[1], 1)
        this.BadgeItem(BADGES[2], 2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      Row({ space: 6 }) {
        this.BadgeItem(BADGES[3], 3)
        this.BadgeItem(BADGES[4], 4)
        this.BadgeItem(BADGES[5], 5)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD)
    .borderRadius(Theme.R_CARD)
    .borderWidth(1)
    .borderColor(Theme.STROKE)
  }

  build() {
    NavDestination() {
      Column() {
        this.Header()
        Scroll() {
          Column({ space: 14 }) {
            this.ScoreHero()
            this.RadarCard()
            if (this.hasData()) {
              if (this.report.count < 3) {
                Text('再完成 ' + (3 - this.report.count).toString() + ' 局，雷达会更准确')
                  .fontSize(12)
                  .fontColor(Theme.PRIMARY)
                  .width('100%')
                  .textAlign(TextAlign.Center)
              }
              this.DimensionGrid()
              this.DetailCard()
              this.PlanCard()
              this.TrendCard()
            }
            this.BadgeCard()
            Text('给家长：六维分数由每局公开的推理过程（猜测、反馈、用时、求助次数）计算，统计最近 ' +
              WINDOW.toString() + ' 局，越新的对局权重越高；仅作游戏表现参考，不是医学或心理测评。' +
              '数据只保存在本设备，不会上传。')
              .fontSize(11)
              .fontColor(Theme.TEXT_FAINT)
              .lineHeight(17)
              .width('100%')
          }
          .width('100%')
          .padding({ top: 14, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18, top: 48, bottom: 12 })
    }
    .hideTitleBar(true)
    .backgroundColor(Theme.BG_TOP)
  }
}
