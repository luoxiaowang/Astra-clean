# OneSwitch

使用 Tauri 2 + Vue 3 + TypeScript + Rust 开发的 macOS 菜单栏常亮工具。支持 macOS 13 及以上，当前首版仅实现 macOS。

## 功能

- 启动时只显示菜单栏图标。左键在图标下方打开/收起原生悬浮面板，点击外部自动隐藏；右键打开菜单或退出。
- 屏幕常亮：保持屏幕亮起，阻止因闲置导致的系统睡眠。
- 永久、5 分钟、30 分钟、1 小时、2 小时、5 小时、8 小时；开启时切换时长会从当前时刻重新计时。
- 面板收起后 Rust 继续保活和计时；退出应用释放断言。
- 登录启动可选。每次应用启动默认关闭常亮，不恢复上次的保活会话。
- 单实例运行，重复打开会显示已有面板。
- 系统黑暗模式开关：切换 macOS 全局外观，面板同时自动跟随系统深浅色。
- 列表式菜单，展开选择亮屏时长；底部“设置”内可配置登录启动。

## 开发运行

前提：macOS 13+、Xcode Command Line Tools、Rust stable、Node.js 22.12+ 与 npm（推荐 Node LTS）。

```bash
cd ~/Desktop/code/OneSwitch
npm ci
npm run tauri dev
```

`npm run dev` 仅启动浏览器预览，不能操作系统常亮；预览会明确提示并禁用系统开关。

## 打包

```bash
npm run tauri build -- --bundles app
```

应用输出：`src-tauri/target/release/bundle/macos/OneSwitch.app`。

```bash
open src-tauri/target/release/bundle/macos/OneSwitch.app
```

正式使用建议把应用复制到 `/Applications` 后再开启登录启动，避免注册到易变的开发或构建路径。

生成 DMG：`npm run tauri build -- --bundles dmg`。本地构建不包含 Developer ID 签名和 Apple 公证；对外分发需要另外配置证书和公证。当前标识为 `com.oneswitch.desktop`，发布前应更换为自己管理的标识。

## 系统黑暗模式

首次点击黑暗模式开关，macOS 可能询问是否允许 OneSwitch 控制“系统事件”。允许后才能切换系统外观。若拒绝，可到“系统设置 → 隐私与安全性 → 自动化”重新允许，再重试。

本功能使用系统自带的 AppleScript 接口。授权等待最多 45 秒，失败时显示错误。面板外观跟随系统，从系统设置切换也会同步。退出应用不会撤销用户选择的系统外观。

## 保持活跃

独立开关，默认关闭。首次使用点击“授权辅助功能”，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `/Applications/OneSwitch.app`，返回后手动开启。若未列出应用，可用系统设置的“+”添加。重新构建后系统可能要求重新授权。

后台每秒检查输入闲置时间，闲置达到 45 秒后发送当前位置的鼠标移动事件，不点击、不输入文字，也不主动移动指针。鼠标键或修饰键按住时跳过。下一次检查验证系统闲置时间已重置；权限撤销或事件无效时停止并显示错误。发送与实际鼠标移动存在极短的竞争窗口，不能保证对所有应用完全无影响。

开启时同时保持亮屏，独立持有电源断言。因此单独关闭“保持亮屏”不会结束“保持活跃”的亮屏效果。关闭活跃或退出应用停止发送事件并释放自己的断言；重启不自动恢复。不会解锁电脑，也不保证合盖或手动睡眠时工作。

企微可能采用不同的在线判定机制；当前没有验证企微持续在线，请以实际客户端状态为准。系统电源活动声明已在本机验证不会重置输入闲置计时，因此本功能使用 CoreGraphics 输入事件。

## 验证

```bash
npm run build
cd src-tauri
cargo fmt --check
cargo test --lib
cargo clippy --all-targets -- -D warnings
# 在当前 Mac 短暂申请真实电源断言，然后检查释放结果
cargo test --lib native_assertion_is_visible_and_released -- --ignored
```

电源状态检查：`pmset -g assertions`，开启时应看到当前应用持有的 `PreventUserIdleDisplaySleep` 断言及 OneSwitch 名称。其他应用也可能持有断言，所以退出本应用不保证整台电脑立即睡眠。

人工验收：

1. 打开应用，开启常亮；检查菜单栏状态及 `pmset -g assertions`。
2. 选择不同时长；确认重新计时；收起、重新打开后状态一致。
3. 关闭常亮及退出应用；确认 OneSwitch 断言消失。
4. 在接电、电池、不同显示器及全屏空间下检查面板和常亮行为。
5. 安装到固定路径后开启登录启动，注销再登录，确认仅启动应用、不开启常亮。
6. 持续运行至定时结束，确认恢复系统设置；手动睡眠后再唤醒时，已到期的任务会在恢复执行后关闭。

详细验证结果见 [验证记录](docs/verification.md)。

## 代码结构

- `src/views/panel/`：Vue 中文面板、交互逻辑和状态类型。
- `src-tauri/src/keep_awake.rs`：电源断言状态机、期限校验和到期关闭。
- `src-tauri/src/power.rs`：IOKit FFI，显式管理创建/释放。
- `src-tauri/src/appearance.rs`：系统外观切换、授权错误和超时处理。
- `src-tauri/src/desktop.rs`：菜单栏图标、点击事件和原生菜单。
- `src-tauri/src/popover.rs`：挂在菜单栏图标上的原生 NSPopover、自动收起和内容尺寸管理。
- `src-tauri/src/lib.rs`：Tauri 命令、后台计时、单实例、登录启动和退出清理。
- `docs/superpowers/`：已确认设计和实施清单。

不修改系统全局休眠配置。保持亮屏不模拟输入；保持活跃会发送原位置鼠标活动事件。常亮不等于阻止合盖或手动睡眠，也不保证聊天软件持续在线。定时使用绝对结束时间，手动修改系统时钟可能改变剩余时长。悬浮面板使用原生 NSPopover，多屏及全屏空间行为仍需按目标设备验收。
