# OHOS rustup 与本地私有仓 — 关系、推送与更新指南

> 日期: 2026-07-20 | 平台: HarmonyOS HongMeng Kernel 1.12.0 aarch64

---

## 一、整体架构

```
┌─────────────────────────────────────────────────────┐
│                  本地私有仓 (dist server)             │
│                                                     │
│  ~/work/ohos-dist-server/dist/                      │
│  ├── channel-rust-stable.toml   ← rustup 读这个找组件 │
│  ├── rustc-1.95.0-*.tar.gz      ← rustup 下载这些    │
│  ├── cargo-1.95.0-*.tar.gz                           │
│  ├── rust-std-1.95.0-*.tar.gz                        │
│  ├── rustfmt-preview-1.95.0-*.tar.gz                 │
│  ├── clippy-preview-1.95.0-*.tar.gz                  │
│  ├── rust-analyzer-preview-1.95.0-*.tar.gz           │
│  ├── rust-src-1.95.0-*.tar.gz                        │
│  ├── rust-1.95.0-*.tar.gz (合并包)                    │
│  ├── rustup-init.sh              ← curl|sh 安装脚本   │
│  └── rustup/                                         │
│      ├── release-stable.toml     ← 版本信息           │
│      ├── dist/{triple}/rustup-init ← 默认安装路径     │
│      └── archive/{ver}/{triple}/     ← 版本锁定路径   │
│          rustup-init                                 │
│                                                     │
│  RUSTUP_DIST_SERVER=http://127.0.0.1:8080           │
│  ↑ 替换官方 static.rust-lang.org                    │
└─────────────────────────────────────────────────────┘
          ↑                        ↑
          │                        │
    新用户 curl|sh          已有用户 rustup install
```

**核心关系**：rustup 原本从官方 `static.rust-lang.org` 下载工具链。我们通过 `RUSTUP_DIST_SERVER` 环境变量指向本地 dist server (`127.0.0.1:8080`)，所有 tarball 和 manifest 完全本地构建，形成闭环。

---

## 二、rustup 下载流程详解

当你运行 `rustup toolchain install stable` 时：

```
rustup
  │
  ├─1. 请求 http://127.0.0.1:8080/channel-rust-stable.toml
  │     (URL 来自 RUSTUP_DIST_SERVER 环境变量)
  │
  ├─2. 解析 manifest，找到:
  │     - 版本号: rustc 1.95.0
  │     - 各组件 URL: https://static.rust-lang.org/dist/{name}-{ver}-{target}.tar.gz
  │     - 各组件 SHA-256 hash
  │     - profiles: minimal / default / complete
  │
  ├─3. URL 替换: rustup 将 URL 中的域名替换为 RUSTUP_DIST_SERVER
  │     https://static.rust-lang.org/dist/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  │     → http://127.0.0.1:8080/dist/rustc-1.95.0-aarch64-unknown-linux-ohos.tar.gz
  │
  ├─4. 逐个下载 tarball → 校验 SHA-256 → 解包 → 安装到 ~/.rustup/toolchains/
  │     (default profile 安装 5 个组件: rustc + cargo + rust-std + rustfmt + clippy)
  │
  └─5. 创建代理 symlink: ~/.cargo/bin/{rustc,cargo,clippy,...} → rustup
```

**dist server URL 路由** (`resolve_file()`):

| 请求 URL | 映射到文件 | rustup 用途 |
|-----------|-----------|------------|
| `/` | `dist/channel-rust-stable.toml` | 获取 manifest |
| `/dist/rustc-*.tar.gz` | `dist/rustc-*.tar.gz` | 下载组件 |
| `/dist/*.sha256` | `dist/*.sha256` | 校验 hash (rustup 内部计算，此文件供参考) |

---

## 三、如何往本地仓推送新版本源码

### 场景：Rust 发布新版本 (如 1.96.0)

前提：你已获得对应 OHOS 预编译工具链，放在 `~/usr/rust-1.96.0-aarch64-unknown-linux-ohos/`

```sh
# ── Step 1: 构建新版本 tarball ──
# 从预编译工具链目录拆包为 rust-installer v3 格式 + ELF 签名 + SHA-256
bash ~/work/rustup-ohos/scripts/build-ohos-dist.sh \
  -v 1.96.0 \
  -t aarch64-unknown-linux-ohos \
  -T ~/usr/rust-1.96.0-aarch64-unknown-linux-ohos

# 产出: dist/ 下新增 8 组 1.96.0 tarball + .sha256 文件


# ── Step 2: 重新生成 manifest ──
# 自动扫描 dist 目录的 .sha256 文件，发现所有可用 triple，
# 生成包含所有版本的 channel-rust-stable.toml
bash ~/work/rustup-ohos/scripts/generate-manifest.sh \
  -v 1.96.0 \
  -d ~/work/ohos-dist-server/dist

# 产出: dist/channel-rust-stable.toml (含 1.96.0 版本条目) + .sha256


# ── Step 3: 重启 dist server ──
# 让服务器加载新生成的文件
bash ~/work/ohos-dist-server/start-dist-server.sh stop
bash ~/work/ohos-dist-server/start-dist-server.sh start
```

3 步完成后，本地仓已有 1.96.0 组件。

### 场景：rustup 本体更新 (如 1.31.0)

rustup 自身版本升级（不仅是工具链版本）：

```sh
# ── Step 1: 编译新版 rustup ──
cd ~/work/rustup-ohos
cargo build --release \
  --features "no-self-update,reqwest-native-tls" \
  --target aarch64-unknown-linux-ohos --locked

# ── Step 2: 重新部署 rustup-init ──
# 签名 + 部署到 dist/archive 路径 + 更新 release-stable.toml
bash ~/work/rustup-ohos/scripts/deploy-rustup-init.sh -v 1.31.0

# ── Step 3: 通过 harmonybrew 更新已安装的 rustup ──
harmonybrew reinstall rustup-ohos
```

---

## 四、如何通过 rustup 更新工具链

### 更新 Rust 工具链 (rustc / cargo / clippy 等)

```sh
# 安装最新 stable (从本地 dist server 下载)
rustup toolchain install stable

# 设置默认
rustup default stable

# 查看当前版本
rustup show
# 输出:
#   Default host: aarch64-unknown-linux-ohos
#   stable-aarch64-unknown-linux-ohos (default) — rustc 1.96.0

# 查看已安装的所有工具链
rustup toolchain list
```

### 更新 rustup 本体

```sh
# ❌ 以下命令在 OHOS 上禁用:
rustup self update
# → error: self-update is disabled for this build of rustup

# ✅ 正确方式: 通过 harmonybrew 更新
harmonybrew upgrade rustup-ohos
```

**为什么禁用 self-update**: rustup 默认从官方服务器下载新版 rustup-init，但官方二进制没有 OHOS ELF 签名，无法执行 (exit 126)。harmonybrew 在本地编译+签名，确保可执行。

---

## 五、rustup 本体 vs Rust 工具链 — 区别对照

| 概念 | 是什么 | 更新方式 | 来源 |
|------|--------|---------|------|
| **rustup 本体** | 工具链管理器 (`~/.cargo/bin/rustup`) | `harmonybrew upgrade rustup-ohos` | 本地编译+签名 |
| **Rust 工具链** | 编译器+包管理器等 (`~/.rustup/toolchains/stable-*`) | `rustup toolchain install stable` | 本地 dist server |

```
~/.cargo/bin/
├── rustup            ← rustup 本体 (harmonybrew 管理)
├── rustc → rustup    ← 代理命令 (rustup 转发到工具链)
├── cargo → rustup
├── clippy → rustup
└── ...

~/.rustup/toolchains/
└── stable-aarch64-unknown-linux-ohos/   ← Rust 工具链 (rustup install 管理)
    ├── bin/rustc
    ├── bin/cargo
    ├── lib/rustlib/...
    └── ...
```

rustup 本体是一个轻量代理：`rustc`/`cargo`/`clippy` 等命令都是 symlink → rustup → rustup 根据当前 default toolchain 转发到对应二进制。

---

## 六、各组件的更新命令速查

| 操作 | 命令 | 前提 |
|------|------|------|
| 安装 stable 工具链 | `rustup toolchain install stable` | dist server 运行 + manifest 含该版本 |
| 切换默认工具链 | `rustup default stable` | 工具链已安装 |
| 添加组件 | `rustup component add rust-src` | 工具链已安装 |
| 更新 rustup 本体 | `harmonybrew upgrade rustup-ohos` | 新版 formula 可用 |
| 推送新工具链到本地仓 | `build-ohos-dist.sh` + `generate-manifest.sh` + 重启 server | 预编译工具链就绪 |
| 推送新 rustup 到本地仓 | `deploy-rustup-init.sh` | 新版 rustup 编译完成 |
| 新用户一键安装 | `curl http://127.0.0.1:8080/rustup-init.sh | sh` | dist server 运行 + rustup-init 已部署 |
| 局域网 HTTPS 安装 | `curl -k https://IP:8080/rustup-init.sh | sh` | TLS 启用 + BIND_ADDR=0.0.0.0 |

---

## 七、dist server 启停

```sh
# 启动 (HTTP 默认)
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 启动 (HTTPS + 局域网)
TLS_CERT=~/work/ohos-dist-server/certs/server.pem \
TLS_KEY=~/work/ohos-dist-server/certs/server.key \
BIND_ADDR=0.0.0.0 \
bash ~/work/ohos-dist-server/start-dist-server.sh start

# 停止
bash ~/work/ohos-dist-server/start-dist-server.sh stop

# 查看状态
bash ~/work/ohos-dist-server/start-dist-server.sh status
```

**重要**: `rustup toolchain install stable` 和 `curl | sh` 安装都要求 dist server 运行。如果 server 不运行，命令会报 "Connection refused"。

---

## 八、环境变量速查

```sh
# ~/.zshrc 中的关键配置
export RUSTUP_DIST_SERVER=http://127.0.0.1:8080      # 工具链下载源 (替换官方)
export RUSTUP_UPDATE_ROOT=http://127.0.0.1:8080/rustup # rustup-init 安装源 (curl|sh)
export RUST_MIN_STACK=8388608                         # musl 栈大小 8MB (必须)
export LD_LIBRARY_PATH=...                            # 动态库路径 (必须)
export PATH="$HOME/.cargo/bin:$PATH"                  # rustup 代理命令 (必须)
```

| 变量 | 作用 | 必须性 |
|------|------|--------|
| `RUSTUP_DIST_SERVER` | rustup 下载工具链的源 | 必须 |
| `RUSTUP_UPDATE_ROOT` | curl|sh 下载 rustup-init 的源 | 推荐 |
| `RUST_MIN_STACK` | 解决 musl 128KB 栈限制 | 必须 |
| `LD_LIBRARY_PATH` | rustup/rustc 运行时动态库 | 必须 |
