# PVE 管家 构建系统

| 脚本 | 用途 |
|:--|:--|
| `build-nginx.sh` | 从官方源码静态编译 nginx（x86_64 + aarch64），产物到 `out/`，本机架构同时拷贝到 `fnos/bin/nginx` |
| `package.sh` | 将 `fnos/` 打包为 `.fpk`（tar 手动打包方式），自动写入 `version/platform/checksum` |
| `test/local-verify.sh` | 无飞牛实机时的本地端到端验证（模拟 TRIM_* 环境 + 自签 HTTPS 后端） |
| `gen-icons.py` | 生成应用图标 `ICON.PNG`（90×90）与 `ICON_256.PNG`（256×256） |
| `patches/` | 交叉编译 nginx 所需的 configure 补丁（sizeof / 字节序检测降级） |

## 快速开始

```bash
./build-nginx.sh --arch x86       # 仅建议用于验证配置/语法（见下）
./package.sh --arch x86 --dry-run # 仅校验打包清单，不产出 .fpk
./test/local-verify.sh            # 本地验证（需本机架构二进制）
```

> **编译与打包默认走 GitHub Actions（ADR-006）**：push 到 `main` / push `v*` tag /
> 手动 `workflow_dispatch` 都会触发 `.github/workflows/build.yml`，在
> ubuntu-latest 上以矩阵方式编译 x86_64 / aarch64 静态 nginx 并产出
> `build/dist/pvepilot_<version>_<arch>.fpk` artifact。本地（CT 105）不保留
> 交叉编译工具链、不做长时间编译。

## 版本覆盖

默认 nginx 1.28.3（最新稳定 1.28.x）、OpenSSL 3.6.3（LTS 线）、PCRE2 10.46
（供 `proxy_cookie_flags ~` 正则）。可用环境变量覆盖：

```bash
NGINX_VERSION=1.28.2 OPENSSL_VERSION=3.5.7 PCRE2_VERSION=10.45 \
  ./build-nginx.sh --arch x86
```

## 交叉编译说明

arm 产物在 x86 主机上通过 `gcc-aarch64-linux-gnu` 交叉编译：

1. nginx configure 的“运行型”特性检测被降级为“仅编译”（`patches/` 与 `sed` 补丁）；
2. 类型大小/字节序按 Linux LP64 小端约定取值（aarch64/x86_64 均成立）；
3. OpenSSL 通过 `CROSS_COMPILE` 环境变量交叉构建，`--with-openssl-opt="linux-aarch64 no-asm"`；
4. PCRE2 由 nginx 构建系统以 `--host=aarch64-linux-gnu` 交叉编译（脚本自动补丁，
   否则 autoconf 运行型检测在 x86 主机上会失败）；
5. 产物为全静态二进制（`ldd` 显示非动态可执行文件），可用 `qemu-aarch64-static` 在本机直接运行验证。
