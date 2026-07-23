# OHOS rustup 适配 — 状态清单与后续计划

> 日期: 2026-07-17 | 平台: HarmonyOS HongMeng Kernel 1.12.0 aarch64

---

## 一、已完成事项

| # | 事项 | 说明 |
|---|------|------|
| 1 | 上游源码改动 — mod.rs | 5 个 OHOS TUPLE 常量 + gnu guard 更新 + HarmonyOS/OpenHarmony match arms |
| 2 | 上游源码改动 — rustup-init.sh | `HarmonyOS | OpenHarmony` case 分支 |
| 3 | 本地编译 rustup | no-self-update + native-tls，签名可执行 |
| 4 | rustup host detection 验证 | `rustup show` → `aarch64-unknown-linux-ohos` |
| 5 | 组件打包脚本 | build-ohos-dist.sh 函数式 7 组件 setup + ELF 签名 + manifest.in 生成 |
| 6 | 8 组 aarch64 tarball | rustc/cargo/rust-std/rustfmt/clippy/rust-analyzer/rust-src/rust (合并包) |
| 7 | Manifest v2 | channel-rust-stable.toml 含 8 个 pkg 条目 + profiles + renames |
| 8 | Manifest SHA-256 | .sha256 文件与 rustup 验证逻辑匹配 |
| 9 | Rust 分发服务器 | tiny_http 静态文件服务器，127.0.0.1:8080 |
| 10 | 启停脚本 | start-dist-server.sh (start/stop/status + PID 管理) |
| 11 | 端到端安装 | `rustup toolchain install stable` 下载 5 components 成功 |
| 12 | 16 项集成测试 | default/minimal profile, clippy, fmt, rust-analyzer, 幂等安装, error handling 等 |
| 13 | 环境变量持久化 | ~/.zshrc 已写入 RUSTUP_DIST_SERVER/RUST_MIN_STACK/LD_LIBRARY_PATH 等 |
| 14 | 两个上游 patch | 0001 (mod.rs, 78行) + 0002 (rustup-init.sh, 13行) |
| 15 | 综合技术文档 | OHOS-RUSTUP-GUIDE.md v1.1 |
| 16 | Formula SHA256/URL/caveats 修复 | P0 三项全部修复：本地 tarball URL + 真实 SHA256 + rustup install caveats |
| 17 | build-ohos-dist.sh 参数化 | CLI args: -v/-t/-T/-d/-s + toolchain dir 验证 |
| 18 | Formula 架构参数化 | ohos_triple helper (Hardware::CPU.arch → triple) |
| 19 | Start script 架构参数化 | uname -m triple detection + TLS env passthrough |
| 20 | Manifest 生成器 | generate-manifest.sh (多架构自动发现 + hash 自动读取) |
| 21 | TLS 支持 | tiny_http ssl-openssl + --tls-cert/--tls-key/--bind + 自签名证书脚本 |
| 22 | x86_64 文档 | OHOS-RUSTUP-GUIDE.md 八/九章节 (4 步集成流程 + TLS 使用说明) |
| 23 | rustup-init 安装闭环 | 签名 rustup-init + dist/archive 路径部署 + release-stable.toml |
| 24 | rustup-init.sh 托管 | 注入 RUSTUP_UPDATE_ROOT/RUSTUP_DIST_SERVER 的 OHOS 安装脚本 |
| 25 | RUSTUP_UPDATE_ROOT 环境 | ~/.zshrc + formula 均已添加 |
| 26 | curl | sh 一键安装验证 | 所有 HTTP 端点测试通过 |

---

## 二、未完成事项

| # | 事项 | 问题 | 优先级 |
|---|------|------|--------|
| 1 | ~~Harmonybrew formula — SHA256 占位符~~ | ✅ 已修复（P4-1） | — |
| 2 | ~~Harmonybrew formula — 源码 URL~~ | ✅ 已修复（P4-1） | — |
| 3 | ~~Harmonybrew formula — caveats 过时~~ | ✅ 已修复（P4-1） | — |
| 4 | ~~Harmonybrew formula — aarch64 硬编码~~ | ✅ 已修复（P5-1 ohos_triple） | — |
| 5 | 多架构 tarball | 仅 aarch64；x86_64 等需预编译工具链（基础设施就绪） | P1 |
| 6 | ~~多架构 manifest~~ | ✅ generate-manifest.sh 自动生成 | — |
| 7 | ~~TLS/HTTPS~~ | ✅ tiny_http ssl + --tls-cert/--tls-key | — |
| 8 | ~~rustup-init 安装闭环~~ | ✅ 签名 + 部署 + curl|sh 一键安装 | — |
| 9 | 上游 PR 推送 | patch 已就绪，GitHub 访问受限无法推送 | P2 |
| 10 | ~~build-ohos-dist.sh 参数化~~ | ✅ CLI args: -v/-t/-T/-d/-s | — |
| 11 | ~~自动化版本更新~~ | ✅ generate-manifest.sh 自动发现 | — |

---

## 三、后续计划

### Phase 4 — 生产就绪 ✅ 已完成

1. ~~修复 Harmonybrew formula 三个硬伤~~ ✅
2. ~~build-ohos-dist.sh 参数化~~ ✅

### Phase 5 — 多架构 + 网络分发 ✅ 已完成

3. ~~Formula + start script 架构参数化~~ ✅ (ohos_triple + uname -m)
4. ~~Manifest 自动生成~~ ✅ (generate-manifest.sh, 多架构自动发现)
5. ~~TLS 支持~~ ✅ (tiny_http ssl + --tls-cert/--tls-key + 自签名证书)

### Phase 6 — 上游贡献（GitHub 解封后）

6. 推送 patch 到 rust-lang/rustup，提交 PR
7. OHOS 成为上游支持 target 后，移除本地分发服务器，直接用官方 channel

### Phase 7 — rustup-init 安装闭环 ✅ 已完成

8. ~~构建签名 rustup-init~~ ✅ (deploy-rustup-init.sh, .codesign 验证)
9. ~~设置 RUSTUP_UPDATE_ROOT~~ ✅ (http://127.0.0.1:8080/rustup)
10. ~~curl | sh 一键安装~~ ✅ (rustup-init.sh + 签名 binary 部署)

---

## 四、总结

核心功能（aarch64 上 `rustup install stable`）已完整可用。Phase 4-5-7 全部完成；`curl | sh` 一键安装可用；多架构 tarball 需等 x86_64 工具链就绪；TLS 已集成；上游 PR 等网络条件恢复。剩余：P6 上游 PR（暂不推送）。
