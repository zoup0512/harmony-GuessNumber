# 数字解密（Guess Number / 1A2B）— HarmonyOS

经典 1A2B 猜数字益智游戏的鸿蒙原生实现（ArkTS / Stage 模型）。

- bundleName: com.razor.h.v2.guess
- SDK: 6.0.2(22)
- 功能：三档难度、定制防错键盘、猜测历史、限时计时、单次提示、战绩持久化

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
