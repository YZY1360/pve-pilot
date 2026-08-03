#!/bin/bash
# ============================================================================
# PVE 管家（pve-pilot）— nginx 静态二进制构建脚本
# ----------------------------------------------------------------------------
# 目标：
#   - 官方源码（nginx.org）编译，静态链接 PCRE2 / OpenSSL 等第三方库
#   - 产物：build/out/nginx-x86_64、build/out/nginx-aarch64（strip 后）
#   - 原生架构（本机为 x86_64）同时拷贝到 fnos/bin/nginx（仓库默认产物）
#
# 模块取舍（对应任务书 §7）：
#   - 启用：http_proxy_module（默认）、http_ssl_module、stream_module(+ssl)、
#     http_sub_module（0.1.7 起 http 直连时改写 PVE 前端 JS 的 Secure cookie 写入，
#     sub_filter 精确字节匹配）、PCRE2（供 proxy_cookie_flags ~ 正则匹配，
#     透传时剥离服务端 Set-Cookie 的 Secure 标志）
#   - 关闭：rewrite（保留 pcre2 但不用 rewrite 模块）、gzip（省 zlib）及其余
#     用不到的内容模块，以控制二进制体积（目标 ~5MB）
#
# 用法：
#   ./build/build-nginx.sh [--arch x86|arm|both] [--cache-dir DIR] [-v 1.28.3]
# 环境变量：NGINX_VERSION / OPENSSL_VERSION / PCRE2_VERSION 可覆盖版本
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build"
OUT_DIR="${BUILD_DIR}/out"

NGINX_VERSION="${NGINX_VERSION:-1.28.3}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.3}"
PCRE2_VERSION="${PCRE2_VERSION:-10.47}"

NGINX_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
PCRE2_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz"

# 模块裁剪：保留 proxy/ssl/stream，去掉用不到的内容模块
CONFIGURE_MODULE_OPTS=(
    --with-http_ssl_module
    --with-http_sub_module
    --with-stream
    --with-stream_ssl_module
    --with-pcre
    --without-http_rewrite_module
    --without-http_gzip_module
    --without-http_ssi_module
    --without-http_userid_module
    --without-http_autoindex_module
    --without-http_geo_module
    --without-http_memcached_module
    --without-http_empty_gif_module
    --without-http_fastcgi_module
    --without-http_uwsgi_module
    --without-http_scgi_module
    --without-http_grpc_module
    --without-http_split_clients_module
    --without-http_referer_module
    --without-http_mirror_module
)

# 默认按本机架构构建
HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
    x86_64|amd64) HOST_ARCH_TAG="x86" ;;
    aarch64|arm64) HOST_ARCH_TAG="arm" ;;
    *) echo "不支持的主机架构: ${HOST_ARCH}（可用 --arch 指定）" >&2; exit 1 ;;
esac

CACHE_DIR="${CACHE_DIR:-${BUILD_DIR}/cache}"
ARCH=""

usage() {
    cat <<EOF
用法: $0 [选项]

选项:
  --arch x86|arm|both   目标架构（默认: ${HOST_ARCH_TAG}）
  --cache-dir DIR       源码缓存目录（默认: build/cache）
  -h, --help            显示帮助

环境变量:
  NGINX_VERSION          nginx 版本（默认 ${NGINX_VERSION}）
  OPENSSL_VERSION        OpenSSL 版本（默认 ${OPENSSL_VERSION}）
  PCRE2_VERSION          PCRE2 版本（默认 ${PCRE2_VERSION}）
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --arch=*) ARCH="${1#*=}"; shift ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知选项: $1" >&2; usage; exit 1 ;;
    esac
done
[ -n "${ARCH}" ] || ARCH="${HOST_ARCH_TAG}"
case "${ARCH}" in
    x86|arm|both) ;;
    *) echo "无效架构: ${ARCH}（可选 x86 / arm / both）" >&2; exit 1 ;;
esac

mkdir -p "${OUT_DIR}" "${CACHE_DIR}"

# ---- 下载并解压源码（带缓存，避免重复下载）----------------------------------
fetch_extract() {
    local url="$1" name="$2" dest="$3"
    local archive="${CACHE_DIR}/${name}.tar.gz"
    if [ ! -f "${archive}" ]; then
        echo "[INFO] 下载 ${url}"
        curl -fsSL -o "${archive}" "${url}"
    else
        echo "[INFO] 使用缓存 ${archive}"
    fi
    rm -rf "${dest}"
    mkdir -p "${dest}"
    tar xzf "${archive}" -C "${dest}" --strip-components=1
}

# ---- 单架构构建 --------------------------------------------------------------
build_arch() {
    local arch="$1"
    local cc="" openssl_opt="" cross_prefix=""
    local openssl_opt_args=() cross_opt_args=()
    local out_name

    case "${arch}" in
        x86)
            cc="gcc"
            out_name="nginx-x86_64"
            ;;
        arm)
            cc="aarch64-linux-gnu-gcc"
            openssl_opt="linux-aarch64 no-asm"
            cross_prefix="aarch64-linux-gnu-"
            out_name="nginx-aarch64"
            ;;
    esac

    if ! command -v "${cc}" >/dev/null 2>&1; then
        echo "[ERROR] 缺少编译器 ${cc}（arm 交叉编译请安装 gcc-aarch64-linux-gnu）" >&2
        exit 1
    fi

    echo "============================================================"
    echo "  构建 nginx ${NGINX_VERSION} + OpenSSL ${OPENSSL_VERSION} [${arch}]"
    echo "============================================================"

    local work="${BUILD_DIR}/work-${arch}"
    rm -rf "${work}"
    mkdir -p "${work}"
    # 编译临时文件放到构建目录内（部分沙箱环境 /tmp 并发临时文件不稳定）
    export TMPDIR="${work}/tmp"
    mkdir -p "${TMPDIR}"

    local nginx_src="${work}/nginx-src"
    local openssl_src="${work}/openssl-src"
    local pcre2_src="${work}/pcre2-src"
    fetch_extract "${NGINX_URL}" "nginx-${NGINX_VERSION}" "${nginx_src}"
    fetch_extract "${OPENSSL_URL}" "openssl-${OPENSSL_VERSION}" "${openssl_src}"
    fetch_extract "${PCRE2_URL}" "pcre2-${PCRE2_VERSION}" "${pcre2_src}"

    # mime.types 随源码同步到应用 conf/（仓库内静态文件，供打包使用）
    cp -f "${nginx_src}/conf/mime.types" "${ROOT}/fnos/conf/mime.types"

    cd "${nginx_src}"
    # 交叉编译补丁：configure 的若干特性检测需要"编译后运行测试程序"，
    # 在 x86 主机上无法直接运行 aarch64 二进制（无 binfmt 时）。统一降级为
    # "仅编译检测"——Linux/aarch64 目标系统与编译机共享同代内核特性，安全。
    if [ -n "${cross_prefix}" ]; then
        export PVE_NGINX_CROSS=1
        sed -i 's/ngx_feature_run=yes/ngx_feature_run=no/g' \
            auto/cc/name \
            auto/cc/conf \
            auto/unix \
            auto/os/linux \
            auto/lib/libatomic/conf 2>/dev/null || true
        # sizeof 检测补丁：交叉编译时无法运行目标二进制，用 __SIZEOF_* 宏推导
        patch -p1 -s < "${ROOT}/build/patches/nginx-cross-sizeof.patch" || {
            echo "[ERROR] sizeof 交叉补丁应用失败" >&2
            exit 1
        }
        # 字节序检测补丁：aarch64/x86_64 均为小端
        patch -p1 -s < "${ROOT}/build/patches/nginx-cross-endianness.patch" || {
            echo "[ERROR] endianness 交叉补丁应用失败" >&2
            exit 1
        }
        # PCRE2 交叉构建：nginx 生成的 pcre 构建规则不传 --host，
        # autoconf 会尝试运行 aarch64 测试程序导致 configure 失败，这里补上
        sed -i 's#\./configure --disable-shared #./configure --host='"${cross_prefix%-}"' --disable-shared #g' \
            auto/lib/pcre/make
    else
        export PVE_NGINX_CROSS=0
    fi

    # 仅在有值时传入（避免空参数）
    [ -n "${openssl_opt}" ] && openssl_opt_args=(--with-openssl-opt="${openssl_opt}")
    [ -n "${cross_prefix}" ] && cross_opt_args=(--crossbuild=Linux:aarch64)
    ./configure \
        --prefix=/usr/local/nginx \
        --with-cc="${cc}" \
        --with-cc-opt="-O2" \
        --with-ld-opt="-static" \
        --with-openssl="${openssl_src}" \
        --with-pcre="${pcre2_src}" \
        "${openssl_opt_args[@]}" \
        "${cross_opt_args[@]}" \
        "${CONFIGURE_MODULE_OPTS[@]}"

    # 交叉编译时 CROSS_COMPILE 环境变量传递给 OpenSSL 的 configure/make；
    # 首次失败（沙箱并发临时文件问题）自动降级 -j1 重试一次
    local make_attempts=(0 1)
    local make_ok=0
    for attempt in "${make_attempts[@]}"; do
        if [ -n "${cross_prefix}" ]; then
            if CROSS_COMPILE="${cross_prefix}" make -j"$(nproc)" \
                || CROSS_COMPILE="${cross_prefix}" make -j1; then
                make_ok=1
                break
            fi
        else
            if make -j"$(nproc)" || make -j1; then
                make_ok=1
                break
            fi
        fi
        [ "${attempt}" -eq 0 ] && echo "[WARN] 并行构建失败，重试单核构建..." >&2
    done
    [ "${make_ok}" -eq 1 ] || { echo "[ERROR] make 构建失败" >&2; exit 1; }

    local bin="${work}/nginx-src/objs/nginx"
    [ -f "${bin}" ] || { echo "[ERROR] 未找到构建产物 objs/nginx" >&2; exit 1; }

    # strip 并输出到 build/out/
    cp -f "${bin}" "${OUT_DIR}/${out_name}"
    # 交叉编译时使用目标架构的 strip（宿主 strip 无法处理 aarch64 二进制）
    local strip_tool="strip"
    [ -n "${cross_prefix}" ] && strip_tool="${cross_prefix}strip"
    "${strip_tool}" --strip-unneeded "${OUT_DIR}/${out_name}" 2>/dev/null \
        || "${strip_tool}" "${OUT_DIR}/${out_name}"
    echo "[INFO] 产物: ${OUT_DIR}/${out_name} ($(du -h "${OUT_DIR}/${out_name}" | cut -f1))"

    # 原生架构产物同时放入 fnos/bin/nginx（仓库默认应用二进制）
    if [ "${arch}" = "${HOST_ARCH_TAG}" ]; then
        mkdir -p "${ROOT}/fnos/bin"
        cp -f "${OUT_DIR}/${out_name}" "${ROOT}/fnos/bin/nginx"
        chmod +x "${ROOT}/fnos/bin/nginx"
        echo "[INFO] 已拷贝到 fnos/bin/nginx"
    fi
}

case "${ARCH}" in
    both)
        build_arch x86
        build_arch arm
        ;;
    *)
        build_arch "${ARCH}"
        ;;
esac

echo "[INFO] 全部构建完成。"
