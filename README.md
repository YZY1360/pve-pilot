# PVE 管家（pve-pilot）

> [English](README.en.md) · 基于飞牛 OS（fnOS）的 Proxmox VE 远程管理应用

通过 FN Connect 穿透链接访问自家 Proxmox VE WebUI——**无公网 IP 也能远程管理**。V1（MVP）为 PC 端原版 WebUI 全量透传。

PVE 管家把 Proxmox VE 的 WebUI 装进飞牛应用商店——一个链接，远程管理。应用内置静态 nginx 反代引擎（约 5–8MB，无管理界面），通过 fnOS 原生向导填写 PVE 地址后即可访问。

## 特性（V1）

- **零配置上手**：应用中心安装 → 填写 PVE 地址/端口 → 得到可访问链接
- **原版 WebUI 全量透传**：根路径透传，保留 PVE 自身认证（密码 / 2FA），不保存任何 PVE 凭据
- **FN Connect 穿透**：应用声明端口（`pvepilot.sc`），无公网 IP 也能远程管理
- **内置反代引擎**：打包静态 nginx（`http_proxy` / `http_ssl` / `stream`），零外部依赖
- **纯配置型**：无自研长驻进程，配置由安装/配置向导生成，生命周期由 fnOS 管理

## 目录结构

```
pve-pilot/
├── fnos/            # fnOS 应用（manifest / 向导 / 生命周期脚本 / 图标 / 配置模板）
├── build/           # nginx 静态编译脚本 + .fpk 打包脚本 + 本地验证脚本
├── docs/            # 设计文档（00-04）
└── tasks/           # 开发任务书
```

## 构建与打包

```bash
# 1. 编译静态 nginx（x86_64 + aarch64，产物在 build/out/，x86 同时拷贝到 fnos/bin/）
./build/build-nginx.sh --arch both

# 2. 生成应用图标（90/256，仓库内已生成，可复现）
python3 build/gen-icons.py

# 3. 打包 .fpk（按架构分别产出，自动更新 manifest 的 platform/checksum）
./build/package.sh --arch both
# 产物：build/dist/pvepilot_<version>_<arch>.fpk
```

依赖：`gcc` / `gcc-aarch64-linux-gnu`（arm 交叉编译）、`curl`、`tar`、`patch`。
OpenSSL 从源码静态编译（默认 3.6.x LTS），nginx 默认 1.28.x 稳定版，可用环境变量覆盖。

## 本地验证

无需飞牛实机，可运行端到端本地验证（自签 HTTPS 后端模拟 PVE 8006）：

```bash
./build/test/local-verify.sh
```

覆盖：install_callback 配置生成、§5 透传要点逐项核对、`nginx -t`、真实启动后的
Host 头透传、config_callback 重写配置并重启、stop/restart/status/log。

## 使用说明

1. 在飞牛应用中心手动安装 `build/dist/` 下的 `.fpk`
2. 安装向导填写：PVE 地址（IP 或主机名）、PVE 端口（默认 8006）、透传端口（默认 8800）
3. 打开应用（或访问 `http://<飞牛地址>:8800` / FN Connect 链接），即进入原版 PVE WebUI

> 提示：透传端口建议保持 8800，与 `.sc` 声明的 FN Connect 转发端口一致；
> 修改端口后本地访问使用新端口，FN Connect 转发仍以 `.sc` 声明为准（待实机验证）。

## 设计约束（勿改）

1. 根路径全量透传（PVE 硬编码根路径，不支持子目录）
2. Host 头必须透传（否则登录后白屏/重定向循环）
3. `proxy_ssl_verify off`（PVE 8006 为自签 HTTPS，后端不校验证书；浏览器→飞牛 段
   由 FN Connect 的 fnos.net 证书提供）

详见 [docs/04-设计.md](docs/04-设计.md) 与任务书 `tasks/v1-codex.md`。

## 协议

MIT © 2026 pve-pilot
