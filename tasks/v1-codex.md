# PVE 管家 V1 — Codex 任务书

> 派发日期：2026-08-02 ｜ 状态：待执行 ｜ 工作机：CT 105（Ubuntu 24.04）

## 1. 项目背景

PVE 管家（pve-pilot）是一个飞牛 fnOS 应用：让飞牛用户通过 FN Connect 穿透链接访问自家
Proxmox VE 的 WebUI，无公网 IP 也能远程管理。MIT 协议，单仓库规划（backend/frontend/fnos-app/docs）。

**V1（MVP）目标**：用户装应用 → 填 PVE 地址 → 得到可访问链接 → PC 打开是原版 PVE WebUI（保留 PVE 自身认证）。

## 2. 交付物（本次任务）

在 `/root/projects/pve-pilot/` 下完成：

1. `fnos/` — fnOS 应用完整目录（见 §4 结构），产出可手动安装的 `.fpk`
2. `build/` — nginx 静态二进制构建脚本（x86_64 + aarch64）
3. `docs/` 已存在（00-04），本次补充 README.md（仓库根，中英双语，中文名 PVE 管家）
4. 本地验证记录（在无飞牛实机时可做的部分：nginx -t、脚本 dry-run）

## 3. 核心设计决策（已定稿，勿改）

| 决策 | 内容 |
|:--|:--|
| 形态 | 纯配置型：内置 nginx 反代引擎 + fnOS 原生向导 + 生命周期脚本，**无自研长驻进程** |
| 反代 | 内置静态 nginx（~5MB），无管理界面；不依赖任何商店反代应用 |
| 透传 | 根路径全量透传（PVE 不支持子目录），独立端口（默认 8800） |
| 认证 | PVE 自身认证（密码/2FA），应用不存任何 PVE 凭据 |
| 语言 | 中文界面，i18n 预留 |

## 4. fnOS 应用结构（目标）

```
pve-pilot/fnos/
├── manifest              # appname=pvepilot, service_port=8800, platform=x86|arm
├── pvepilot.sc           # port_forward=yes, src/dst ports=8800/tcp
├── ICON.PNG / ICON_256.PNG
├── bin/nginx             # 静态 nginx（构建产物）
├── conf/mime.types
├── cmd/
│   ├── install_callback  # 生成透传配置（读 wizard 输入）
│   ├── config_callback   # 重写配置 + 重启
│   ├── main              # 启动 nginx（daemon off）
│   ├── uninstall_callback
│   └── (install_init / upgrade_init 按需)
├── wizard/
│   ├── install           # 表单：PVE 地址 / PVE 端口 / 透传端口
│   └── config            # 同上（改配置）
└── var/                  # 运行时动态生成：nginx.conf + logs/（不入 fpk）
```

**fnOS 生命周期脚本环境变量**（关键，勿凭猜测）：
- `TRIM_APPDEST` — 应用安装目录（target，只读）
- `TRIM_PKGVAR` — 应用数据目录（var，可写，运行时 nginx.conf 放这）
- `TRIM_APPNAME` — 应用标识
- 系统目录规则：`/var/apps/<appname>/` 下 `cmd/`（脚本）、`var -> /vol[x]/@appdata/<appname>`、
  `target -> /vol[x]/@appcenter/<appname>`、`etc -> /vol[x]/@appconf/<appname>`
- 参考实现：conversun/fnos-apps 的 `apps/nginx/fnos/bin/nginx-server`（用 TRIM_PKGVAR 存 conf、
  `exec ./sbin/nginx -c <conf> -g "daemon off;"` 前台跑，脚本模式可直接借鉴）

## 5. 透传配置模板（核心，全部要点已查证）

```nginx
server {
    listen       8800;                          # 透传端口（向导可改，冲突检测）
    server_name  _;
    location / {
        proxy_pass        https://<PVE地址>:<PVE端口>;   # 默认 192.168.8.10:8006
        proxy_set_header  Host $host;                  # 必须透传，PVE 靠 Host 拼 URL
        proxy_http_version 1.1;
        proxy_set_header  Upgrade $http_upgrade;       # noVNC/控制台/日志 websocket
        proxy_set_header  Connection "upgrade";
        proxy_buffering   off;                         # 长连接必需
        client_max_body_size 0;                        # 上传 ISO/备份不设限
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_ssl_verify  off;                         # PVE 自签证书，后端不校验证书
    }
}
```

三个硬约束（勿改）：
1. 根路径透传（PVE 硬编码根路径，不支持子目录）
2. Host 头必须透传（否则登录后白屏/重定向循环）
3. `proxy_ssl_verify off`（PVE 8006 是自签 https，nginx 后端不校验证书；浏览器→飞牛 的证书由 FN Connect 的 fnos.net 域名提供）

配置生成方式：install_callback 按 wizard 输入生成 `$TRIM_PKGVAR/nginx.conf`
（worker/events/http 骨架 + 上述 server 块），`main` 脚本 exec nginx 前台运行。

## 6. manifest 关键字段（参考 conversun nginx 应用）

```
appname = pvepilot
version = 0.1.0
display_name = PVE 管家
service_port = 8800
checkport = false
platform = x86|arm        # 按实际打包架构
maintainer / maintainer_url / distributor / distributor_url
desktop_uidir = ui
desktop_applaunchname = pvepilot.Application
desc = 通过 FN Connect 远程管理 Proxmox VE
source = thirdparty
checksum = <md5(app.tgz)>
```

`.sc`：
```
[pvepilot]
title="PVE 管家"
desc="PVE 管家 Service"
port_forward="yes"
src.ports="8800/tcp"
dst.ports="8800/tcp"
```

## 7. nginx 静态构建

- 目标：静态 nginx（x86_64 + aarch64），带 `http_proxy_module`、`http_ssl_module`、`stream_module`（可选）
- 参考：conversun/fnos-apps `apps/nginx/update_nginx.sh`（官方源码 + 静态编译，可借鉴其 configure 参数）
- 产物：`build/out/nginx-x86_64`、`build/out/nginx-aarch64`，strip 后拷贝到 `fnos/bin/`
- 版本：nginx 最新稳定版（1.28.x）
- 本机无网下载受限时在 CT 105 编译（N100 编译 nginx 静态包约几分钟）

## 8. 验收标准

1. `fnos/` 结构完整，`fnpack`（或 tar 手动打包）能产出 `.fpk` 且 manifest 字段合法
2. `bin/nginx -t -c <生成的conf>` 通过（本地可验）
3. 生成的 nginx.conf 包含 §5 全部要点（逐项核对）
4. install/config wizard 字段与 §6/§4 一致，config_callback 能重写配置并重启服务
5. 代码/脚本有注释，关键路径中文注释（团队协作惯例）
6. 不动 `docs/00-04` 已有内容（只读参考）

## 9. 已知边界

- 飞牛实机验证（应用中心安装/打开按钮/FN Connect 穿透）不在本次范围，需用户实机测试
- GitHub 仓库尚未创建（用户 gh 认证后建），本次先在本地目录开发，git init 即可
- fnOS 官方文档：developer.fnnas.com（可参考）；conversun/fnos-apps 仓库有完整示例应用
