# PVE 管家（pve-pilot）

> [English](README.en.md) · 基于飞牛 OS（fnOS）的 Proxmox VE 远程管理应用

> ⚡ **Vibe Coding 项目**：本项目由 AI 编程助手（Codex CLI）参与开发，人类负责架构决策与代码审查。

通过 FN Connect 穿透链接访问自家 Proxmox VE WebUI——**无公网 IP 也能远程管理**。PVE 管家把 Proxmox VE 的 WebUI 装进飞牛应用商店，一个链接，远程管理。

## 特性

- **零配置上手**：应用中心安装 → 填写 PVE 地址/端口 → 得到可访问链接
- **原版 WebUI 全量透传**：与本地操作完全一致，保留 PVE 自身认证（密码 / 2FA），不保存任何 PVE 凭据
- **FN Connect 穿透**：无公网 IP 也能远程管理
- **轻量内置引擎**：内置静态 nginx 反代引擎（约 5–8MB），零外部依赖
- **安全透明**：PVE 的登录、权限、双因子认证全部由 PVE 自己负责，应用不碰你的凭据

## 使用说明

1. 在飞牛应用中心安装本应用
2. 安装向导填写：**PVE 地址**（IP 或主机名）、**PVE 端口**（默认 8006）、**透传端口**（默认 8800）
3. 打开应用，或访问 `http://<飞牛地址>:8800` / 你的 FN Connect 链接——即进入原版 PVE WebUI

> 提示：透传端口建议保持默认 8800（与 FN Connect 转发声明一致）；如需修改端口，请先确认新端口未被占用。

## 协议

MIT © 2026 pve-pilot
