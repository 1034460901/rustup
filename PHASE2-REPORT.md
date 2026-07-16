# 鸿蒙 rustup 适配 — Phase 2 完成报告

## 日期: 2026-07-16

## 概述

Phase 2 目标：搭建私有分发服务器，使 `RUSTUP_DIST_SERVER` + `rustup install stable` 可直接工作。已全部完成并通过验证。

## Step 0: Host Detection Fix ✅

修改 `~/work/rustup-ohos/src/dist/mod.rs` 为 OHOS 添加 `cfg(target_env = "ohos")` 常量映射，使 `rustup show` 输出 `Default host: aarch64-unknown-linux-ohos`（而非之前错误的 `aarch64-unknown-linux-musl`）。

修改内容：
- 所有 `TUPLE_*_UNKNOWN_LINUX` 常量新增 `not(target_env = "ohos")` 条件
- 新增 OHOS 专属常量：`aarch64-unknown-linux-ohos`, `x86_64-unknown-linux-ohos`, `loongarch64-unknown-linux-ohos`, `powerpc64-unknown-linux-ohos`, `powerpc64le-unknown-linux-ohos`

重新编译并签名安装 rustup v1.30.0，验证 host detection 正确。

## Step 1: Tarball Packaging Infrastructure ✅

脚本: `~/work/rustup-ohos/scripts/build-ohos-dist.sh`

最终版本使用函数式设计（而非 glob pattern 文件列表），解决了以下关键 bug：
- **glob pattern 不展开**: `[[ -e "$glob" ]]` 将 glob 当作字面量，不匹配实际文件
- **双重 lib 前缀**: `lib/lib${so}` → `lib/liblibrustc_driver`，需改为 `lib/${so}`
- **manifest.in 格式**: 必须使用 `file:path` 前缀（不是裸路径）
- **遗漏 .so 文件**: `librustc_driver-*.so` 等在顶层 `lib/` 目录（非 `lib/rustlib/` 下），必须加入 rustc 组件
- **proc-macro .so 文件**: `libserde_derive-*.so` 等必须加入 cargo 组件

组件拆分结果：
| 组件 | manifest 条目数 | 关键内容 |
|------|----------------|---------|
| rustc | 12 | bin/rustc, bin/rustdoc, rust-objcopy, librustc_driver.so, librustc_macros.so, librustc_index_macros.so, librustc_type_ir_macros.so, gdb/lldb scripts |
| cargo | 59 | bin/cargo, 13 proc-macro .so, libssl.so, libcrypto.so, man pages, shell completions |
| rust-std | 60 | lib/rustlib/${TARGET}/lib/ 下所有 .rlib/.rmeta/.so |
| rustfmt-preview | 2 | bin/rustfmt, bin/cargo-fmt |
| clippy-preview | 2 | bin/clippy-driver, bin/cargo-clippy |
| rust-analyzer-preview | 1 | bin/rust-analyzer |
| rust-src | 9274 | lib/rustlib/src/rust/library/ 全部源码 |
| rust (combined) | — | 以上 5 个 default profile 组件合并 |

## Step 2: Manifest Generation ✅

文件: `~/work/ohos-dist-server/dist/channel-rust-stable.toml`

Manifest v2 TOML 格式，包含：
- `pkg.rust`（combined package）+ 5 components + 2 extensions
- `pkg.rustc`, `pkg.cargo`, `pkg.rust-std`, `pkg.rustfmt-preview`, `pkg.clippy-preview`, `pkg.rust-analyzer-preview`, `pkg.rust-src`
- `[renames]` 映射: rustfmt→rustfmt-preview, clippy→clippy-preview, rust-analyzer→rust-analyzer-preview
- `[profiles]`: minimal, default, complete

URL 使用 `https://static.rust-lang.org/dist/` 基址，rustup 运行时通过 `RUSTUP_DIST_SERVER` 替换。

SHA-256 hashes 与实际 tarball 完全匹配。

## Step 3: Distribution Server MVP ✅

服务: `python3 -m http.server 8000 --bind 127.0.0.1`（运行于 `~/work/ohos-dist-server/`）

目录结构:
```
dist/
  channel-rust-stable.toml
  channel-rust-stable.toml.sha256
  rust-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rust-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  cargo-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  cargo-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rust-std-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  rustfmt-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rustfmt-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  clippy-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  clippy-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  rust-analyzer-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rust-analyzer-preview-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
  rust-src-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  rust-src-1.95.0-aarch64-unknown-linux-ohos.tar.gz.sha256
```

## Step 4: rust-src Component ✅

`rustup component add rust-src` — 下载安装成功（9274 entries）

`rustup component add rust-analyzer-preview` — 下载安装成功

## Step 5: Integration Testing ✅

| # | 测试项 | 结果 |
|---|--------|------|
| 1 | Fresh install | ✅ `rustup toolchain install stable` 成功，rustc --version = 1.95.0 |
| 2 | Component add | ✅ `rustup component add rust-src` + `rust-analyzer-preview` 成功 |
| 3 | Default set | ✅ `rustup default stable` → `rustup show` 显示 stable-aarch64-unknown-linux-ohos |
| 4 | Signing verify | ✅ 所有 ELF binary 可执行（binary-sign-tool 签名 + OHOS auto-sign） |
| 5 | Update flow | ✅ 重复 `rustup toolchain install stable` 显示 "unchanged" |
| 6 | cargo run | ✅ hello-ohos 项目编译+签名+运行成功 |
| 7 | clippy/fmt | ✅ cargo clippy / cargo fmt 正常 |
| 8 | rust-analyzer | ✅ rust-analyzer --version = 1.95.0 |
| 9 | Host detection | ✅ Default host: aarch64-unknown-linux-ohos |

## Phase 2 产出文件清单

| 文件 | 位置 |
|------|------|
| Host detection patch | `~/work/rustup-ohos/src/dist/mod.rs` |
| Tarball build script | `~/work/rustup-ohos/scripts/build-ohos-dist.sh` |
| Channel manifest | `~/work/ohos-dist-server/dist/channel-rust-stable.toml` |
| Manifest SHA-256 | `~/work/ohos-dist-server/dist/channel-rust-stable.toml.sha256` |
| 8 组组件 tarballs | `~/work/ohos-dist-server/dist/*.tar.gz` + `.sha256` |
| Rustup binary (signed) | `~/.cargo/bin/rustup` v1.30.0 |

## 遗留事项

- Step 6: Panamax 升级路径（文档级，非必须）
- Profile 测试（minimal profile 安装验证）
- 错误处理测试（服务器关闭时 rustup 报网络错误）
- Phase 3: 上游贡献 PR（将 OHOS host detection 提交到 rust-lang/rustup）

## Bug 修复记录

| Bug | 原因 | 修复 |
|-----|------|------|
| manifest.in 空 | glob pattern 在 `[[ -e ]]` 不展开 | 函数式 setup + `find` 生成 manifest |
| rustc/cargo 缺 .so | `.so` 文件在顶层 `lib/` 不在 `lib/rustlib/` 下 | setup_rustc/setup_cargo 函数用 `for candidate in ${pattern}` 展开 |
| 双重 lib 前缀 | `lib/lib${so}` → `lib/liblibrustc_driver` | 改为 `lib/${so}` |
| rustc 无法运行 | 缺 librustc_driver.so 导致 symbol not found | 将 .so 文件加入 rustc 组件 manifest |
| binary sign 后权限丢失 | binary-sign-tool 移除 +x 权限 | sign_elf 后 chmod +x |
