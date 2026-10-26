# 数字解密（Guess Number / 1A2B）— HarmonyOS

经典 1A2B 猜数字益智游戏的鸿蒙原生实现（ArkTS / Stage 模型）。

- bundleName: com.razor.h.v2.guess
- SDK: 6.0.2(22)
- 功能：三档难度、定制防错键盘、猜测历史、用时记录、单次提示、战绩持久化、离线语音新手引导

## 运行
1. DevEco Studio（含 API 22 SDK）打开本目录，等待 Sync 完成；
2. 无需勾选自动签名：仓库已内置 Debug 签名配置，直接构建或 Run ▶；
3. 连接真机或模拟器，Run ▶。

详见 GuessNumber_Design_Document.md。

## 签名（跨开发机复用）

Debug 签名材料固定在 `keystore/debug/`，`build-profile.json5` 只引用仓库内的相对路径，因此任意开发机 clone 后构建出的 HAP 使用同一套证书与 Profile，无需每台机器各自“自动签名”：

- `debug.cer` / `debug.p12` / `debug.p7b`：开发者证书、密钥库、Debug Profile；
- `material/`：DevEco 用于解密 `build-profile.json5` 中加密口令的密钥材料，必须与 `debug.p12` 放在同一目录旁（hvigor 固定读取 `dirname(storeFile)/material`）。缺少它时构建能读到密钥库文件，但口令无法解密、签名失败。

口令在 `build-profile.json5` 里是 DevEco 加密串，明文不入库；但证钥库与 `material/` 已足以完成签名，仓库需保持私有，不要公开或上传到公共托管平台。

Profile 为 debug 类型，绑定包名 `com.razor.h.v2.guess` 和已登记设备的 UDID，有效期至 2027-10-26。设备（含模拟器）不在登记列表时安装会被拒绝。新增开发机真机或更换模拟器后，需在 AppGallery Connect 增加对应 UDID 并重新生成 Profile 覆盖 `keystore/debug/debug.p7b`；若证书或口令一并更新，同步替换 `debug.cer` / `debug.p12` 与 `build-profile.json5` 中的加密串。Profile 到期前也按同样方式续期。

签名配置回归测试：

```shell
node --test tests/signing-config.test.cjs
```

测试会检查签名路径均为仓库相对路径且文件存在、`material/` 存在、Profile 为 debug 类型并与 `AppScope/app.json5` 的包名一致、尚未过期。

## 离线语音新手引导

- 首次打开教学时选择「边听边学」或「静音阅读」；不会进页即外放。开启后跟随步骤播报，支持暂停、继续和重听。
- 正位、错位、汇总分段解释；第三步含理解检查；三位练习按公开反馈给出短讲解，不读取隐藏答案作提示。
- 字幕始终保留；语音失败不阻塞教学。切页、开始下一次输入、退后台、音频中断或耳机断开时取消旧播报，不自动续播。
- 语音偏好独立保存。检测到系统读屏时停用旁白，避免重复播报。
- 文案唯一来源为 `entry/src/main/ets/model/TutorialNarration.ets`。19 个中文 WAV 随包提供，无需联网或麦克风权限。主线八段实测约 100.5 秒（不含操作等待），全部音频原始体积约 9.59 MiB。

音频校验（Windows PowerShell）：

```powershell
powershell -NoProfile -File tools/generate-tutorial-audio.ps1 -ValidateOnly
```

若本机执行策略禁止 PowerShell 脚本，不必更改系统策略；下面的 Node 测试也会检查音频资源完整性。重建配音及分发注意事项见 `entry/src/main/resources/rawfile/tutorial/zh-CN/README.md`。

设备外逻辑测试：

```shell
node --test tests/tutorial-voice.test.cjs
```

测试使用本机 DevEco 自带 TypeScript 转译真实播放器源码，并模拟媒体接口；不代替真机听音、音频焦点和无障碍验收。

### 设备验收清单

1. 冷启动教学不发声；选静音能走完所有步骤；开启语音后切换正位、错位、汇总时字幕及重点一致。
2. 暂停／继续／重听有效；快速连点切步没有叠音，退出教学后不再发声。
3. 小题答错时给补充说明，答对时解释数量含义，不强制答对才能下一步。
4. 练习输满三位自动提交；手动提交不会重复；下一次输入中止旧讲解；返回、后台取消待提交回调。
5. 来电、其他应用抢占音频、拔出耳机或蓝牙断连后停止讲解，回前台和恢复音频焦点后不自动外放。
6. 系统读屏启用时不同时播放旁白；大字体与小屏仍能滚动查看字幕及操作控件。
7. 飞行模式下可播放；音量使用系统媒体音量；媒体初始化失败时仍可阅读和完成教学。
