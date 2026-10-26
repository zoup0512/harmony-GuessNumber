# 新手教程离线中文配音

## 来源与格式

- 唯一字幕/文案来源：`entry/src/main/ets/model/TutorialNarration.ets` 中的 `TUTORIAL_CLIPS`；本目录和脚本不维护另一份文案。
- 文件映射：每项生成 `clip.id.wav`，当前共 19 段。不修改、缩写或拆分原文。
- 生成器：Windows 本机 `System.Speech.Synthesis.SpeechSynthesizer`，声音为 `Microsoft Huihui Desktop`，区域为 `zh-CN`，`Rate = -1`，`Volume = 100`。
- 输出方式：`SetOutputToWaveFile`，显式指定 SAPI 支持的单声道、16 位 PCM、22050 Hz。未进行后期重采样、变速或增益处理；不调用任何在线 TTS 服务。
- 需要 Windows PowerShell 5.1、.NET Framework `System.Speech` 和已安装且启用的上述系统声音。脚本没有 Python、Node.js 或第三方包依赖，缺少指定声音时直接报错，不切换其他声音。

## 校验与重建

以下命令在项目 `GuessNumber` 根目录执行；也可通过绝对路径调用脚本。输入和输出路径由脚本自身位置推导，不依赖当前工作目录。

只校验已入库的音频，不合成也不覆盖文件：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tools\generate-tutorial-audio.ps1 -ValidateOnly
```

首次生成，或将现有 WAV 人工检查并移到资源目录外备份之后重建：

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tools\generate-tutorial-audio.ps1
```

脚本默认拒绝覆盖：若发现现有 WAV，会先校验整套资源，随后报错退出，不替换文件；部分缺失、额外 WAV、损坏文件或同名目录也会报错。脚本没有 `-Force` 参数。重建前请自行决定如何保管旧音频，`README.md` 无需移动。合成先写入唯一临时子目录，整套验证通过后才发布；最终移动也拒绝覆盖已出现的同名文件。正常结束或异常退出会清理该次临时目录；若进程被强制终止，可能留下 `.generation-*` 子目录，应检查后自行清理。

脚本严格消费整个数组，检查空文案、重复/不安全 ID，并明确核对默认数量 19。若经过评审增减条目，可传 `-ExpectedCount <新数量>`；不能靠忽略解析失败来继续。当前仅支持数组中的 `{ id: '...', text: '...' }` 普通单引号字面量，遇到转义、表达式、注释、字段顺序变化等不支持的语法会失败，需要先更新解析器，不会静默漏项。

请将 `tools/generate-tutorial-audio.ps1` 保持为 **UTF-8 with BOM**，以兼容 Windows PowerShell 5.1 的中文编码。ETS 以严格 UTF-8 解码。生成所用字符串直接来自 ETS，不做第二份配置。

这是可重复执行的离线生成流程，不保证不同 Windows / SAPI / 声音引擎版本产生逐字节相同的音频。修改文案后必须显式重建；`-ValidateOnly` 只能确认当前 ID/资源集合和音频结构、采样信息，不能证明现有录音与最新文案逐字一致。

## 本次实测结果

- 19/19 个 WAV 与当前 `TUTORIAL_CLIPS` ID 完整对应，无缺项、无额外 WAV。
- 全部通过 RIFF/WAVE 标识、RIFF 长度、块边界、`fmt`/`data` 块、PCM 编码、采样率、通道数、位深、字节率和采样对齐检查。
- 逐样本计算 RMS、峰值、非零样本数；全部通过非静音检查。校验要求时长在 0.25–300 秒、峰值至少 100、RMS 至少 10、非零样本占比至少 1%。
- WAV 原始资源总大小：**10,052,190 字节（9.587 MiB）**；这是未压缩资源大小，不等于最终 HAP 压缩后包体增量。
- 总时长：**227.921 秒（约 3 分 47.92 秒）**。
- 主线八段（`goal`、`demo`、`exact`、`misplaced`、`summary`、`strategy`、`practice`、`ready`）：**100.474 秒，4,431,290 字节（4.226 MiB）**，比 100 秒目标上限多 0.474 秒；不含交互等待和其他片段。使用精简后的原始文案重新合成，仍保持 `Rate = -1`，未加速。
- 最长片段：**`ready.wav`，14.560 秒**；最短片段：`practice_3_0.wav`，8.267 秒。
- 以上为机器结构与信号校验，**未进行人工试听**，不代表对发音、停顿、主观音质或字幕同步的验收。产品发布前仍需试听与交互联调。

## 版权与分发

声音来自本机安装的 Microsoft 系统语音引擎，并非真人录音。此处仅客观记录技术来源，**不声称已取得声音、合成输出或再分发的授权**。配音版权、商业使用及随应用分发的许可范围，需要产品/法务根据适用的 Microsoft、Windows 和语音组件许可条款确认后再决定是否发布。
