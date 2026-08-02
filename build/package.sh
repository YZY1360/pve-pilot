#!/bin/bash
# ============================================================================
# PVE 管家（pve-pilot）— .fpk 打包脚本（tar 手动打包方式）
# ----------------------------------------------------------------------------
# 依据任务书 §6/§7 与 conversun build-fpk.sh 的包结构（自包含实现）：
#
#   pvepilot_<version>_<arch>.fpk （tar.gz）
#   ├── manifest          # version/platform/checksum 由本脚本按目标写入
#   ├── pvepilot.sc
#   ├── ICON.PNG / ICON_256.PNG
#   ├── ui/               # ui/config + ui/images/256.png（由 ICON_256 生成）
#   ├── config/           # privilege / resource
#   ├── wizard/           # install / config
#   ├── cmd/              # common/installer/main/service-setup + 生命周期回调
#   └── app.tgz           # bin/nginx + conf/mime.types + ui/
#
# 用法：
#   ./build/package.sh [--arch x86|arm|both] [--version X.Y.Z] [--nginx PATH] [--dry-run]
# 产物：build/dist/pvepilot_<version>_<arch>.fpk
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FNOS_DIR="${ROOT}/fnos"
OUT_DIR="${ROOT}/build/dist"

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
    x86_64|amd64) HOST_ARCH_TAG="x86" ;;
    aarch64|arm64) HOST_ARCH_TAG="arm" ;;
    *) HOST_ARCH_TAG="" ;;
esac

ARCH=""
VERSION=""
NGINX_BIN_OVERRIDE=""
DRY_RUN=0

usage() {
    cat <<EOF
用法: $0 [选项]

选项:
  --arch x86|arm|both   目标架构（默认: ${HOST_ARCH_TAG:-检测不到，必填}）
  --version X.Y.Z       版本号（默认读 manifest 中 version）
  --nginx PATH          指定 nginx 二进制（默认: fnos/bin/nginx；arm 默认 build/out/nginx-aarch64）
  --dry-run             只做校验与打印，不产出 .fpk
  -h, --help            显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) ARCH="$2"; shift 2 ;;
        --arch=*) ARCH="${1#*=}"; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --nginx) NGINX_BIN_OVERRIDE="$2"; shift 2 ;;
        --nginx=*) NGINX_BIN_OVERRIDE="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知选项: $1" >&2; usage; exit 1 ;;
    esac
done

[ -n "${ARCH}" ] || ARCH="${HOST_ARCH_TAG:-}"
case "${ARCH}" in
    x86|arm) ;;
    both)
        # 分别打包两个架构（透传 --dry-run）
        EXTRA=()
        [ "${DRY_RUN}" -eq 1 ] && EXTRA+=(--dry-run)
        [ -n "${VERSION}" ] && EXTRA+=(--version "${VERSION}")
        "$0" --arch x86 "${EXTRA[@]}"
        "$0" --arch arm "${EXTRA[@]}"
        exit 0
        ;;
    *)
        echo "无效/缺失架构: ${ARCH}（可选 x86 / arm / both）" >&2
        exit 1
        ;;
esac

MANIFEST_VERSION="$(grep '^version' "${FNOS_DIR}/manifest" | awk -F= '{print $2}' | tr -d ' ')"
VERSION="${VERSION:-${MANIFEST_VERSION}}"

# 默认二进制：x86 用 fnos/bin/nginx（仓库默认产物），arm 用 build/out/nginx-aarch64
case "${ARCH}" in
    x86) DEFAULT_NGINX="${ROOT}/fnos/bin/nginx" ;;
    arm) DEFAULT_NGINX="${ROOT}/build/out/nginx-aarch64" ;;
esac
NGINX_BIN="${NGINX_BIN_OVERRIDE:-${DEFAULT_NGINX}}"

echo "============================================================"
echo "  PVE 管家 .fpk 打包  version=${VERSION} arch=${ARCH}"
echo "  nginx 二进制: ${NGINX_BIN}"
echo "============================================================"

# ---- 校验清单 ---------------------------------------------------------------
check() {
    [ -e "$1" ] || { echo "[ERROR] 缺少: $1" >&2; exit 1; }
}
check "${FNOS_DIR}/manifest"
check "${FNOS_DIR}/pvepilot.sc"
check "${FNOS_DIR}/ICON.PNG"
check "${FNOS_DIR}/ICON_256.PNG"
check "${FNOS_DIR}/cmd/common"
check "${FNOS_DIR}/cmd/installer"
check "${FNOS_DIR}/cmd/main"
check "${FNOS_DIR}/cmd/service-setup"
check "${FNOS_DIR}/cmd/install_callback"
check "${FNOS_DIR}/cmd/config_callback"
check "${FNOS_DIR}/cmd/uninstall_callback"
check "${FNOS_DIR}/wizard/install"
check "${FNOS_DIR}/wizard/config"
check "${FNOS_DIR}/ui/config"
check "${FNOS_DIR}/config/privilege"
check "${FNOS_DIR}/config/resource"
check "${NGINX_BIN}"

# 校验 nginx 二进制架构与目标匹配
BIN_ARCH="$(file -b "${NGINX_BIN}" | grep -oE 'x86-64|aarch64' | head -1)"
EXPECTED="x86-64"; [ "${ARCH}" = "arm" ] && EXPECTED="aarch64"
if [ "${BIN_ARCH}" != "${EXPECTED}" ]; then
    echo "[ERROR] nginx 二进制架构不匹配: 期望 ${EXPECTED}，实际 ${BIN_ARCH}（${NGINX_BIN}）" >&2
    exit 1
fi

# manifest 必备字段校验（对应任务书 §6）
for key in appname version display_name service_port checkport platform \
           maintainer maintainer_url distributor distributor_url \
           desktop_uidir desktop_applaunchname desc source checksum; do
    grep -q "^${key}[[:space:]]*=" "${FNOS_DIR}/manifest" \
        || { echo "[ERROR] manifest 缺少字段: ${key}" >&2; exit 1; }
done

# ---- 组装 app.tgz（运行时本体：bin/nginx + conf/mime.types + ui）-------------
TMP="$(mktemp -d /tmp/pvepilot-pkg.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT
APP_ROOT="${TMP}/app_root"
PKG_ROOT="${TMP}/pkg"
mkdir -p "${APP_ROOT}/bin" "${APP_ROOT}/conf" "${APP_ROOT}/ui"

cp -f "${NGINX_BIN}" "${APP_ROOT}/bin/nginx"
cp -f "${FNOS_DIR}/conf/mime.types" "${APP_ROOT}/conf/mime.types"
cp -a "${FNOS_DIR}/ui/." "${APP_ROOT}/ui/"
chmod +x "${APP_ROOT}/bin/nginx"

APP_TGZ="${TMP}/app.tgz"
# 与 conversun build-fpk.sh 一致：不带 "./" 前缀打包，便于 fnOS 解析
(cd "${APP_ROOT}" && tar -czf "${APP_TGZ}" *)
CHECKSUM="$(md5sum "${APP_TGZ}" | cut -d' ' -f1)"
echo "[INFO] app.tgz: $(du -h "${APP_TGZ}" | cut -f1)，checksum=${CHECKSUM}"

# ---- 组装 fpk 根目录 ----------------------------------------------------------
mkdir -p "${PKG_ROOT}/cmd" "${PKG_ROOT}/ui/images"

cp -f "${APP_TGZ}" "${PKG_ROOT}/app.tgz"
cp -f "${FNOS_DIR}/pvepilot.sc" "${PKG_ROOT}/"
cp -f "${FNOS_DIR}/ICON.PNG" "${FNOS_DIR}/ICON_256.PNG" "${PKG_ROOT}/"
cp -f "${PKG_ROOT}/ICON_256.PNG" "${PKG_ROOT}/ui/images/256.png"
cp -a "${FNOS_DIR}/cmd/." "${PKG_ROOT}/cmd/"
cp -a "${FNOS_DIR}/config/." "${PKG_ROOT}/config/"
cp -a "${FNOS_DIR}/wizard/." "${PKG_ROOT}/wizard/"
cp -a "${FNOS_DIR}/ui/." "${PKG_ROOT}/ui/"
chmod +x "${PKG_ROOT}"/cmd/* 2>/dev/null || true

# manifest：按目标写入 version / platform / checksum
cp -f "${FNOS_DIR}/manifest" "${PKG_ROOT}/manifest"
sed -i "s/^version[[:space:]]*=.*/version         = ${VERSION}/" "${PKG_ROOT}/manifest"
sed -i "s/^platform[[:space:]]*=.*/platform        = ${ARCH}/" "${PKG_ROOT}/manifest"
sed -i "s/^checksum[[:space:]]*=.*/checksum        = ${CHECKSUM}/" "${PKG_ROOT}/manifest"

# ---- 最终打包 ----------------------------------------------------------------
FPK_NAME="pvepilot_${VERSION}_${ARCH}.fpk"
if [ "${DRY_RUN}" -eq 1 ]; then
    echo
    echo "[DRY-RUN] 校验通过，本应生成: ${OUT_DIR}/${FPK_NAME}"
    echo "[DRY-RUN] 最终 manifest:"
    sed 's/^/    /' "${PKG_ROOT}/manifest"
    echo "[DRY-RUN] fpk 目录内容:"
    (cd "${PKG_ROOT}" && find . -type f | sort | sed 's/^/    /')
    exit 0
fi

mkdir -p "${OUT_DIR}"
(cd "${PKG_ROOT}" && tar -czf "${OUT_DIR}/${FPK_NAME}" *)
echo "[INFO] 生成: ${OUT_DIR}/${FPK_NAME} ($(du -h "${OUT_DIR}/${FPK_NAME}" | cut -f1))"
