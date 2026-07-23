# 鸿蒙 (OHOS) rustup 适配 — 完整技术文档

> 版本: v1.2 | 日期: 2026-07-17 | 平台: HarmonyOS HongMeng Kernel 1.12.0 aarch64

---

## 一、项目概述

在鸿蒙 (HarmonyOS/OpenHarmony) 系统上实现 rustup 标准安装流程，使开发者可以通过 `rustup toolchain install stable` 直接安装和管理 Rust 工具链，而非依赖手动 `toolchain link`。

**核心挑战**: OHOS 在 Rust target triple 系统中使用 `target_os="linux" + target_env="ohos"`，但 `libc::uname()` 返回 `sysname="HarmonyOS"` 而非 `"Linux"`，导致 rustup 无法正确识别 host 平台。

**解决路径**: 分三个 Phase 逐步实现：

| Phase | 目标 | 状态 |
|-------|------|------|
| Phase 1 | 编译 rustup + toolchain link + Harmonybrew formula | 完成 |
| Phase 2 | 私有分发服务器 + `rustup install stable` 标准流程 | 完成 |
| Phase 3 | 上游 PR patch 准备 + 本地验证 | 完成 |
| Phase 4 | Formula 修复 + 脚本参数化 | 完成 |
| Phase 5 | 多架构支持 + TLS + manifest 自动生成 | 完成 |
| Phase 7 | rustup-init curl | sh 一键安装闭环 | 完成 |

---

## 二、代码构成与所有改动

### 2.1 上游源码改动（2 个文件）

#### 文件 1: `src/dist/mod.rs` — Rust 侧 host detection

**改动 A: 新增 OHOS TUPLE 常量** (line 715-725)

```rust
// OHOS (HarmonyOS) uses "ohos" as target_env, mapping to -ohos triples.
#[cfg(all(not(windows), target_env = "ohos"))]
const TUPLE_X86_64_UNKNOWN_LINUX: &str = "x86_64-unknown-linux-ohos";
#[cfg(all(not(windows), target_env = "ohos"))]
const TUPLE_AARCH64_UNKNOWN_LINUX: &str = "aarch64-unknown-linux-ohos";
#[cfg(all(not(windows), target_env = "ohos"))]
const TUPLE_LOONGARCH64_UNKNOWN_LINUX: &str = "loongarch64-unknown-linux-ohos";
#[cfg(all(not(windows), target_env = "ohos"))]
const TUPLE_POWERPC64_UNKNOWN_LINUX: &str = "powerpc64-unknown-linux-ohos";
#[cfg(all(not(windows), target_env = "ohos"))]
const TUPLE_POWERPC64LE_UNKNOWN_LINUX: &str = "powerpc64le-unknown-linux-ohos";
```

**改动 B: 更新 gnu cfg guards** (line 726, 730, 734, 738, 742)

原来 `#[cfg(all(not(windows), not(target_env = "musl")))]` → 现在增加 `not(target_env = "ohos")`:

```rust
#[cfg(all(not(windows), not(target_env = "musl"), not(target_env = "ohos")))]
const TUPLE_X86_64_UNKNOWN_LINUX: &str = "x86_64-unknown-linux-gnu";
// ... 同样应用于 AARCH64, LOONGARCH64, POWERPC64, POWERPC64LE
```

**改动 C: from_host() 新增 OHOS match block** (line 640-658)

```rust
// OHOS (HarmonyOS/OpenHarmony) uses target_os="linux" + target_env="ohos".
// uname -s returns "HarmonyOS" or "OpenHarmony" instead of "Linux".
#[cfg(target_env = "ohos")]
let host_tuple = match (sysname, machine) {
    (b"HarmonyOS" | b"OpenHarmony", b"aarch64") => Some(TUPLE_AARCH64_UNKNOWN_LINUX),
    (b"HarmonyOS" | b"OpenHarmony", b"x86_64") => Some(TUPLE_X86_64_UNKNOWN_LINUX),
    (b"HarmonyOS" | b"OpenHarmony", b"loongarch64") => Some(TUPLE_LOONGARCH64_UNKNOWN_LINUX),
    (b"HarmonyOS" | b"OpenHarmony", b"ppc64") => Some(TUPLE_POWERPC64_UNKNOWN_LINUX),
    (b"HarmonyOS" | b"OpenHarmony", b"ppc64le") => Some(TUPLE_POWERPC64LE_UNKNOWN_LINUX),
    (_, b"arm") => Some("arm-unknown-linux-ohos"),
    (_, b"armv7l") => Some("armv7-unknown-linux-ohos"),
    (_, b"armv8l") => Some("armv7-unknown-linux-ohos"),
    (_, b"aarch64") => Some(TUPLE_AARCH64_UNKNOWN_LINUX),
    (_, b"x86_64") => Some(TUPLE_X86_64_UNKNOWN_LINUX),
    (_, b"loongarch64") => Some(TUPLE_LOONGARCH64_UNKNOWN_LINUX),
    (_, b"ppc64") => Some(TUPLE_POWERPC64_UNKNOWN_LINUX),
    (_, b"ppc64le") => Some(TUPLE_POWERPC64LE_UNKNOWN_LINUX),
    _ => None,
};
```

**改动 D: 更新非 android cfg guard** (line 594)

```rust
// 原来:
#[cfg(not(target_os = "android"))]
// 现在:
#[cfg(all(not(target_os = "android"), not(target_env = "ohos")))]
```

> 原因: OHOS 编译时 `target_env = "ohos"`，如果同时存在 android block 和通用 Linux block 的 `let host_tuple`，会产生重复绑定。排除 ohos 后，只有 `#[cfg(target_env = "ohos")]` block 编译。

#### 文件 2: `rustup-init.sh` — Shell 侧平台检测

**改动**: `get_architecture()` 函数 OS case statement (line 452-454)

```sh
HarmonyOS | OpenHarmony)
    _ostype=unknown-linux-ohos
    ;;
```

> 原因: OHOS 上 `uname -s` 返回 "HarmonyOS" 或 "OpenHarmony"，不是 "Linux"。不加此分支，installer 会报 "unrecognized OS type"。

#### Patch 文件

已生成两个 patch 供上游 PR 使用:
- `~/work/rustup-ohos/0001-ohos-host-detection-mod-rs.patch` (78 lines)
- `~/work/rustup-ohos/0002-ohos-rustup-init-sh.patch` (13 lines)

---

### 2.2 本地构建脚本（2 个文件）

#### `~/work/rustup-ohos/scripts/build-ohos-dist.sh` — 组件打包 + 签名

将社区预编译 Rust 工具链拆分为 rust-installer v3 格式组件 tarball，签名所有 ELF binary，计算 SHA-256。

**关键设计**: 函数式组件 setup（而非 glob pattern 文件列表），每个组件有独立的 `setup_*()` 函数:

| 函数 | 组件 | 内容 |
|------|------|------|
| `setup_rustc` | rustc | bin/rustc, bin/rustdoc, rust-objcopy, **4 个 .so (librustc_driver 等)**, gdb/lldb scripts |
| `setup_cargo` | cargo | bin/cargo, **13 个 proc-macro .so**, libssl.so, libcrypto.so, man pages |
| `setup_rust_std` | rust-std | lib/rustlib/${TARGET}/lib/ 全部 .rlib/.rmeta/.so |
| `setup_rustfmt` | rustfmt-preview | bin/rustfmt, bin/cargo-fmt |
| `setup_clippy` | clippy-preview | bin/clippy-driver, bin/cargo-clippy |
| `setup_rust_analyzer` | rust-analyzer-preview | bin/rust-analyzer |
| `setup_rust_src` | rust-src | lib/rustlib/src/rust/library/ 全部源码 |

**签名流程**: `sign_elf()` 函数对每个 ELF binary 调用 `binary-sign-tool sign -selfSign 1`，签名后 `chmod +x` 恢复执行权限。

**manifest.in 生成**: 用 `find . -type f ! -name "manifest.in" | sed 's|^\./||'` 遍历实际文件，输出 `file:<path>` 格式。

**已知 bug 修复记录**:
- glob pattern 在 `[[ -e ]]` 不展开 → 改用函数式 setup
- `lib/lib${so}` 双重 lib 前缀 → 改为 `lib/${so}`
- manifest.in 裸路径 → 必须用 `file:path` 前缀
- 遗漏 .so 文件 → rustc 需要顶层 lib/*.so，cargo 需要 proc-macro .so

#### `~/work/rustup-ohos/scripts/ohos-toolchain-setup.sh` — Phase 1 toolchain link 脚本

用于通过 `rustup toolchain link` 管理本地预编译工具链（Phase 1 方案，Phase 2 后作为备用）。

---

### 2.3 分发服务器文件

#### `~/work/ohos-dist-server/` — Rust 分发服务器

| 文件 | 说明 |
|------|------|
| `src/main.rs` | tiny_http 静态文件服务器，监听 127.0.0.1:8080 |
| `Cargo.toml` | 依赖: tiny_http 0.12, ascii 1.1 |
| `start-dist-server.sh` | 启停脚本 (start/stop/status)，PID 管理 |
| `target/aarch64-unknown-linux-ohos/release/ohos-dist-server-signed` | 签名后的可执行二进制 |

> 替代了 Phase 2 MVP 中的 `python3 -m http.server`，提供原生 Rust 服务，更轻量更稳定。

#### `~/work/ohos-dist-server/dist/` — 全部分发产物

```
dist/
  channel-rust-stable.toml              ← Manifest v2 (105 lines)
  channel-rust-stable.toml.sha256       ← Manifest hash
  rust-1.95.0-aarch64-unknown-linux-ohos.tar.gz          ← 合并包
  rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz          ← 12 entries
  cargo-1.95.0-aarch64-unknown-linux-ohos.tar.gz          ← 59 entries
  rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz       ← 60 entries
  rustfmt-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz ← 2 entries
  clippy-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz ← 2 entries
  rust-analyzer-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz ← 1 entry
  rust-src-1.95.0-aarch64-unknown-linux-ohos.tar.gz       ← 9274 entries
  (每个 .tar.gz 都有对应的 .sha256 文件)
```

#### Manifest 结构 (`channel-rust-stable.toml`)

```toml
[pkg.rust]                              ← 合并包 (5 components + 2 extensions)
[pkg.rustc]                             ← 编译器 + driver .so
[pkg.cargo]                             ← cargo + proc-macro .so + SSL
[pkg.rust-std]                          ← 标准库 .rlib/.rmeta/.so
[pkg.rustfmt-preview]                   ← 格式化器
[pkg.clippy-preview]                    ← 代码检查器
[pkg.rust-analyzer-preview]             ← 语言服务器 (extension)
[pkg.rust-src]                          ← 源码 (extension, target="*")

[renames]                               ← rustfmt → rustfmt-preview 等
[profiles]                              ← minimal / default / complete
```

URL 使用 `https://static.rust-lang.org/dist/` 基址（rustup 运行时通过 `RUSTUP_DIST_SERVER` 替换为实际服务器地址）。

---

### 2.4 Harmonybrew Formula

#### `~/.harmonybrew/Homebrew/Library/Taps/zqz979/homebrew-ohos/Formula/rustup-ohos.rb`

从源码编译 rustup 的 Homebrew formula，包含:
- `--no-default-features --features "no-self-update,reqwest-native-tls"`
- `RUSTUP_OVERRIDE_BUILD_TUPLE` 环境变量
- 安装后创建 proxy symlinks (rustc, cargo 等 → rustup)
- Caveats 说明 self-update 已禁用

---

### 2.5 安装后的工具链结构

```
~/.rustup/toolchains/stable-aarch64-unknown-linux-ohos/
  bin/
    cargo            ← 通过 rustup proxy shim 运行
    cargo-clippy
    cargo-fmt
    clippy-driver
    rustc
    rustdoc
    rustfmt
  lib/
    librustc_driver-*.so          ← 编译器驱动 (来自 rustc 组件)
    librustc_macros-*.so          ← 编译器宏 (来自 rustc 组件)
    librustc_index_macros-*.so
    librustc_type_ir_macros-*.so
    libserde_derive-*.so          ← proc-macro 库 (来自 cargo 组件)
    libthiserror_impl-*.so
    ... (共 13 个 proc-macro .so)
    libssl.so                     ← OpenSSL (来自 cargo 组件)
    libcrypto.so
    rustlib/
      aarch64-unknown-linux-ohos/
        lib/
          libstd-*.so             ← 动态链接标准库 (来自 rust-std 组件)
          libstd-*.rlib           ← 静态标准库
          libcore-*.rlib
          ... (共 60 个 .rlib/.rmeta/.so)
      components
      rust-installer-version
      manifest-rustc-*
      manifest-cargo-*
      manifest-rust-std-*
      manifest-rustfmt-preview-*
      manifest-clippy-preview-*
  share/
    doc/cargo/
    man/man1/
    zsh/site-functions/
```

---

## 三、rustup 使用方式

### 3.1 环境准备

rustup 在 OHOS 上运行需要三个关键环境变量:

```sh
# 1. 动态库路径 — 包含 harmonybrew (liblzma 等) + toolchain lib
export LD_LIBRARY_PATH=~/.harmonybrew/lib:~/.harmonybrew/Homebrew/lib

# 2. 线程栈大小 — musl libc 默认 128KB，rustup 需要 8MB
export RUST_MIN_STACK=8388608

# 3. 分发服务器 — 替换官方服务器为私有服务器
export RUSTUP_DIST_SERVER=http://127.0.0.1:8080
```

建议将这三行加入 `~/.bashrc` 或 `/data/service/hnp/bin/bash` 的 profile 文件。

### 3.2 启动分发服务器

```sh
cd ~/work/ohos-dist-server
bash start-dist-server.sh start
```

> 服务器使用 Rust 编写的 `ohos-dist-server` 二进制（基于 tiny_http crate），监听 `127.0.0.1:8080`。
> 支持 `start|stop|status` 命令，PID 文件管理自动启停。
> 注意: 此服务器仅在本地使用。若需网络分发，需替换为支持 TLS 的服务器。

### 3.3 安装工具链

```sh
# 标准安装 (default profile: rustc + cargo + rust-std + rustfmt + clippy)
rustup toolchain install stable

# 设为默认
rustup default stable

# 验证
rustup show
# 输出: Default host: aarch64-unknown-linux-ohos
```

### 3.4 安装额外组件

```sh
# Rust 源码 (rust-analyzer "go to definition" 需要)
rustup component add rust-src

# 语言服务器
rustup component add rust-analyzer-preview

# 注意: rust-analyzer-preview 需要额外的 LD_LIBRARY_PATH 包含 toolchain lib
export LD_LIBRARY_PATH=~/.harmonybrew/lib:~/.rustup/toolchains/stable-aarch64-unknown-linux-ohos/lib:~/.harmonybrew/Homebrew/lib
rust-analyzer --version
# 输出: rust-analyzer 1.95.0
```

### 3.5 Profile 选择

```sh
# minimal: 仅 rustc + cargo + rust-std
rustup set profile minimal
rustup toolchain install stable

# default: 加上 rustfmt + clippy
rustup set profile default
rustup toolchain install stable

# complete: 加上 rust-analyzer + rust-src
rustup set profile complete
rustup toolchain install stable
```

### 3.6 日常使用

```sh
# 编译运行项目
cd ~/work/hello-ohos
cargo run
# 输出: Hello from HarmonyOS!

# 代码检查
cargo clippy

# 格式化
cargo fmt

# 查看所有工具
rustup show
```

### 3.7 工具链更新（新版本发布时）

```sh
# 1. 重建 tarballs（使用参数化脚本）
/data/service/hnp/bin/bash ~/work/rustup-ohos/scripts/build-ohos-dist.sh \
  -v <新版本号> -t <目标triple>

# 2. 自动生成 manifest（扫描 dist 目录）
/data/service/hnp/bin/bash ~/work/rustup-ohos/scripts/generate-manifest.sh \
  -v <新版本号> -d ~/work/ohos-dist-server/dist

# 3. 重启分发服务器
~/work/ohos-dist-server/start-dist-server.sh stop && \
~/work/ohos-dist-server/start-dist-server.sh start

# 4. 安装新版本
rustup toolchain install stable
```

---

## 四、关键约束与技术细节

### 4.1 ELF 签名

OHOS 要求所有可执行 ELF binary 必须包含 `.codesign` section。无签名 binary 无法执行 (exit 126)。

**两种签名方式**:
1. **预分发签名**: `build-ohos-dist.sh` 中 `sign_elf()` 对 tarball 内每个 ELF binary 用 `binary-sign-tool -selfSign 1` 签名
2. **编译时自动签名**: `ld.lld --code-sign` 在链接阶段自动添加签名 (cargo build 时自动触发)

**注意**: `binary-sign-tool` 签名后会移除 `+x` 权限，必须在签名后执行 `chmod +x`。

### 4.2 no-self-update

rustup 的自更新功能在 OHOS 上必须禁用，因为:
- 从官方服务器下载的 rustup binary 没有 OHOS 签名
- 无签名 binary 在 OHOS 上无法执行

编译时使用 `--no-default-features --features "no-self-update,reqwest-native-tls"`。

### 4.3 native-tls vs rustls

使用 `reqwest-native-tls` (基于 OpenSSL) 而非默认的 `reqwest-rustls`:
- `rustls-platform-verifier` 在 OHOS 上可能有兼容问题
- harmonybrew 提供 OpenSSL 3.6.3
- 编译时需设置 `OPENSSL_DIR` 等环境变量

### 4.4 RUST_MIN_STACK

OHOS 使用 musl libc，默认线程栈大小仅 128KB。rustup 的 reqwest/tokio 等异步运行时需要更大栈空间。设置 `RUST_MIN_STACK=8388608` (8MB) 是必须的。

### 4.5 LD_LIBRARY_PATH

rustup 和 rustc 等工具动态链接了以下库:
- `liblzma.so.5` — 来自 harmonybrew (xz 压缩)
- `librustc_driver-*.so` — 来自 toolchain lib/ (编译器驱动)
- `libssl.so` / `libcrypto.so` — 来自 toolchain lib/ (cargo HTTPS)

`LD_LIBRARY_PATH` 必须包含:
1. `~/.harmonybrew/lib` (运行 rustup 本体)
2. `~/.rustup/toolchains/stable-*/lib` (运行 rustc/cargo 等工具)
3. `~/.harmonybrew/Homebrew/lib` (备用)

### 4.6 target_env = "ohos"

OHOS 在 Rust triple 系统中的定位:
- `target_os = "linux"` (与标准 Linux 相同的内核 ABI)
- `target_env = "ohos"` (区别于 gnu/musl 的 C 库环境)
- triple 格式: `aarch64-unknown-linux-ohos`

这意味着:
- `libc::uname()` 返回 `sysname="HarmonyOS"` (非 "Linux")
- `cfg(target_env = "ohos")` 在编译时生效
- `cfg(target_os = "ohos")` **不存在** (OHOS 不是独立的 target_os)

---

## 五、文件清单总览

| 类别 | 文件 | 位置 |
|------|------|------|
| **上游改动** | src/dist/mod.rs | ~/work/rustup-ohos/src/dist/mod.rs |
| | rustup-init.sh | ~/work/rustup-ohos/rustup-init.sh |
| **Patch 文件** | 0001-ohos-host-detection-mod-rs.patch | ~/work/rustup-ohos/ |
| | 0002-ohos-rustup-init-sh.patch | ~/work/rustup-ohos/ |
| **构建脚本** | build-ohos-dist.sh (参数化 -v/-t/-T/-d/-s) | ~/work/rustup-ohos/scripts/ |
| | generate-manifest.sh (多架构自动发现) | ~/work/rustup-ohos/scripts/ |
| | deploy-rustup-init.sh (签名+部署+注入) | ~/work/rustup-ohos/scripts/ |
| | ohos-toolchain-setup.sh | ~/work/rustup-ohos/scripts/ |
| **分发服务器** | ohos-dist-server (HTTP+HTTPS, 参数化) | ~/work/ohos-dist-server/ |
| | start-dist-server.sh (架构自动检测+TLS) | ~/work/ohos-dist-server/ |
| | generate-self-signed-cert.sh | ~/work/ohos-dist-server/scripts/ |
| **分发产物** | channel-rust-stable.toml | ~/work/ohos-dist-server/dist/ |
| | 8 组 .tar.gz + .sha256 | ~/work/ohos-dist-server/dist/ |
| **Rustup 二进制** | rustup (signed) | ~/.cargo/bin/rustup |
| **工具链** | stable-aarch64-unknown-linux-ohos | ~/.rustup/toolchains/ |
| **Harmonybrew** | rustup-ohos.rb | ~/.harmonybrew/Homebrew/.../Formula/ |
| **文档** | PHASE2-REPORT.md | ~/work/rustup-ohos/ |
| | PANAMAX-EVAL.md | ~/work/rustup-ohos/ |
| | OHOS-RUSTUP-GUIDE.md (本文档) | ~/work/rustup-ohos/ |

---

## 六、验证通过的测试项

| # | 测试 | 命令 | 结果 |
|---|------|------|------|
| 1 | 标准安装 | `rustup toolchain install stable` | 5 components 下载成功 |
| 2 | 默认设置 | `rustup default stable` | 显示 stable-aarch64-unknown-linux-ohos |
| 3 | Host 检测 | `rustup show` | Default host: aarch64-unknown-linux-ohos |
| 4 | rustc | `rustc --version` | 1.95.0 |
| 5 | cargo | `cargo --version` | 1.95.0 |
| 6 | rustfmt | `rustfmt --version` | 1.9.0-stable |
| 7 | clippy | `clippy-driver --version` | 0.1.95 |
| 8 | 编译运行 | `cargo run` (hello-ohos) | Hello from HarmonyOS! |
| 9 | clippy | `cargo clippy` | 正常 |
| 10 | fmt | `cargo fmt --check` | 正常 |
| 11 | rust-src | `rustup component add rust-src` | 9274 entries 安装成功 |
| 12 | rust-analyzer | `rustup component add rust-analyzer-preview` | 安装成功 |
| 13 | 幂等安装 | 再次 `rustup toolchain install stable` | "unchanged" |
| 14 | minimal profile | `rustup set profile minimal` + install | 只装 3 components |
| 15 | error handling | 服务器关闭后 install | "Connection refused" |
| 16 | 自更新禁用 | install 输出 | "self-update is disabled" |

---

## 七、后续计划

### 立即可做

- ~~将环境变量写入 shell profile 确保每次终端自动设置~~ (已完成 — ~/.zshrc)
- ~~将分发服务器改为开机自启脚本~~ (已完成 — start-dist-server.sh)

### 中期

- 当 GitHub 访问恢复时，用 patch 提交上游 PR 到 rust-lang/rustup

### 长期

- OHOS 成为 rustup 上游支持 target 后，直接用官方 channel
- Panamax 全功能镜像 (rustup + crates.io)

---

## 八、新增架构支持 (x86_64 等)

基础设施已就绪，添加新架构只需 4 步：

### 8.1 步骤

```sh
# Step 1: 获取新架构的预编译 Rust 工具链
# 将工具链放置到 ~/usr/rust-<版本>-<triple>/
# 例如 x86_64: ~/usr/rust-1.95.0-x86_64-unknown-linux-ohos/

# Step 2: 构建分发 tarballs
/data/service/hnp/bin/bash ~/work/rustup-ohos/scripts/build-ohos-dist.sh \
  -v 1.95.0 -t x86_64-unknown-linux-ohos

# Step 3: 重新生成多架构 manifest
/data/service/hnp/bin/bash ~/work/rustup-ohos/scripts/generate-manifest.sh \
  -v 1.95.0 -d ~/work/ohos-dist-server/dist

# Step 4: 重启分发服务器
~/work/ohos-dist-server/start-dist-server.sh stop && \
~/work/ohos-dist-server/start-dist-server.sh start
```

### 8.2 前提条件

新架构工具链的获取方式（取决于实际情况）：

| 来源 | 适用场景 |
|------|---------|
| OHOS NDK 自带 Rust 编译器 | 最快路径，需要确认 NDK 版本包含 rustc |
| 在 x86_64 OHOS 设备上原生编译 | 需要物理 x86_64 设备 |
| 从社区渠道获取预编译包 | 需要确认包格式兼容 rust-installer v3 |

### 8.3 Harmonybrew Formula 自动适配

`rustup-ohos.rb` 已参数化，`ohos_triple` 方法根据 `Hardware::CPU.arch` 自动选择 triple：
- arm64 → `aarch64-unknown-linux-ohos`
- x86_64 → `x86_64-unknown-linux-ohos`

无需手动修改 formula 即可在不同架构设备上 `brew install rustup-ohos`。

### 8.4 分发服务器自动适配

`start-dist-server.sh` 通过 `uname -m` 自动检测架构，无需修改即可在新架构设备运行。

---

## 九、TLS 分发服务器

### 9.1 概述

分发服务器支持可选 TLS（HTTPS），适用于局域网内多设备分发场景。

- 默认：HTTP on 127.0.0.1（本地单设备使用，流量不离开设备）
- HTTPS：需提供证书和私钥，可绑定 0.0.0.0 供局域网其他设备访问

### 9.2 启用 TLS

```sh
# 生成自签名证书
/data/service/hnp/bin/bash ~/work/ohos-dist-server/scripts/generate-self-signed-cert.sh

# 启动 HTTPS 分发服务器（绑定所有接口，供局域网访问）
TLS_CERT=~/work/ohos-dist-server/certs/server.pem \
TLS_KEY=~/work/ohos-dist-server/certs/server.key \
BIND_ADDR=0.0.0.0 \
~/work/ohos-dist-server/start-dist-server.sh start
```

### 9.3 客户端配置

自签名证书不被系统 CA 信任，客户端需配置：

**方式 A: 信任自签名（开发环境推荐）**
```sh
export RUSTUP_TLS_VERIFY=0
export RUSTUP_DIST_SERVER=https://<服务器IP>:8080
rustup toolchain install stable
```

**方式 B: 导入证书到系统 CA（生产环境推荐）**
```sh
# 将 server.pem 复制到客户端设备
sudo cp server.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
export RUSTUP_DIST_SERVER=https://<服务器IP>:8080
```

### 9.4 技术实现

- `tiny_http` SSL feature (`ssl-openssl`) 提供 HTTPS 支持
- `openssl = "0.10"` crate 处理 TLS 加密
- CLI 参数：`--tls-cert <path>` / `--tls-key <path>` / `--bind <addr>`
- 证书格式：PEM（ECDSA P-256 或 RSA）

---

## 十、rustup-init 一键安装 (curl | sh)

### 10.1 概述

新用户可通过标准 `curl | sh` 方式安装 rustup，无需手动编译或配置。

rustup-init 安装闭环通过以下组件实现：
1. **rustup-init.sh** — 托管在 dist server，已注入 OHOS 环境变量
2. **签名 rustup-init** — OHOS 签名的安装二进制，放在 dist + archive 路径
3. **release-stable.toml** — 版本信息文件
4. **RUSTUP_UPDATE_ROOT** — 指向本地 dist server 的 `/rustup` 路径

### 10.2 安装方式

**交互式安装**：
```sh
curl http://127.0.0.1:8080/rustup-init.sh | sh
```

**非交互式安装**：
```sh
curl http://127.0.0.1:8080/rustup-init.sh | sh -s -- -y --default-toolchain stable
```

**局域网 HTTPS 安装**（需先启用 TLS + 启动 dist server）：
```sh
curl -k https://<服务器IP>:8080/rustup-init.sh | sh -s -- -y
```

### 10.3 安装流程

| 步骤 | 说明 | URL / 文件 |
|------|------|------------|
| 1 | 下载 rustup-init.sh | `curl http://127.0.0.1:8080/rustup-init.sh` |
| 2 | 脚本设置环境变量 | `RUSTUP_UPDATE_ROOT=http://127.0.0.1:8080/rustup` (注入) |
| 3 | 检测 OHOS 平台 | `_arch=aarch64-unknown-linux-ohos` |
| 4 | 下载签名 rustup-init | `http://127.0.0.1:8080/rustup/dist/aarch64-unknown-linux-ohos/rustup-init` |
| 5 | 执行 rustup-init | 交互式选择或 `-y` 自动 |
| 6 | 安装 stable toolchain | `rustup toolchain install stable` (via RUSTUP_DIST_SERVER) |

### 10.4 部署命令

部署脚本 `deploy-rustup-init.sh` 自动完成签名、目录创建、脚本注入：

```sh
/data/service/hnp/bin/bash ~/work/rustup-ohos/scripts/deploy-rustup-init.sh
```

参数：`-v` 版本、`-t` 目标、`-d` dist 目录、`-u` UPDATE_ROOT URL

### 10.5 自更新说明

rustup 以 `no-self-update` 编译，**自更新功能已禁用**。这是 OHOS 的设计约束——从官方服务器下载的 rustup-init 无 OHOS 签名，无法执行。

更新 rustup 的方式：
```sh
harmonybrew upgrade rustup-ohos
```

### 10.6 URL 路径结构

dist server 目录布局：

```
dist/
├── rustup-init.sh                          # 安装脚本（注入 OHOS 环境变量）
├── rustup/
│   ├── release-stable.toml                 # 版本信息
│   ├── dist/aarch64-unknown-linux-ohos/
│   │   └── rustup-init                     # 默认路径
│   └── archive/1.30.0/aarch64-unknown-linux-ohos/
│       └── rustup-init                     # 版本锁定路径
```
