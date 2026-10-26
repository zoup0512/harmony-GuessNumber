# 当前模型生图 · Current Model Image

ZCode 本地插件，提供 MCP 工具与配套 Skill。让当前会话模型通过 OpenAI Responses 的 `image_generation` 工具生成图片，自动解码、验证并保存 PNG，无需每次编写 Python，也不再扫描会话日志恢复图片。

版本：`0.1.0`。需要 Node.js 20 或更高版本；本机已有可用 Node，无第三方依赖、不需要 npm install。

## 模型与供应商

- **当前模型**：Skill 从当前会话上下文取得模型 ID，显式传给工具；例如本次创建时的 `gpt-6.1-sol`。插件没有读取 ZCode 模型下拉框的私有接口，不宣称能自动感知模型切换。
- **供应商**：默认使用已有的本地个人供应商 `NS-GPT`，从环境变量 `ZCODE_PERSONAL_PROVIDER_CONFIG_FILE` 指向的文件读取；未设置时读取 `~/.zcode/v2/provider_config.json`。
- 仅支持 `openai-responses` 连接类型。插件调用 `/responses`，不会把当前模型发到 `/images/generations`，不会切换到 `gpt-image-*` 或其他供应商。
- 密钥只在运行时读取，不写入插件、不返回模型、不输出到日志。不要将含密钥的本地配置复制进插件。

默认文件无需修改。可在 MCP 进程环境中覆盖下列选项（修改后需重启相应 MCP 服务或新建任务）：

| 环境变量 | 用途 |
| --- | --- |
| `CURRENT_IMAGE_PROVIDER_ID` | 精确选择已有 ZCode provider ID，优先于名称 |
| `CURRENT_IMAGE_PROVIDER_NAME` | 按名称选择供应商，默认 NS-GPT |
| `CURRENT_IMAGE_API_KEY` 和 `CURRENT_IMAGE_BASE_URL` | 同时设置时直接使用这组连接；仅设其中一个会报错。不要写进版本库 |
| `ZCODE_PERSONAL_PROVIDER_CONFIG_FILE` | 现有 ZCode 个人供应商配置文件位置 |

供应商选择和聊天模型选择是独立的。如果切换了聊天供应商，应同步设置插件供应商；模型不在所选供应商的登记列表时会拒绝调用，不静默回退。若凭据存放于非明文配置的系统凭据库，此版本不读取它，应通过环境变量注入凭据。

## 工具

### `check_connection`

必填 `model`。校验本地配置，访问供应商 `/models` 核对连接与模型存在情况；不生图。模型列表存在不保证该模型一定支持图像工具，最终以生成响应为准。

### `generate_image`

必填 `prompt`、`model`、`output_path`，可选 `width`、`height`、`quality`。

- `output_path` 必须是绝对 `.png` 路径。父目录自动创建。
- 默认导出 1024×1024，可用范围为每边 256–2048 像素。
- API 返回的原图分辨率可能不是请求值；本地处理为精确目标尺寸。宽高比不同时中心裁切，提示词应让主体处于中央安全区。
- 一次调用只发一次生成请求，不自动重试。网络超时或取消不代表远端未执行，可能已经计费。
- 已有同尺寸、有效 PNG 会返回 `reused: true`，不再次付费请求，也不覆盖。这并不代表旧图符合新的提示词。需要新图时使用新文件名。
- 使用目标文件锁避免同路径并发生成。遗留锁应先确认没有进行中的请求，再由用户处理，不自动解除。
- 仅接受并验证 Base64 PNG；支持 8 位非交错 RGB/RGBA。其他图片格式明确报错，不假装保存成功。
- 不支持参考图编辑，不自动替换项目资源。生成之后由助手在用户授权范围内接入应用。

返回本地绝对路径、最终尺寸、原图尺寸、使用的模型和供应商等元数据；不返回大段 Base64。助手应直接预览返回文件，而不是再生成一次。

## 安装与使用

1. 在 ZCode「插件市场 → 添加 → 添加插件市场」粘贴市场根目录（**不是插件子目录**）：
   `D:\workspace\My\harmony\GuessNumber_HarmonyOS\GuessNumber\plugins`
2. 在「个人 → dev-guessnumber-2211257a」找到「当前模型生图」，安装 `0.1.0`。完整插件 ID 为 `current-model-image@dev-guessnumber-2211257a`。市场清单位于上一级 `marketplace.json`。
3. 在「设置 → 插件」确认启用及 MCP 连接。若提示找不到 `node`，在本地 MCP 启动设置中使用本机 Node 可执行文件的绝对路径；本机位置为 `C:\Program Files\nodejs\node.exe`，不要为此另装 Python。
4. **新建任务**，在输入框的插件/技能选择器中选中本插件的 `generate-image` 技能。
5. 发送：

   > 使用当前模型，生成深靛蓝背景、暖金密码格和薄荷绿对勾的应用图标，保存为 generated-images/icon-demo.png，精确尺寸 1024×1024，并在对话中预览。

预期：先检查当前模型连接，随后只发一次生图请求，在工作区保存可打开的 PNG，并返回图片预览与下载链接。插件源目录和已安装副本不同；编辑源文件后需提高版本号、刷新该市场并手动更新插件，不会自动热更新。

## 开发验证

在已具备 Node 的开发环境执行：

```sh
node --test tests/*.test.mjs
node scripts/smoke.mjs
```

真实端到端测试会产生一次生图请求，需明确提供测试模型与一个尚不存在的绝对输出路径：

```powershell
$env:CURRENT_IMAGE_SMOKE_MODEL = 'gpt-6.1-sol'
$env:CURRENT_IMAGE_SMOKE_OUTPUT = 'C:\Users\vyron\.codex\recovered_images\plugin-smoke-new.png'
node scripts/smoke.mjs --live
```

该测试通过真正的 stdio MCP 协议执行检查、生图与同路径复用，不需要临时脚本。测试模型仅用于开发测试，不是运行时默认模型。

## 本机验证结果（2026-10-26）

- 12 项自动测试全部通过：MCP 握手与工具调用、JSON/SSE 图片返回、PNG 校验与缩放、文件复用、并发锁、取消、响应上限、配置与凭据脱敏等。
- 真实 stdio MCP 测试通过：NS-GPT / `gpt-6.1-sol`，只发一次生图请求，1254×1254 原图导出 1024×1024，生成结果已打开确认可读；同路径再次调用返回 `reused: true`。
- 真实测试文件：`C:\Users\vyron\.codex\recovered_images\current-model-image-plugin-smoke-20261026.png`，不包含在插件发布内容中。
- 插件 manifest、MCP 引用文件和 Skill 路径的本地完整性检查通过；本机没有可直接使用的全局 `zcode` CLI，因此没有声称通过 `zcode plugins validate` 的宿主 schema 校验。
- 市场仍待手动添加、插件仍待手动安装；安装后新任务中的 Skill 触发和 UI 预览仍待验。

## 安全与隐私

提示词会发送给所选供应商；不自动上传本地源码、图片或会话记录。插件本身不调用 ZCode 内置的 `image_gen.imagegen`，而是使用所选模型的 Responses 图像工具。HTTP 错误不回传完整供应商响应、Authorization 或 Base64。失败应先看脱敏原因，不盲目再次付费生成。
