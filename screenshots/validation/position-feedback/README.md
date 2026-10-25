# 正位／错位图标：HarmonyOS 模拟器闭环验证

日期：2026-10-25

## 结论

在同一台本地 HarmonyOS Pura90 模拟器上先安装修复前的包，复现「外框正常、内部对勾不见、箭头仅左上残影」；再覆盖安装单 Path 修复后的包，在相同教学步骤及实际对局中确认两种图标完整显示。本次不是浏览器模拟或仅编译检查。

## 环境

- 原生 HarmonyOS Emulator：6.1.1.350，实例 `Pura90`。
- 镜像目录标识：HarmonyOS-6.1.1 / phone_all_x86。
- 设备实际返回：`const.ohos.fullname=OpenHarmony-6.1.1.125`，API 24。
- `const.product.software.version=emulator 6.1.0.126(SP1DEVC00E120R4P11)`。
- 分辨率 1320 × 2856，像素密度倍率 3.5，逻辑尺寸约 377 × 816 vp。
- HDC：`127.0.0.1:6555`，使用 `uitest dumpLayout / uiInput / screenCap` 操作并截图。
- 未重置模拟器、未清空应用数据、未修改项目签名配置或系统环境。

## 修复

`entry/src/main/ets/common/GuessFeedback.ets`：将外框与内部符号合并为 Shape 下的单一直接子 Path；根据 `exact` 选择命令字符串，不再在 Shape 内用 if/else 创建子 Path。保留 px 视口与 px 描边、vp 显示尺寸。

## 测试结果

| 检查项 | 操作与结果 | 截图 |
| --- | --- | --- |
| 旧版问题复现 | 教学第二步，5234 / 5346 示例；外框正常但框内符号缺失 | [修复前](before-tutorial-feedback.png) |
| 同场景修复验证 | 覆盖安装新版，重新进入同一教学步骤；正位对勾、错位双向箭头完整居中 | [修复后](after-tutorial-feedback.png) |
| 首页 24vp 图标 | 返回首页，两种主视觉图标正常 | [首页](after-home.png) |
| 规则说明 | 打开规则并滚动至示例，正位1、错位2可见，滚动及关闭正常 | [规则](after-rules-scrolled.png) |
| 对局空态 | 开始四位对局，两类说明图标完整显示 | [空态](after-game-empty.png) |
| 策略卡 | 三组示例均显示两类图标及0值 | [策略](after-strategy.png) |
| 练习记录 | 输入123自动提交，教练文本与汇总反馈显示正常 | [练习](after-practice-feedback.png) |
| 三位正式对局 | 输入123自动提交，历史出现两类图标及数量 | [三位](after-game-3digits.png) |
| 四位正式对局 | 输入1234自动提交，零值保留、图标完整 | [四位](after-game-4digits.png) |
| 五位正式对局 | 输入12345自动提交，数字和反馈无横向挤压 | [五位](after-game-5digits.png) |
| 提示与AI按钮 | 四位局猜测后7/8；点击提示变6/8且显示“提示已用”；点击AI弹出分析面板、关闭后5/8且AI剩1次。两个按钮内容均在屏内 | [使用后](after-actions-used.png) |
| 最终复测 | 返回首页重新进入四位局并提交，模拟器保留在该页面 | [最终对局](after-final-game.png) |

对相同教学截图使用UI树中的标签边界定位图标中央区域，统计对应青绿／紫色像素：旧版为0／0，新版为233／529。该检查辅助验证框内符号确实恢复，图标形状和布局另经实际截图检查。

应用进程 `hilog -x -P <pid> -L E,F` 查询结果为空；本次操作未出现崩溃。

## 构建与部署边界

- `CompileArkTS`、`PackageHap`、`PackingCheck` 通过。
- 完整 `assembleHap` 的 `SignHap` 仍被原有无效 `storeFile` 配置阻塞；没有声称签名构建成功。
- 本地开发模拟器成功接受未签名 HAP，直接通过 HDC 安装后运行。没有绕过或修改签名校验配置。
- 仍有17处既有可能抛异常警告（StatsStore 13处、GamePage showToast 4处），不属于本次路径改动。
- 覆盖一台API24、3.5倍率的HarmonyOS模拟器；未在用户物理手机或其它系统版本上验证。

## 测试对象指纹

源码 `GuessFeedback.ets` SHA-256：

`fb26eeedaa09acb67704c3dd2e5256796ef1466b1cd8e61542718ce19e33d142`

运行包 `entry/build/default/outputs/default/entry-default-unsigned.hap` SHA-256：

`d49958ee05e8d5f32ed16e734766a28febd8d62a8651be64c67a24eb628ac143`
