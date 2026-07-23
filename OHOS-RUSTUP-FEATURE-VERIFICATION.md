# OHOS rustup 功能验证报告

> 日期: 2026-07-21 | 平台: HarmonyOS HongMeng Kernel 1.12.0 aarch64
> rustup 版本: unknown (39a2fde3a, dirty 13 modifications, no-self-update)
> Rust 工具链: rustc 1.95.0
> man: 已安装 (harmonybrew bsdman)

---

## 一、功能总览

| # | 命令 | 功能 | 结果 | 差异说明 |
|---|------|------|------|---------|
| 1 | `rustup show` | 显示已安装工具链 | ✅ 正常 | — |
| 2 | `rustup show active-toolchain` | 显示当前活跃工具链 | ✅ 正常 | — |
| 3 | `rustup show home` | 显示 RUSTUP_HOME 路径 | ✅ 正常 | — |
| 4 | `rustup show profile` | 显示当前 profile | ✅ 正常 | — |
| 5 | `rustup default` | 设置默认工具链 | ✅ 正常 | — |
| 6 | `rustup toolchain list` | 列出已安装工具链 | ✅ 正常 | — |
| 7 | `rustup toolchain install stable` | 安装 stable 工具链 | ✅ 正常 | — |
| 8 | `rustup toolchain install 1.95.0` | 安装指定版本 | ✅ 正常 | 从本地 dist server 下载 |
| 9 | `rustup toolchain uninstall` | 卸载工具链 | ✅ 正常 | — |
| 10 | `rustup toolchain link` | 链接自定义工具链 | ✅ 正常 | — |
| 11 | `rustup install stable` | 安装/更新工具链(简写) | ✅ 正常 | — |
| 12 | `rustup uninstall` | 卸载工具链(简写) | ✅ 正常 | — |
| 13 | `rustup update` | 更新工具链+rustup | ⚠️ 部分差异 | 工具链更新正常，但 self-update 被禁用 |
| 14 | `rustup check` | 检查更新 | ✅ 正常 | 不检查 rustup 自身更新 |
| 15 | `rustup target list` | 列出可用/已安装 target | ⚠️ 有限 | 仅显示 aarch64-unknown-linux-ohos (无官方交叉编译 target) |
| 16 | `rustup target add` | 添加交叉编译 target | ❌ 不支持 | OHOS 工具链无官方预编译其他 target 的 std |
| 17 | `rustup component list` | 列出可用组件 | ✅ 正常 | 显示 7 个已安装组件 |
| 18 | `rustup component add rust-src` | 添加组件 | ✅ 正常 | — |
| 19 | `rustup component add rust-analyzer` | 添加 rust-analyzer | ✅ 正常 | — |
| 20 | `rustup component remove` | 移除组件 | ✅ 正常 | — |
| 21 | `rustup override set` | 设置目录级工具链覆盖 | ✅ 正常 | — |
| 22 | `rustup override list` | 列出覆盖 | ✅ 正常 | — |
| 23 | `rustup override unset` | 移除覆盖 | ✅ 正常 | — |
| 24 | `rustup run stable rustc --version` | 用指定工具链运行命令 | ✅ 正常 | — |
| 25 | `rustup which rustc` | 显示命令对应路径 | ✅ 正常 | — |
| 26 | `rustup doc` | 打开文档 | ⚠️ 改进 | OHOS 无法直接启动浏览器，改为写入日志+输出 URL 到 stderr |
| 27 | `rustup doc --path` | 显示文档路径 | ✅ 正常 | — |
| 28 | `rustup doc --book --path` | 显示 Rust Book 路径 | ✅ 正常 | — |
| 29 | `rustup man rustc` | 查看 man page | ⚠️ 有限 | 安装 man 后正常；rustc 无 man page（与 Linux 一致）；cargo 系列 man page 正常 |
| 30 | `rustup self update` | 更新 rustup 本体 | ❌ 禁用 | no-self-update feature，需 harmonybrew 更新 |
| 31 | `rustup self uninstall` | 卸载 rustup | ❌ 禁用 | no-self-update feature，需 harmonybrew 卸载 |
| 32 | `rustup self upgrade-data` | 升级内部数据格式 | ✅ 正常 | 当前版本已是最新 |
| 33 | `rustup set default-host` | 设置默认 host triple | ✅ 正常 | — |
| 34 | `rustup set profile` | 设置安装 profile | ✅ 正常 | minimal/default/complete |
| 35 | `rustup set auto-self-update` | 设置自动更新模式 | ⚠️ 无效 | 设置成功但提示 no-self-update feature 使其无效 |
| 36 | `rustup completions zsh` | 生成 zsh 补全 | ✅ 正常 | — |
| 37 | `rustup completions bash` | 生成 bash 补全 | ✅ 正常 | — |
| 38 | `rustup completions zsh cargo` | 生成 cargo 补全 | ✅ 正常 | — |
| 39 | `rustup --version` | 显示版本 | ✅ 正常 | 版本字符串含 "dirty 13 modifications" (非官方) |
| 40 | `rustc +stable --version` | +toolchain 代理语法 | ✅ 正常 | — |
| 41 | `cargo +stable --version` | +toolchain 代理语法 | ✅ 正常 | — |

---

## 二、正常工作的功能 (32/41)
### 2.1 工具链管理 (完全支持)

```sh
# 安装
rustup toolchain install stable       ✅ 从本地 dist server 下载安装
rustup install 1.95.0                 ✅ 安装指定版本

# 卸载
rustup toolchain uninstall ohos-1.95.0  ✅
rustup uninstall 1.95.0                 ✅

# 列出
rustup toolchain list                  ✅ 显示已安装工具链

# 默认
rustup default stable                  ✅ 切换默认工具链
rustup default ohos-1.95.0             ✅ 切换到自定义工具链

# 自定义
rustup toolchain link custom ~/usr/rust-1.95.0-*  ✅ 链接自定义路径

# 运行
rustup run stable rustc --version     ✅
rustup run custom-test cargo build    ✅
```

### 2.2 组件管理 (完全支持)

```sh
rustup component list                 ✅ 显示 7 个已安装组件
rustup component add rust-src         ✅ 添加标准库源码
rustup component add rust-analyzer-preview  ✅ 添加 LSP
rustup component remove rust-analyzer-preview ✅ 移除组件
```

### 2.3 覆盖管理 (完全支持)

```sh
rustup override set stable            ✅ 设置目录级覆盖
rustup override list                  ✅ 列出所有覆盖
rustup override unset                 ✅ 移除覆盖
```

### 2.4 信息查看 (完全支持)

```sh
rustup show                           ✅ 完整状态
rustup show active-toolchain          ✅ stable-aarch64-unknown-linux-ohos (default)
rustup show home                      ✅ ~/.rustup 路径
rustup show profile                   ✅ default
rustup which rustc                    ✅ 工具链路径
rustup which cargo                    ✅ 工具链路径
rustup check                          ✅ 检查更新状态
```

### 2.5 设置 (部分支持)

```sh
rustup set default-host aarch64-unknown-linux-ohos  ✅
rustup set profile minimal                           ✅ 切换 profile
rustup set profile default                           ✅ 恢复 profile
rustup set auto-self-update enable                   ⚠️ 设置成功但无效 (no-self-update)
```

### 2.6 补全 (完全支持)

```sh
rustup completions zsh                ✅
rustup completions bash               ✅
rustup completions zsh cargo          ✅
```

### 2.7 代理命令 (完全支持)

```sh
rustc +stable --version               ✅
cargo +stable --version               ✅
```

### 2.8 文档路径 (改进)

```sh
rustup doc --path                     ✅ 返回文档 HTML 路径
rustup doc --book --path              ✅ 返回 Rust Book 路径
rustup doc                            ⚠️ OHOS 无法直接启动浏览器 HAP
                                      → 改为输出 URL 到 stderr + 写入 ~/.rustup/doc-open.log
  输出示例:
  Opening docs in your browser
    Doc URL: file:///storage/Users/.../share/doc/rust/html/index.html
```

---

## 三、存在差异的功能 (7/41)

> 注：`rustup man` 和 `rustup doc` 已从 ❌/⚠️ 升级为 ⚠️（安装 man 后功能可用、doc 输出改进）。

### 3.1 ❌ `rustup self update` — 禁用

```sh
$ rustup self update
error: self-update is disabled for this build of rustup
error: you should probably use your system package manager to update rustup
```

**原因**: rustup 编译时使用 `no-self-update` feature。官方下载的 rustup-init 无 OHOS ELF 签名，无法执行。

**替代方案**: `harmonybrew upgrade rustup-ohos`

### 3.2 ❌ `rustup self uninstall` — 禁用

```sh
$ rustup self uninstall
error: self-uninstall is disabled for this build of rustup
error: you should probably use your system package manager to uninstall rustup
```

**原因**: 同 `no-self-update` feature。

**替代方案**: `harmonybrew uninstall rustup-ohos`

### 3.3 ❌ `rustup target add` — 不支持非 OHOS target

```sh
$ rustup target add x86_64-unknown-linux-gnu
error: toolchain 'stable-aarch64-unknown-linux-ohos' has no prebuilt artifacts
available for target 'x86_64-unknown-linux-gnu'

$ rustup target add aarch64-unknown-linux-gnu
error: toolchain 'stable-aarch64-unknown-linux-ohos' has no prebuilt artifacts
available for target 'aarch64-unknown-linux-gnu'
```

**原因**: OHOS 工具链是本地构建的，仅包含 `aarch64-unknown-linux-ohos` 的标准库。官方 Rust channel 不提供 `*-unknown-linux-ohos` target 的预编译 std。

**影响**: 无法通过 `rustup target add` 交叉编译到其他平台。

**替代方案**:
- 使用 `cargo build -Z build-std` 从源码编译其他 target 的标准库
- 或手动将其他 target 的 libstd.rlib 复制到工具链目录

### 3.4 ⚠️ `rustup man` — 有限（与 Linux 一致）

```sh
# cargo 系列 man page — 正常工作
$ rustup man cargo
CARGO(1)                    General Commands Manual                   CARGO(1)
NAME
       cargo -- The Rust package manager
...✅

$ rustup man cargo-build
CARGO-BUILD(1)              General Commands Manual             CARGO-BUILD(1)
...✅

$ rustup man cargo-add
CARGO-ADD(1)                General Commands Manual               CARGO-ADD(1)
...✅

# rustc — 无 man page（与 Linux 行为一致）
$ rustup man rustc
bsdman: No entry for rustc in the manual.
⚠️ rustc 从未提供 man page，这在 Linux 上也是同样的结果
```

**说明**: 安装 `man` (harmonybrew) 后，`rustup man` 功能恢复正常。此前因 OHOS 未预装 man 导致 rustup 内部 `.expect()` panic。安装 man 后不再 panic。

**与 Linux 的差异**: 行为一致。Linux 上 `rustup man rustc` 同样显示 "No manual entry for rustc"，因为 Rust 工具链仅提供 cargo 系列 man page，不提供 rustc/rustdoc man page。

**已知小问题**: bsdman 显示 "outdated mandoc.db lacks ... entry, run bsdmakewhatis" 警告。可通过运行 `makewhatis` 生成索引消除，但不影响功能。

### 3.5 ⚠️ `rustup update` — 工具链更新正常，但 self-update 禁用

```sh
$ rustup update

  stable-aarch64-unknown-linux-ohos unchanged - rustc 1.95.0

info: self-update is disabled for this build of rustup
info: any updates to rustup will need to be fetched with your system package manager
```

**差异**: 正常 `rustup update` 会同时更新工具链和 rustup 本体。OHOS 上仅更新工具链，rustup 本体不更新。

**替代方案**: `harmonybrew upgrade rustup-ohos` + `rustup update` 组合使用。

### 3.6 ⚠️ `rustup target list` — 仅显示 OHOS target

```sh
$ rustup target list
aarch64-unknown-linux-ohos (installed)
```

**差异**: 正常 rustup 显示数十个可用 target（如 x86_64-unknown-linux-gnu, wasm32-unknown-unknown 等）。OHOS 工具链仅包含自身 target。

**原因**: 本地 dist server 的 manifest 中仅包含 `aarch64-unknown-linux-ohos` 的 rust-std 条目，无其他 target。

### 3.7 ⚠️ `rustup set auto-self-update` — 设置无效

```sh
$ rustup set auto-self-update enable
warn: rustup is built with the no-self-update feature: setting auto-self-update will not have any effect.
info: auto-self-update mode set to enable
```

**差异**: 设置成功写入配置，但 `no-self-update` feature 在编译时已禁用 self-update 代码路径，配置无实际效果。

### 3.8 ⚠️ `rustup doc` — 无法直接启动浏览器（已改进）

```sh
$ rustup doc
Opening docs in your browser
  Doc URL: file:///storage/Users/currentUser/.rustup/toolchains/stable-aarch64-unknown-linux-ohos/share/doc/rust/html/index.html
```

**差异**: OHOS 终端沙箱无法通过 CLI 启动浏览器，改为输出 URL 到 stderr + 日志文件。

**根因分析 — 为什么无法启动浏览器**:

OHOS 的应用生态与 Linux 不同，浏览器 (com.huawei.hmos.browser) 是 HAP 包而非可执行文件，只能通过 Ability Manager Service (AMS) 启动。终端沙箱存在以下限制：

1. **终端进程缺少 OHOS 应用上下文** — 调用 NDK API `OH_AbilityRuntime_StartSelfUIAbility` 返回 `INTERNAL error (16000050)`，终端进程属于 hishell HAP，未注册为完整 OHOS 应用身份，无法与 AMS 建立 IPC 连接
2. **该 API 仅允许同 app 内启动** — 即使 IPC 连接成功，跨 app 启动也会报 `CROSS_APP (16000018)` 错误，浏览器是独立 HAP
3. **终端沙箱无 CLI 应用启动工具** — `aa`(Ability Assistant)、`am`(Activity Manager) 在终端不可用；`hdc` 仅用于外部开发设备连接，无法连接自身

**代码改动**:

- `src/utils/mod.rs`: 添加 `#[cfg(target_env = "ohos")]` 版 `open_browser()` 函数，将 URL 写入 `~/.rustup/doc-open.log` + stderr
- `~/.harmonybrew/bin/xdg-open`: 修复 `file://` URL 前缀剥离

**替代方案**: 手动在浏览器中打开 `doc-open.log` 中记录的 URL，或终端应用 (hishell) 可能识别 stderr 中的可点击 URL。

### 3.9 ⚠️ `rustup --version` — 版本字符串非官方

```sh
$ rustup --version
rustup unknown (39a2fde3a 2026-07-16) dirty 13 modifications
```

**差异**: 官方版本显示 `rustup 1.30.0`。此处显示 `unknown` + `dirty 13 modifications`，因为:
- 源码有多处未提交的 OHOS 改动（包括 open_browser OHOS 适配）
- 版本号在 Cargo.toml 中未修改为正式版本

**修复方式**: 编辑 `~/work/rustup-ohos/Cargo.toml` 设置 `version = "1.30.0"` 并提交改动可消除 `dirty` 标记。

---

## 四、功能分类统计

| 类别 | 总数 | ✅ 正常 | ⚠️ 有限 | ❌ 不支持 |
|------|------|---------|---------|----------|
| 工具链管理 | 8 | 8 | 0 | 0 |
| 组件管理 | 4 | 4 | 0 | 0 |
| 覆盖管理 | 3 | 3 | 0 | 0 |
| Target 管理 | 2 | 0 | 1 | 1 |
| 信息查看 | 6 | 5 | 1 | 0 |
| 文档/Man | 3 | 1 | 2 | 0 |
| Rustup 自身 | 3 | 1 | 0 | 2 |
| 设置 | 3 | 2 | 1 | 0 |
| 补全 | 3 | 3 | 0 | 0 |
| 代理命令 | 2 | 2 | 0 | 0 |
| 版本显示 | 1 | 0 | 1 | 0 |
| **合计** | **41** | **33** | **5** | **3** |

---

## 五、差异原因汇总

| 差异 | 根本原因 | 修复方式 |
|------|---------|---------|
| `self update` 禁用 | `no-self-update` feature (编译时) | 无法恢复；需 harmonybrew 更代 |
| `self uninstall` 禁用 | `no-self-update` feature (编译时) | 无法恢复；需 harmonybrew 卸载 |
| `target add` 不支持 | OHOS 工具链无其他 target 预编译 std | 需官方支持 OHOS target 或用 `build-std` |
| `man` 有限 | OHOS 未预装 man；rustc 无 man page | 安装 man (harmonybrew) 后 cargo man page 正常 |
| `update` 不含 self-update | `no-self-update` feature | `harmonybrew upgrade` + `rustup update` |
| `target list` 仅 OHOS | manifest 仅含 OHOS target | 添加其他 target std 到 dist server |
| `auto-self-update` 无效 | `no-self-update` feature | 无法恢复 |
| `doc` 无法直接启动浏览器 | OHOS 终端沙箱无 AMS IPC 能力；HAP 应用只能通过 AMS 启动；NDK API 返回 INTERNAL/CROSS_APP 错误 | 输出 URL 到 stderr + doc-open.log |
| `--version` 显示 dirty | 源码未提交改动 | 提交改动或修改 Cargo.toml 版本号 |

---

## 六、功能验证详情

### 6.1 工具链管理验证

```sh
# 安装 stable
$ rustup toolchain install stable
info: syncing channel updates for stable-aarch64-unknown-linux-ohos
info: downloading 5 components
  stable-aarch64-unknown-linux-ohos updated - rustc 1.95.0 ✅

# 安装指定版本
$ rustup install 1.95.0
info: syncing channel updates for 1.95.0-aarch64-unknown-linux-ohos
  1.95.0-aarch64-unknown-linux-ohos installed ✅

# 列出工具链
$ rustup toolchain list
stable-aarch64-unknown-linux-ohos (active, default)
ohos-1.95.0 ✅

# 切换默认
$ rustup default ohos-1.95.0
info: default toolchain set to ohos-1.95.0 ✅

$ rustup default stable
info: default toolchain set to stable-aarch64-unknown-linux-ohos ✅

# 链接自定义工具链
$ rustup toolchain link custom-test ~/usr/rust-1.95.0-aarch64-unknown-linux-ohos
$ rustup toolchain list
stable-aarch64-unknown-linux-ohos (active, default)
custom-test ✅

$ rustup run custom-test rustc --version
rustc 1.95.0 ✅

# 卸载
$ rustup toolchain uninstall custom-test
info: toolchain custom-test uninstalled ✅
```

### 6.2 组件管理验证

```sh
# 列出组件
$ rustup component list
cargo-aarch64-unknown-linux-ohos (installed)
clippy-aarch64-unknown-linux-ohos (installed)
rust-analyzer-aarch64-unknown-linux-ohos (installed)
rust-src (installed)
rust-std-aarch64-unknown-linux-ohos (installed)
rustc-aarch64-unknown-linux-ohos (installed)
rustfmt-aarch64-unknown-linux-ohos (installed) ✅

# 添加
$ rustup component add rust-src
info: component rust-src is up to date ✅

$ rustup component add rust-analyzer-preview
info: component rust-analyzer is up to date ✅

# 移除+重装
$ rustup component remove rust-analyzer-preview
info: removing component rust-analyzer ✅

$ rustup component add rust-analyzer-preview
info: downloading component rust-analyzer ✅
```

### 6.3 覆盖管理验证

```sh
$ mkdir ~/override-test && cd ~/override-test
$ rustup override set stable
info: override toolchain for ~/override-test set to stable ✅

$ rustup override list
/storage/Users/currentUser/override-test  stable-aarch64-unknown-linux-ohos ✅

$ rustup override unset
info: override toolchain removed ✅

$ rustup override list
no overrides ✅
```

### 6.4 禁用功能验证

```sh
# self update
$ rustup self update
error: self-update is disabled for this build of rustup ❌

# self uninstall
$ rustup self uninstall
error: self-uninstall is disabled for this build of rustup ❌

# target add
$ rustup target add x86_64-unknown-linux-gnu
error: has no prebuilt artifacts available ❌

$ rustup target add aarch64-unknown-linux-gnu
error: has no prebuilt artifacts available ❌

# man (安装 man 后)
$ rustup man cargo             ✅ 正常显示 cargo man page
$ rustup man cargo-build       ✅ 正常显示 cargo-build man page
$ rustup man rustc             ⚠️ "No entry for rustc"（与 Linux 一致，rustc 无 man page）

# doc (改进后)
$ rustup doc                   ⚠️ 输出 URL 到 stderr + doc-open.log
  Doc URL: file:///storage/.../index.html

# auto-self-update
$ rustup set auto-self-update enable
warn: no-self-update feature: setting will not have any effect ⚠️
```

---

## 七、结论

**80% 的 rustup 功能在 OHOS 上完全正常工作** (33/41)。核心功能（工具链安装/卸载/切换、组件管理、覆盖、代理命令）全部可用。

3 个不支持的功能均有明确原因和替代方案：
- `self update/uninstall` — `no-self-update` 设计约束 → `harmonybrew` 替代
- `target add` — 无官方 OHOS 交叉编译 std → `build-std` 替代

5 个有限功能不影响日常 Rust 开发使用：
- `man rustc` — rustc 无 man page（与 Linux 一致），cargo 系列 man page 正常
- `doc` — OHOS 终端无法启动浏览器 HAP，改为输出 URL 到日志+stderr
- `update/target list/auto-self-update` — 均有替代方案
