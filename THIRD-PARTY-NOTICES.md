# Third-Party Notices

PVE 管家（pve-pilot）以 MIT 许可开源（见 [LICENSE](LICENSE)）。项目分发物
（`.fpk` 与静态 nginx 二进制）内包含下列第三方组件的代码与二进制，特此声明
其版权与许可信息。

| 组件 | 版本 | 许可 | 使用方式 |
|:--|:--|:--|:--|
| nginx | 1.28.3 | BSD-2-Clause | 静态编译进 `bin/nginx`（反向代理引擎） |
| OpenSSL | 3.6.3 | Apache-2.0 | 静态链接进 `bin/nginx`（HTTPS/TLS） |
| PCRE2 | 10.47 | BSD-3-Clause WITH PCRE2-exception | 静态链接进 `bin/nginx`（`proxy_cookie_flags ~` 正则匹配） |
| FNOSP fnmake | main | MIT | fnOS 应用结构/打包流程参考 |

## nginx — BSD-2-Clause

- 官网：<https://nginx.org>
- 版本：1.28.3（官方源码编译）
- 版权：Copyright (C) 2002-2021 Igor Sysoev；Copyright (C) 2011-2025 Nginx, Inc.
- 用途：pve-pilot 内置的反向代理引擎，以"daemon off"前台方式运行。
- 许可摘要（BSD 2-Clause）：允许以源代码或二进制形式再分发，条件是在源码
  分发中保留上述版权声明与本条件列表，并在二进制分发随附的文档/材料中复现
  上述版权声明。完整条款见 nginx 源码中的 [LICENSE](https://raw.githubusercontent.com/nginx/nginx/release-1.28.3/LICENSE)。

## OpenSSL — Apache-2.0

- 官网：<https://www.openssl.org>
- 版本：3.6.3（官方源码编译）
- 版权：Copyright © 1999-2026 The OpenSSL Project Authors（详见 LICENSE.txt）
- 用途：为 nginx 提供 TLS/HTTPS 支持（PVE 后端为 HTTPS）。
- 许可摘要（Apache License 2.0）：授予版权与专利许可，允许自由使用、复制、
  修改与再分发；再分发须保留本声明并在修改文件上显著标注；如基于本软件提起
  专利诉讼，相关许可自动终止。完整条款见 OpenSSL 源码中的 [LICENSE.txt](https://raw.githubusercontent.com/openssl/openssl/openssl-3.6.3/LICENSE.txt)。

## PCRE2 — BSD-3-Clause WITH PCRE2-exception

- 官网：<https://github.com/PCRE2Project/pcre2>
- 版本：10.47（官方源码编译）
- 版权：Copyright (c) 1997-2007 University of Cambridge；Copyright (c) 2007-2024
  Philip Hazel；JIT 编译支持 Copyright (c) 2009-2024 Zoltan Herczeg
- 用途：提供正则表达式匹配（`proxy_cookie_flags ~` 剥离 Secure cookie 标志）。
- 许可摘要（BSD 3-Clause + PCRE2-exception）：允许以源代码或二进制形式再分发，
  保留版权声明、条件列表与免责声明，且不得使用版权方名义背书；同时授予一项
  二进制再分发例外，允许不附带完整源代码即可随程序分发编译后的 PCRE2 库。
  完整条款见 PCRE2 源码中的 [LICENCE](https://raw.githubusercontent.com/PCRE2Project/pcre2/pcre2-10.47/LICENCE.md)。

## FNOSP fnmake — MIT

- 仓库：<https://github.com/FNOSP/fnmake>
- 版权：Copyright (c) 2026 飞牛开发者开放平台
- 用途：参考其 fnOS 应用目录结构与构建/打包流程约定（非代码复用）。
- 许可摘要（MIT）：允许自由使用、复制、修改、合并、出版、分发、再许可与销售，
  条件是保留上述版权声明与许可声明。完整条款见 [fnmake LICENSE](https://raw.githubusercontent.com/FNOSP/fnmake/main/LICENSE)。
