# OneSwitch Implementation Plan

**Goal:** 可运行的 macOS 菜单栏常亮工具。
**Architecture:** Vue 显示、Tauri 通信、Rust 管理状态和定时、IOKit 执行电源断言。
**Tech Stack:** Tauri 2、Vue 3、TypeScript、Rust。
**Spec:** ../specs/2026-09-16-oneswitch.md

## 约束
中文 UI，macOS 13+，不提交 Git。当前会话直接执行。

## 步骤
- [x] 创建骨架，写电源服务测试：开启失败不能进入开启状态、关闭失败保留状态、重复开启不泄漏、到期关闭、非法时长拒绝。
- [x] 实现 power.rs 原生 API 与 keep_awake.rs 服务；运行 cargo test。
- [x] 实现 desktop.rs 托盘/面板、lib.rs 命令/后台时钟/退出处理。
- [x] 实现 Vue 面板、状态同步、时长选择、登录启动和错误反馈。
- [x] 运行前端类型检查和构建、cargo fmt、clippy、单元测试、原生电源断言集成测试。
- [x] 打包 .app，补充 README 启动路径与人工验收范围。
