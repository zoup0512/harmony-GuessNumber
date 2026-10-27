# 清爽数字棋盘主题验证

日期：2026-10-27  
分支：`feat/clean-number-board`

## 实现范围

- 暖白／浅灰页面、蓝绿色主行动色、绿紫正位／错位反馈。
- 首页数字棋盘主视觉，难度优先于战绩；位数和机会分行显示。
- 对局增加推理记录标题，降低计时与辅助功能视觉权重，统一矢量图标。
- 教学、语音面板、规则、AI 分析、结果卡、启动窗口及系统栏同步浅色。
- 保持难度、反馈规则、提示和 AI 扣次、自动提交及教学语音行为不变。
- 求助按钮在最后一次机会时禁用并说明原因；AI 推荐操作明确标注“填入并提交”。
- 五位输入、AI 判定格和推荐区、结果答案适配紧凑布局。
- 本次不更换应用桌面图标，不增加主题切换功能。

## 自动验证

工程根目录执行：

```bash
"C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe" --test tests/*.test.cjs

DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk" \
PATH="/c/Program Files/Huawei/DevEco Studio/jbr/bin:$PATH" \
"C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat" \
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon

git diff --check
```

`board-theme.test.cjs` 覆盖主题引用完整性、无表情装饰、小字号正文及反馈颜色的 4.5:1 对比度、最后机会求助限制和五位格子的紧凑宽度预算。静态布局预算不等同于设备渲染测试。

最终结果：74 项离线测试全部通过（0 失败、0 跳过）；最终 `assembleHap` 编译、打包和签名成功；`git diff --check` 无补丁错误，仅提示已有测试文件的 LF／CRLF 转换。

## 设备验收及边界

`home.png` 是本轮构建安装后的真实首页截图（不是设计稿），已人工查看：主文字、难度卡、分行说明、战绩和开始按钮正常显示，无截图中可见的裁切。截图来自无线连接的 HarmonyOS 真机，不是模拟器。截图先于最后一次辅助文字加深和 AI 布局修正；首页主体未变。

本机启动了已有 Pura90／Pura 90 模拟器，没有重置数据。可连接模拟器上的已有应用与当前签名不一致，覆盖安装报 `9568332 install sign info inconsistent`；未卸载应用或清除数据。

无线设备保留数据安装成功，启动后获取了首页和对局的原生布局，确认正式对局的输入格、推理记录标题、辅助按钮及键盘已出现。后续前台切换到了电话界面，立即停止操作并删除误采集的非应用截图。因此不将后续点击算作自动提交验证，也不声称完成五位 AI 面板、胜负结算、四步教学或语音播放的设备视觉验收。

构建仍有原有异常处理告警（StatsStore、toast 和 TutorialVoicePlayer），不阻断打包；本轮未扩展修改这些逻辑。
