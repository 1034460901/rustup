# OHOS (HarmonyOS) rustup 适配 — 代码构成、改动点与使用指南

> 版本: v2.0 | 日期: 2026-07-17 | 平台: HarmonyOS HongMeng Kernel 1.12.0 aarch64

---

## 一、项目概述

OHOS (HarmonyOS/OpenHarmony) 在 Rust target triple 中使用 `target_env="ohos"`，但 `libc::uname()` 返回 `sysname="HarmonyOS"` 而非 `"Linux"`，导致上游 rustup 无法识别 host 平台。本项目通过修改 rustup 源码 + 构建私有分发基础设施，使 OHOS 开发者可以通过 `rustup toolchain install stable` 安装和管理 Rust 工具链。

**核心架构**：

```
新用户 ──curl|sh──▶ rustup-init.sh ──下载──▶ 签名 rustup-init ──执行──▶ rustup install stable
                                                        │
                                    本地 dist server (tiny_http, HTTP/HTTPS)
                                                        │
                              channel-rust-stable.toml + 8 组 aarch64 tarballs
                              release-stable.toml + 签名 rustup-init 二进制
```

---

## 二、代码构成总览

### 2.1 目录结构

```
~/work/rustup-ohos/                         # rustup 源码仓库 (含 OHOS 改动)
├── src/dist/mod.rs                         # ★ 核心改动: host detection
├── rustup-init.sh                          # ★ 核心改动: OS 检测分支
├── 0001-ohos-host-detection-mod-rs.patch   # 上游 PR patch 1
├── 0002-ohos-rustup-init-sh.patch          # 上游 PR patch 2
├── scripts/
│   ├── build-ohos-dist.sh                  # tarball 构建 (参数化)
│   ├── generate-manifest.sh                # manifest 自动生成
│   └── deploy-rustup-init.sh               # rustup-init 部署 (签名+注入)
├── target/aarch64-unknown-linux-ohos/release/
│   └── rustup-init                         # 编译产物
├── OHOS-RUSTUP-GUIDE.md                    # 技术文档
└── STATUS-CHECKLIST.md                     # 状态清单

~/work/ohos-dist-server/                    # 私有分发服务器
├── src/main.rs                             # ★ Rust HTTP/HTTPS 服务器
├── Cargo.toml                              # ★ tiny_http + ssl feature
├── certs/
│   ├── server.pem                          # 自签名 ECDSA 证书
│   └── server.key                          # 私钥
├── scripts/
│   └── generate-self-signed-cert.sh        # 证书生成脚本
├── start-dist-server.sh                    # ★ 启停脚本 (架构检测+TLS)
├── target/aarch64-unknown-linux-ohos/release/
│   └── ohos-dist-server-signed             # 签名服务器二进制
└── dist/                                   # 分发产物目录
    ├── channel-rust-stable.toml            # 工具链 manifest v2
    ├── channel-rust-stable.toml.sha256
    ├── rustup-init.sh                      # ★ 注入 env 的安装脚本
    ├── rustup-init.sh.sha256
    ├── rustup/
    │   ├── release-stable.toml             # rustup 版本信息
    │   ├── dist/aarch64-unknown-linux-ohos/
    │   │   └── rustup-init                 # ★ 签名安装二进制 (默认路径)
    │   └── archive/1.30.0/aarch64-unknown-linux-ohos/
    │       └── rustup-init                 # ★ 签名安装二进制 (版本锁定)
    ├── rustc-1.95.0-*.tar.gz + .sha256     # 7 组 aarch64 组件 tarball
    ├── cargo-1.95.0-*.tar.gz + .sha256
    ├── rust-std-1.95.0-*.tar.gz + .sha256
    ├── rustfmt-preview-1.95.0-*.tar.gz + .sha256
    ├── clippy-preview-1.95.0-*.tar.gz + .sha256
    ├── rust-analyzer-preview-1.95.0-*.tar.gz + .sha256
    ├── rust-src-1.95.0-*.tar.gz + .sha256
    ├── rust-1.95.0-*.tar.gz + .sha256      # 合并包
    └── rustup-ohos-1.30.0-src.tar.gz       # OHOS fork 源码 tarball

~/.harmonybrew/Homebrew/Library/Taps/zqz979/homebrew-ohos/Formula/
└── rustup-ohos.rb                          # ★ Harmonybrew formula (架构参数化)

~/.zshrc                                    # ★ 环境变量持久化

~/.cargo/bin/rustup                         # 安装的 rustup 二进制 (签名)
~/.rustup/toolchains/stable-aarch64-unknown-linux-ohos/  # 安装的 stable 工具链
```

---

## 三、上游源码改动详解

### 3.1 改动 1: `src/dist/mod.rs` — Rust 侧 host detection

**文件**: `~/work/rustup-ohos/src/dist/mod.rs`
**Patch**: `0001-ohos-host-detection-mod-rs.patch` (78 行)
**对应上游**: `rust-lang/rustup` 仓库 `src/dist/mod.rs`

#### 改动 A: 新增 5 个 OHOS TUPLE 常量 (line 715-729)

原先 Linux host 的 TUPLE 常量统一使用 `-gnu` 后缀（或 `-musl`），OHOS 需要独立的 `-ohos` 后缀常量。遵循 `target_env` cfg guard 的 musl 先例：

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

**设计原理**: Rust cfg 系统中，同一常量名可有多个 `#[cfg]` 版本，编译器根据当前 target 选择唯一一个。OHOS 的 `target_env="ohos"` 独立于 `"gnu"` 和 `"musl"`，形成三路互斥。

#### 改动 B: 更新 gnu cfg guards (line 726, 730, 734, 738, 742)

原来 `#[cfg(all(not(windows), not(target_env = "musl")))]` 只排除 musl，现在同时排除 ohos：

```rust
// 原先 (只排除 musl):
#[cfg(all(not(windows), not(target_env = "musl")))]
const TUPLE_X86_64_UNKNOWN_LINUX: &str = "x86_64-unknown-linux-gnu";

// 改为 (排除 musl + ohos):
#[cfg(all(not(windows), not(target_env = "musl"), not(target_env = "ohos")))]
const TUPLE_X86_64_UNKNOWN_LINUX: &str = "x86_64-unknown-linux-gnu";
```

5 个 gnu 常量均需同样更新，确保 gnu/musl/ohos 三路互斥无冲突。

#### 改动 C: 新增 OHOS uname match arm (line 640-661)

原 `from_host()` 函数中 `#[cfg(not(target_os = "android"))]` 的 Linux uname 匹配不处理 `sysname="HarmonyOS"`。新增 `#[cfg(target_env = "ohos")]` 专属匹配块：

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

**设计原理**: 遵循 android 先例——android 也有独立的 `#[cfg(target_os = "android")]` 匹配块。OHOS 的 `sysname` 固定返回 `"HarmonyOS"` 或 `"OpenHarmony"`，精确匹配优先，fallback 模式按 `machine` 匹配（兼容未来内核版本可能改变 sysname 的情况）。

同时原 `#[cfg(not(target_os = "android"))]` 改为 `#[cfg(all(not(target_os = "android"), not(target_env = "ohos")))]`，避免 OHOS 编译时同时触发 Linux 和 OHOS 匹配块。

### 3.2 改动 2: `rustup-init.sh` — Shell 侧 OS 检测

**文件**: `~/work/rustup-ohos/rustup-init.sh`
**Patch**: `0002-ohos-rustup-init-sh.patch` (4 行新增)
**对应上游**: `rust-lang/rustup` 仓库 `rustup-init.sh`

在 `get_architecture()` 函数的 `_ostype` case 分支中，在 `*` (unknown) 之前新增：

```sh
HarmonyOS | OpenHarmony)
    _ostype=unknown-linux-ohos
    ;;
```

**设计原理**: `rustup-init.sh` 通过 `uname -s` 获取 OS 类型。OHOS 内核返回 `"HarmonyOS"` 或 `"OpenHarmony"`，不匹配任何现有 case 分支。新增分支使脚本正确构造 triple 后缀 `-unknown-linux-ohos`。

### 3.3 改动汇总表

| 改动点 | 文件 | 行数 | 上游对应 | 效果 |
|--------|------|------|---------|------|
| OHOS TUPLE 常量 | `src/dist/mod.rs` | 5 常量 | L715-729 | cfg(target_env="ohos") 编译时选择 `-ohos` triple |
| gnu guard 更新 | `src/dist/mod.rs` | 5 行 | L726-742 | 三路互斥: gnu/musl/ohos |
| OHOS uname match | `src/dist/mod.rs` | 20 行 | L640-661 | HarmonyOS/OpenHarmony → ohos triple |
| Linux guard 更新 | `src/dist/mod.rs` | 1 行 | L591 | 排除 ohos 进入 Linux 匹配 |
| Shell OS 检测 | `rustup-init.sh` | 4 行 | L452-455 | HarmonyOS/OpenHarmony → unknown-linux-ohos |

---

## 四、私有分发服务器

### 4.1 `ohos-dist-server` — Rust HTTP/HTTPS 静态文件服务器

**文件**: `~/work/ohos-dist-server/src/main.rs` (155 行)

基于 `tiny_http 0.12` 的轻量服务器，支持可选 TLS。

#### Cargo.toml 依赖

```toml
tiny_http = { version = "0.12", features = ["ssl"] }   # HTTP + HTTPS
ascii = "1.1"
openssl = "0.10"                                         # TLS 加密 (optional)
```

#### CLI 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `port` (位置参数 1) | 8080 | 监听端口 |
| `dist_dir` (位置参数 2) | ~/work/ohos-dist-server/dist | 分发目录 |
| `--bind` | 127.0.0.1 | 绑定地址 (0.0.0.0 = 局域网) |
| `--tls-cert` | None | TLS 证书 PEM 路径 |
| `--tls-key` | None | TLS 私钥 PEM 路径 |

#### URL 路由逻辑 (`resolve_file()`)

```rust
fn resolve_file(url: &str, dist_dir: &str) -> PathBuf {
    let path = url.trim_start_matches('/');
    let base = PathBuf::from(dist_dir);

    if path.starts_with("dist/") {
        base.join(&path[5..])       // /dist/xxx → dist_dir/xxx
    } else if path.is_empty() {
        base.join("channel-rust-stable.toml")  // / → manifest
    } else {
        base.join(path)             // 其他 → dist_dir/path
    }
}
```

**路由映射表**:

| 请求 URL | 文件路径 | 用途 |
|-----------|---------|------|
| `/` | `dist/channel-rust-stable.toml` | rustup 读取工具链 manifest |
| `/dist/rustc-*.tar.gz` | `dist/rustc-*.tar.gz` | 组件 tarball 下载 |
| `/rustup-init.sh` | `dist/rustup-init.sh` | curl|sh 安装脚本 |
| `/rustup/release-stable.toml` | `dist/rustup/release-stable.toml` | rustup 版本信息 |
| `/rustup/dist/{triple}/rustup-init` | `dist/rustup/dist/{triple}/rustup-init` | 默认安装路径 |
| `/rustup/archive/{ver}/{triple}/rustup-init` | `dist/rustup/archive/{ver}/{triple}/rustup-init` | 版本锁定路径 |

#### 安全措施

- 路径遍历防护: `file_path.starts_with(&dist_dir)` 检查
- 不在 dist_dir 下的请求返回 403
- 不存在的文件返回 404

#### TLS 模式

```rust
// 无 TLS → HTTP (默认)
Server::http(&addr)

// 有 TLS → HTTPS
let cert_data = std::fs::read(cert)?;  // PEM 文件内容
let key_data = std::fs::read(key)?;
let ssl = SslConfig { certificate: cert_data, private_key: key_data };
Server::https(&addr, ssl)
```

### 4.2 `start-dist-server.sh` — 启停脚本

**文件**: `~/work/ohos-dist-server/start-dist-server.sh`

| 特性 | 实现 |
|------|------|
| 架构检测 | `uname -m` → `TRIPLE` (aarch64→aarch64-unknown-linux-ohos, x86_64→x86_64-unknown-linux-ohos) |
| PID 管理 | `dist-server.pid` 文件 |
| TLS 透传 | `TLS_CERT` / `TLS_KEY` / `BIND_ADDR` 环境变量 |
| 命令 | `start` / `stop` / `status` |

### 4.3 自签名证书生成

**文件**: `~/work/ohos-dist-server/scripts/generate-self-signed-cert.sh`

生成 P-256 ECDSA 自签名证书 (365 天有效期, SAN: localhost + 127.0.0.1):

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -days 365 -nodes \
    -keyout certs/server.key -out certs/server.pem \
    -subj '/CN=localhost' \
    -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
```

---

## 五、构建与部署脚本

### 5.1 `build-ohos-dist.sh` — 组件 tarball 构建

**文件**: `~/work/rustup-ohos/scripts/build-ohos-dist.sh`

从预编译工具链目录拆包为 rust-installer v3 格式组件 tarball，签名所有 ELF binary，生成 SHA-256 hash。

#### CLI 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-v, --version` | 1.95.0 | Rust 版本 |
| `-t, --target` | aarch64-unknown-linux-ohos | 目标 triple |
| `-T, --toolchain-dir` | ~/usr/rust-{ver}-{target} | 预编译工具链路径 |
| `-d, --dist-dir` | ~/work/ohos-dist-server/dist | 输出目录 |
| `-s, --sign-tool` | /data/service/hnp/bin/binary-sign-tool | 签名工具 |

#### 7 个组件 + 1 个合并包

| 组件 | setup 函数 | 内容 |
|------|-----------|------|
| rustc | `setup_rustc()` | rustc + rustdoc + driver .so + rust-objcopy + debugger scripts |
| cargo | `setup_cargo()` | cargo + proc-macro .so + libssl/libcrypto + man pages |
| rust-std | `setup_rust_std()` | std lib (rlib + rmeta + .so) |
| rustfmt-preview | `setup_rustfmt()` | rustfmt + cargo-fmt |
| clippy-preview | `setup_clippy()` | clippy-driver + cargo-clippy |
| rust-analyzer-preview | `setup_rust_analyzer()` | rust-analyzer |
| rust-src | `setup_rust_src()` | Rust 源码 (平台无关) |
| rust | (合并包) | rustc + cargo + rust-std + rustfmt + clippy (meta-package) |

#### 输出

每组组件: `{name}-{version}-{target}.tar.gz` + `.tar.gz.sha256`

### 5.2 `generate-manifest.sh` — Manifest 自动生成

**文件**: `~/work/rustup-ohos/scripts/generate-manifest.sh`

自动扫描 dist 目录中的 `.sha256` 文件发现可用 triple，生成 `channel-rust-stable.toml`。

#### CLI 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-v, --version` | 1.95.0 | Rust 版本 |
| `-d, --dist-dir` | ~/work/ohos-dist-server/dist | dist 目录 |

#### 自动发现逻辑

```sh
# 从 rustc tarball sha256 文件提取 triple
for sha_file in dist/rustc-${VERSION}-*.tar.gz.sha256; do
    triple="${basename#rustc-${VERSION}-}"
    triple="${triple%.tar.gz.sha256}"
done
```

#### manifest 结构

```toml
manifest-version = "2"
date = "2026-07-17"

[pkg.rust]           # 合包 (components + extensions)
[pkg.rustc]          # 编译器
[pkg.cargo]          # 包管理器
[pkg.rust-std]       # 标准库
[pkg.rustfmt-preview]# 格式化器
[pkg.clippy-preview] # 代码检查
[pkg.rust-analyzer-preview] # LSP
[pkg.rust-src]       # 源码 (target = "*")

[renames]            # rustfmt → rustfmt-preview 等
[profiles]           # minimal / default / complete
```

每个 `[pkg.X]` 有对应的 `[pkg.X.target.{triple}]` 子段，多架构时自动扩展。

### 5.3 `deploy-rustup-init.sh` — rustup-init 部署

**文件**: `~/work/rustup-ohos/scripts/deploy-rustup-init.sh`

签名 rustup-init 二进制，部署到 dist + archive URL 路径，生成 `release-stable.toml`，注入环境变量到 `rustup-init.sh`。

#### CLI 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-v, --version` | 1.30.0 | Rustup 版本 |
| `-t, --target` | aarch64-unknown-linux-ohos | 目标 triple |
| `-d, --dist-dir` | ~/work/ohos-dist-server/dist | dist 目录 |
| `-r, --rustup-dir` | ~/work/rustup-ohos | rustup 源码目录 |
| `-s, --sign-tool` | /data/service/hnp/bin/binary-sign-tool | 签名工具 |
| `-u, --update-root` | http://127.0.0.1:8080/rustup | RUSTUP_UPDATE_ROOT URL |

#### 6 步流程

1. **验证前提**: rustup-init 二进制、签名工具、rustup-init.sh 存在
2. **签名**: `binary-sign-tool -selfSign SHA256withECDSA` → 验证 `.codesign` section
3. **部署二进制**: 两个 URL 路径:
   - `dist/rustup/dist/{triple}/rustup-init` (默认路径)
   - `dist/rustup/archive/{ver}/{triple}/rustup-init` (版本锁定)
4. **生成 release-stable.toml**: `schema-version = "1", version = "1.30.0"`
5. **注入 rustup-init.sh**: 复制原始脚本，在 shebang 后插入:
   ```sh
   export RUSTUP_UPDATE_ROOT="http://127.0.0.1:8080/rustup"
   export RUSTUP_DIST_SERVER="http://127.0.0.1:8080"
   ```
6. **验证**: 检查所有文件存在 + `.codesign` section

---

## 六、Harmonybrew Formula

**文件**: `~/.harmonybrew/Homebrew/Library/Taps/zqz979/homebrew-ohos/Formula/rustup-ohos.rb`

### 6.1 关键特性

| 特性 | 实现 |
|------|------|
| 源码来源 | 本地 OHOS fork tarball (含 host detection patches) |
| 架构自适应 | `ohos_triple` 方法: `Hardware::CPU.arch` → triple |
| 编译选项 | `no-self-update,reqwest-native-tls` |
| ELF 签名 | `binary-sign-tool` 自签 → `chmod 0755` |
| 代理命令 | post_install 创建 rustup/cargo/clippy 等 symlink |

### 6.2 ohos_triple 方法

```ruby
def ohos_triple
  case Hardware::CPU.arch
  when :arm64  then "aarch64-unknown-linux-ohos"
  when :x86_64 then "x86_64-unknown-linux-ohos"
  else raise "Unsupported OHOS architecture: #{Hardware::CPU.arch}"
  end
end
```

在 `install` 方法中 3 处引用:
- `ENV["RUSTUP_OVERRIDE_BUILD_TUPLE"] = ohos_triple`
- `"--target", ohos_triple`
- `bin.install "target/#{ohos_triple}/release/rustup-init"`

### 6.3 构建环境变量

```ruby
ENV["CC"] = "clang"
ENV["CXX"] = "clang++"
ENV["RUST_MIN_STACK"] = "8388608"
ENV["RUSTUP_OVERRIDE_BUILD_TUPLE"] = ohos_triple
ENV["OPENSSL_DIR"] = "#{HOMEBREW_PREFIX}"
ENV["RUSTUP_DIST_SERVER"] = "http://127.0.0.1:8080"
ENV["RUSTUP_UPDATE_ROOT"] = "http://127.0.0.1:8080/rustup"
```

---

## 七、环境变量配置

**文件**: `~/.zshrc`

```sh
# >>> Rust via rustup (OHOS) >>>
export PATH="$HOME/.cargo/bin:$PATH"
export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"
export LD_LIBRARY_PATH="$HOME/.harmonybrew/lib:$HOME/.rustup/toolchains/stable-aarch64-unknown-linux-ohos/lib:$HOME/.harmonybrew/Homebrew/lib"
export RUST_MIN_STACK=8388608
export RUSTUP_DIST_SERVER=http://127.0.0.1:8080
export RUSTUP_UPDATE_ROOT=http://127.0.0.1:8080/rustup
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=clang
export CC="clang"
export CXX="clang++"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/cacert.pem}"
# <<< Rust via rustup (OHOS) <<<</sh>
```

### 7.1 各变量说明

| 变量 | 值 | 必要性 | 说明 |
|------|-----|--------|------|
| `PATH` | ~/.cargo/bin | 必须 | rustup 代理命令路径 |
| `RUSTUP_HOME` | ~/.rustup | 必须 | rustup 数据目录 |
| `CARGO_HOME` | ~/.cargo | 必须 | cargo 数据目录 |
| `LD_LIBRARY_PATH` | 3 个路径 | 必须 | 动态库查找: harmonybrew + toolchain + Homebrew |
| `RUST_MIN_STACK` | 8388608 (8MB) | 必须 | OHOS musl 默认栈仅 128KB，异步运行时需更大栈 |
| `RUSTUP_DIST_SERVER` | http://127.0.0.1:8080 | 必须 | 工具链下载源 (替换官方 static.rust-lang.org) |
| `RUSTUP_UPDATE_ROOT` | http://127.0.0.1:8080/rustup | 推荐 | rustup-init 安装路径 (curl|sh 闭环) |
| `CARGO_TARGET_*_LINKER` | clang | 推荐 | cargo 交叉编译链接器 |
| `CC/CXX` | clang/clang++ | 推荐 | C/C++ 编译器 |
| `SSL_CERT_FILE` | /etc/ssl/certs/cacert.pem | 可选 | HTTPS CA 证书路径 |

---

## 八、Rust 使用方式

### 8.1 安装方式（三选一）

#### 方式 A: curl | sh 一键安装 (推荐新用户)

```sh
# 确保分发服务器运行
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 交互式安装
curl http://127.0.0.1:8080/rustup-init.sh | sh

# 非交互式安装
curl http://127.0.0.1:8080/rustup-init.sh | sh -s -- -y --default-toolchain stable
```

安装流程: 下载 rustup-init.sh → 检测 OHOS → 下载签名 rustup-init → 执行 → 安装 stable 工具链

#### 方式 B: Harmonybrew 安装

```sh
# 确保分发服务器运行
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 安装
harmonybrew install rustup-ohos

# 设置默认工具链
rustup default stable
```

#### 方式 C: 手动 toolchain link (原始方式，不推荐)

```sh
# 仅在无法启动分发服务器时使用
rustup toolchain link stable ~/usr/rust-1.95.0-aarch64-unknown-linux-ohos
rustup default stable
```

### 8.2 日常使用

```sh
# 查看当前工具链
rustup show
# 输出: Default host: aarch64-unknown-linux-ohos
#        stable-aarch64-unknown-linux-ohos (default)

# 安装/更新 stable 工具链 (需分发服务器运行)
rustup toolchain install stable

# 编译运行
cargo new my-project && cd my-project
cargo run
# 输出: Hello, world!

# 代码检查
cargo clippy

# 格式化
cargo fmt

# 添加组件
rustup component add rust-src          # 标准库源码
rustup component add rust-analyzer     # LSP 服务器
rustup component add rustfmt           # 格式化器 (已含在 default profile)
rustup component add clippy            # 代码检查 (已含在 default profile)
```

### 8.3 Rust 工具链版本切换

```sh
# 安装不同版本 (需对应 tarball 在分发服务器)
rustup toolchain install 1.95.0
rustup toolchain install nightly  # 需额外构建 nightly tarball

# 切换默认
rustup default stable
rustup default 1.95.0

# 项目级覆盖
cd my-project
rustup override set nightly
```

### 8.4 更新 rustup 本体

```sh
# ❌ rustup self update — 禁用 (no-self-update)
# error: self-update is disabled for this build of rustup

# ✅ 通过 harmonybrew 更新
harmonybrew upgrade rustup-ohos
```

### 8.5 局域网多设备分发

```sh
# 服务器端: 启动 HTTPS 分发服务器
bash ~/work/ohos-dist-server/scripts/generate-self-signed-cert.sh

TLS_CERT=~/work/ohos-dist-server/certs/server.pem \
TLS_KEY=~/work/ohos-dist-server/certs/server.key \
BIND_ADDR=0.0.0.0 \
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 客户端: 安装 (开发环境，信任自签名)
export RUSTUP_TLS_VERIFY=0
export RUSTUP_DIST_SERVER=https://192.168.1.100:8080
curl -k https://192.168.1.100:8080/rustup-init.sh | sh -s -- -y
```

### 8.6 新版本工具链发布流程

当 Rust 发布新版本 (如 1.96.0) 且有对应 OHOS 预编译工具链时:

```sh
# 1. 构建新版本 tarball
bash ~/work/rustup-ohos/scripts/build-ohos-dist.sh -v 1.96.0 -t aarch64-unknown-linux-ohos

# 2. 重新生成 manifest
bash ~/work/rustup-ohos/scripts/generate-manifest.sh -v 1.96.0

# 3. 重启分发服务器
bash ~/work/ohos-dist-server/start-dist-server.sh stop
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 4. 更新 rustup-init 部署 (如果 rustup 也更新)
bash ~/work/rustup-ohos/scripts/deploy-rustup-init.sh -v 1.31.0

# 5. 客户端更新
rustup toolchain install stable
```

---

## 九、关键技术约束

### 9.1 ELF 签名 (OHOS 必须)

OHOS 要求所有可执行 ELF binary 包含 `.codesign` section。无签名 binary 无法执行 (exit 126)。

```sh
# 签名命令
/data/service/hnp/bin/binary-sign-tool sign -selfSign 1 -signAlg SHA256withECDSA \
    -inFile <binary> -outFile <binary-signed>

# 验证签名
readelf -S <binary> | grep codesign

# 注意: 签名后必须 chmod +x (签名工具会移除执行权限)
```

### 9.2 no-self-update (OHOS 必须)

rustup 自更新从官方服务器下载 unsigned rustup-init，在 OHOS 上无法执行。编译时必须禁用:

```sh
cargo build --release --features "no-self-update,reqwest-native-tls" --target aarch64-unknown-linux-ohos
```

用户通过 `harmonybrew upgrade rustup-ohos` 更新 rustup 本体。

### 9.3 native-tls (OHOS 推荐)

使用 `reqwest-native-tls` (OpenSSL) 而非默认 `reqwest-rustls`:
- `rustls-platform-verifier` 在 OHOS 上可能不兼容
- harmonybrew 提供 OpenSSL 3.6.3
- 编译时: `OPENSSL_DIR` 指向 harmonybrew openssl@3 Cellar

### 9.4 RUST_MIN_STACK (OHOS 必须)

OHOS musl libc 默认线程栈 128KB。rustup 的 reqwest/tokio 需要 ≥8MB:

```sh
export RUST_MIN_STACK=8388608  # 8MB
```

### 9.5 target_env = "ohos"

OHOS 在 Rust triple 系统中的定位:
- `target_os = "linux"` (内核 ABI 与标准 Linux 相同)
- `target_env = "ohos"` (区别于 gnu/musl 的 C 库环境)
- triple 格式: `{arch}-unknown-linux-ohos`
- `cfg(target_env = "ohos")` 编译时生效
- `cfg(target_os = "ohos")` **不存在** (OHOS 不是独立 target_os)

---

## 十、上游 PR Patch 说明

### Patch 1: `0001-ohos-host-detection-mod-rs.patch` (78 行)

**目标仓库**: `rust-lang/rustup`
**目标文件**: `src/dist/mod.rs`
**改动**: 5 个 OHOS TUPLE 常量 + 5 个 gnu guard 更新 + 1 个 Linux guard 更新 + OHOS uname match arm (20 行)

### Patch 2: `0002-ohos-rustup-init-sh.patch` (4 行)

**目标仓库**: `rust-lang/rustup`
**目标文件**: `rustup-init.sh`
**改动**: `HarmonyOS | OpenHarmony` case 分支

**当前状态**: Patch 已就绪，GitHub 访问受限暂未推送。等网络条件恢复后提交 PR 到 `rust-lang/rustup`。

---

## 十一、验证通过的测试项

| # | 测试 | 命令 | 结果 |
|---|------|------|------|
| 1 | Host detection | `rustup show` | aarch64-unknown-linux-ohos |
| 2 | rustc | `rustc --version` | 1.95.0 |
| 3 | cargo | `cargo --version` | 1.95.0 |
| 4 | rustfmt | `rustfmt --version` | 1.9.0-stable |
| 5 | clippy | `clippy-driver --version` | 0.1.95 |
| 6 | 编译运行 | `cargo run` | Hello from HarmonyOS! arch=aarch64 |
| 7 | Self-update disabled | `rustup self update` | "self-update is disabled" |
| 8 | Idempotent install | `rustup toolchain install stable` | 正常重装 |
| 9 | clippy | `cargo clippy` | 正常 |
| 10 | fmt | `cargo fmt --check` | 正常 |
| 11 | rustup-init.sh 端点 | `curl http://127.0.0.1:8080/rustup-init.sh` | OHOS env 注入可见 |
| 12 | rustup-init dist 端点 | `curl -sI .../rustup/dist/{triple}/rustup-init` | HTTP 200 |
| 13 | rustup-init archive 端点 | `curl -sI .../rustup/archive/1.30.0/{triple}/rustup-init` | HTTP 200 |
| 14 | release-stable.toml 端点 | `curl .../rustup/release-stable.toml` | version=1.30.0 |
| 15 | channel manifest 端点 | `curl http://127.0.0.1:8080/` | manifest v2 |

---

## 十二、项目完成状态

| Phase | 内容 | 状态 |
|-------|------|------|
| Phase 1 | rustup 编译 + toolchain link + formula | 完成 |
| Phase 2 | 分发服务器 + rustup install stable | 完成 |
| Phase 3 | 上游 PR patch 准备 | 完成 |
| Phase 4 | formula 修复 + 脚本参数化 | 完成 |
| Phase 5 | 多架构支持 + TLS + manifest 自动生成 | 完成 |
| Phase 6 | 上游 PR 推送 | 暂不执行 (GitHub 访问受限) |
| Phase 7 | curl|sh 一键安装闭环 | 完成 |

**仅剩**: P6 上游 PR 推送 (等 GitHub 网络条件恢复)
