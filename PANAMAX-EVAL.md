# Panamax 升级路径评估

## 结论: 当前 MVP 足够，Panamax 可作为 Phase 3 后的长期方案

## Panamax 概述

Panamax (v1.0.14) 是 Rust 社区的 rustup + crates.io 镜像工具，自带 warp HTTP 服务器。
- GitHub: https://github.com/panamax-rs/panamax
- 用途: 离线/私有 Rust 工具链分发

## OHOS 上的可行性评估

| 依赖 | 风险 | 说明 |
|------|------|------|
| git2 0.16 (libgit2 C) | **高** | 需 libgit2 系统库或从 bundled C 编译，OHOS musl 下非 trivial |
| reqwest 0.11 | 中 | 有 vendored-openssl feature |
| warp + tokio | 低 | 纯 Rust，可正常编译 |
| askama | 低 | 编译时模板 |

**主要障碍**: git2 依赖用于 crates.io-index git 操作。若仅做 rustup 镜像（不需要 crates.io），需 patch 剔除 git2，但 Panamax 无 `--no-default-features` feature gate。

**无 post-sync hook**: Panamax 不支持自定义钩子。替代方案: 包装 shell 脚本在 `panamax sync` 后对 ELF 文件执行 `binary-sign-tool`。

## 当前 MVP vs Panamax 对比

| 特性 | Python http.server MVP | Panamax |
|------|----------------------|---------|
| 复杂度 | 极低 | 高 |
| OHOS 编译 | 不需要 | 需要 patch git2 |
| 自动同步上游 | 手动 | 自动 |
| 多版本支持 | 单版本 | 多版本 |
| TLS 支持 | 无 | warp 内置 |
| crates.io 镜像 | 无 | 有 |
| 签名集成 | build-ohos-dist.sh 内 | 需外部 wrapper |

## 推荐路径

### 短期（当前）: 保持 MVP

Python http.server + build-ohos-dist.sh 组合已验证完整功能：
- `rustup toolchain install stable` 成功
- 所有 5 个 default profile 组件正常安装
- rust-src / rust-analyzer 作为 extension 可单独添加
- minimal / default / complete profile 全部验证

新版本发布时只需:
1. 更新 `build-ohos-dist.sh` 中的 `VERSION` 和 `TOOLCHAIN_DIR`
2. 运行脚本重建 tarballs
3. 更新 `channel-rust-stable.toml` hashes

### 中期: 静态下载器 + warp 服务器

替代 Panamax 的轻量方案:
1. 用 Rust 编写简易下载器，从 static.rust-lang.org 同步指定 platform 的组件 tarball
2. 下载后自动签名 + 计算 hash
3. 生成 manifest.toml
4. warp HTTP server 替代 Python http.server
5. 纯 Rust，无 C 依赖，可直接编译为 aarch64-unknown-linux-ohos

### 长期（Phase 3 后）: Panamax 全功能

当 OHOS 成为 rustup 上游支持 target 后:
1. Panamax 可直接从 crates.io 安装（不再需要本地编译）
2. 配置 `mirror.toml`: `platforms_unix = ["aarch64-unknown-linux-ohos"]`
3. 用 wrapper 脚本集成 binary-sign-tool 签名
4. 同时提供 crates.io 镜像，完整覆盖 Rust 开发工具链

## Panamax 配置模板（未来使用）

```toml
[rustup]
sync = true
platforms_unix = ["aarch64-unknown-linux-ohos"]
keep_latest_stables = 2

[crates]
sync = true
```

运行:
```bash
panamax sync  # 同步上游
# 签名所有新 ELF 文件
find ~/.panamax/rustup/dist/ -type f | while read f; do
    file "$f" | grep -q "ELF" && binary-sign-tool sign -selfSign 1 -signAlg SHA256withECDSA -inFile "$f" -outFile "${f}.signed" && mv "${f}.signed" "$f" && chmod +x "$f"
done
panamax serve  # 启动 warp 服务器 (端口 8080)
```
