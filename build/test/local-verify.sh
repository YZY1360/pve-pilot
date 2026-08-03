#!/bin/bash
# ============================================================================
# PVE 管家本地验证脚本（无飞牛实机时可在开发机执行的部分）
# ----------------------------------------------------------------------------
# 覆盖：
#   1. install_callback 生成 nginx.conf（模拟 fnOS TRIM_* 环境变量）
#   2. §5 配置要点逐项核对
#   3. nginx -t 配置语法校验
#   4. 真实启动 nginx 并经由本地自签 HTTPS 后端做端到端透传
#      （验证 Host 头透传、https→https 自签后端、websocket 头、0.1.7 纯 HTTP
#      直连 200 透传、sub_filter 把 PVE 前端 JS 的 Secure cookie 写入改写为 false）
#   5. config_callback 重写配置并重启（改监听端口，ui/config 端口声明联动）
#   6. main stop/status/restart
#   7. 手机 App 图标兜底补全：ui/images 多尺寸（16/24/32/48/64/72/96/128/256）
#      + 各尺寸幂等
#   8. 0.1.6 → 0.1.7 升级：旧 ssl 监听 + 497 跳转配置自动重建为纯 HTTP + sub_filter
#
# 用法：./build/test/local-verify.sh
# 环境：需可执行 fnos/bin/nginx（x86_64 或 aarch64 本机二进制）
#       且该二进制编译了 --with-http_sub_module（0.1.7 起 build/build-nginx.sh 已启用）
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/pvepilot-verify.XXXXXX)"
BACKEND_PID=""
NGINX_PID=""
FRAMEWORK_ICON_CREATED=""

cleanup() {
    [ -n "${BACKEND_PID}" ] && kill "${BACKEND_PID}" 2>/dev/null || true
    [ -n "${NGINX_PID}" ] && kill "${NGINX_PID}" 2>/dev/null || true
    # 仅清理本次测试自己创建的框架注册目录图标，避免误删真机已有文件
    [ -n "${FRAMEWORK_ICON_CREATED}" ] && rm -f "/var/apps/${TRIM_APPNAME:-}/ICON_256.PNG" 2>/dev/null || true
    [ -n "${FRAMEWORK_ICON_CREATED}" ] && rmdir "/var/apps/${TRIM_APPNAME:-}" 2>/dev/null || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

# 端口声明同步会把实际透传端口写回 ${TRIM_APPDEST}/ui/config；为避免污染仓库源码，
# 用临时副本作为应用安装目录（仍包含 bin/nginx 与 conf/mime.types）
APP_DEST="${WORK}/appdest"
cp -a "${ROOT}/fnos" "${APP_DEST}"

echo "======================================================"
echo " PVE 管家 本地验证  work=${WORK}"
echo "======================================================"

# ---- 1. 自签 HTTPS 后端（模拟 PVE；监听 8007 避免与透传默认端口 8006 冲突）----
echo
echo "[1/7] 准备自签 HTTPS 后端（模拟 PVE）"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${WORK}/pve.key" -out "${WORK}/pve.crt" \
    -days 1 -subj "/CN=pve.local" >/dev/null 2>&1

cat > "${WORK}/backend.py" <<'PYEOF'
import http.server
import json
import ssl
import sys

# 模拟 PVE 9.2.6 的 /proxmoxlib.js 响应：包含 pwt authSet（参数 20 空格缩进）与
# authClear（参数 16 空格缩进）两处 Secure=true 的 auth cookie 写入，另加一个同
# 缩进但不同上下文的非 auth cookie 写入（PVELangCookie），用于验证 sub_filter
# 带上下文匹配、不会误替换。
PROXMOXLIB_JS = """\
/*
 * proxmox-widget-toolkit（本地验证用摘录，缩进与 PVE 9.2.6 线上一致）
 */
Ext.define('Proxmox.Utils', {
    setAuthData: function (data) {
        Proxmox.UserName = data.username;
        Proxmox.LoggedOut = data.LoggedOut;
        if (data.ticket) {
            Proxmox.CSRFPreventionToken = data.CSRFPreventionToken;
            Ext.util.Cookies.set(
                    Proxmox.Setup.auth_cookie_name,
                    data.ticket,
                    null,
                    '/',
                    null,
                    true,
                    'lax',
                );
        }
    },

    authClear: function () {
        if (Proxmox.LoggedOut) {
            return;
        }
        Ext.util.Cookies.set(
                Proxmox.Setup.auth_cookie_name,
                '',
                new Date(0),
                null,
                null,
                true,
                'lax',
            );
    },

    setLangCookie: function (value) {
        var dt = new Date(0);
        Ext.util.Cookies.set(
                    'PVELangCookie',
                    value,
                    dt,
                    null,
                    null,
                    true,
                );
    }
});
"""


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self):
        if self.path in ("/proxmoxlib.js", "/pve2/js/pvemanagerlib.js"):
            body = PROXMOXLIB_JS.encode()
            ctype = "application/javascript"
        else:
            body = json.dumps({
                "path": self.path,
                "headers": {k: v for k, v in self.headers.items()},
                "remote": self.client_address[0],
            }).encode()
            ctype = "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = _reply
    do_POST = _reply
    do_HEAD = _reply

    def log_message(self, fmt, *args):
        sys.stderr.write("[backend] " + fmt % args + "\n")

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[1], sys.argv[2])
server = http.server.HTTPServer(("127.0.0.1", 8007), Handler)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PYEOF

python3 "${WORK}/backend.py" "${WORK}/pve.crt" "${WORK}/pve.key" \
    >"${WORK}/backend.log" 2>&1 &
BACKEND_PID=$!
sleep 1
echo "    后端已启动 pid=${BACKEND_PID}（https://127.0.0.1:8007，自签证书）"

# ---- 2. 模拟 fnOS 安装回调 ---------------------------------------------------
echo
echo "[2/7] 模拟 install_callback（TRIM_* 环境变量 + 向导输入）"
export PVE_PILOT_DEV=1
export TRIM_APPDEST="${APP_DEST}"
export TRIM_PKGVAR="${WORK}/var"
export TRIM_APPNAME="pvepilot"
export TRIM_TEMP_LOGFILE="${WORK}/install.tmp.log"
export wizard_pve_addr="127.0.0.1"
export wizard_pve_port="8007"
export wizard_proxy_port="8006"
mkdir -p "${TRIM_PKGVAR}"

"${ROOT}/fnos/cmd/install_callback" >/dev/null 2>&1
echo "    install_callback 退出码=$?"
[ -f "${TRIM_PKGVAR}/nginx.conf" ] || { echo "FAIL: nginx.conf 未生成"; exit 1; }
[ -f "${TRIM_PKGVAR}/settings" ] || { echo "FAIL: settings 未生成"; exit 1; }
echo "    nginx.conf 已生成"

# ---- 3. §5 配置要点逐项核对 ---------------------------------------------------
echo
echo "[3/7] §5 透传配置要点逐项核对"
CONF="${TRIM_PKGVAR}/nginx.conf"
checks=(
    "listen       8006;|透传端口 8006（纯 HTTP 单监听，无 ssl）"
    "server_name  _;|server_name _"
    "proxy_pass        https://127.0.0.1:8007;|proxy_pass https://地址:端口"
    "proxy_set_header  Host \$host;|Host 头必须透传"
    "proxy_set_header  X-Forwarded-Proto \$scheme;|X-Forwarded-Proto 透传原始协议"
    "proxy_cookie_flags ~ nosecure;|剥离后端 Set-Cookie 的 Secure 标志（双保险）"
    "sub_filter_types application/javascript;|sub_filter_types 覆盖 JS 响应"
    "sub_filter \"Ext.util.Cookies.set(|sub_filter 改写 PVE 前端 JS cookie 写入"
    "sub_filter_once off;|sub_filter_once off（多处出现全部替换）"
    "proxy_set_header  Accept-Encoding \"\";|强制后端返回未压缩响应（否则 sub_filter 无法匹配压缩字节）"
    "proxy_http_version 1.1;|HTTP/1.1"
    "proxy_set_header  Upgrade \$http_upgrade;|websocket Upgrade"
    "proxy_set_header  Connection \"upgrade\";|websocket Connection"
    "proxy_buffering   off;|关闭缓冲"
    "client_max_body_size 0;|上传不设限"
    "proxy_connect_timeout 3600s;|连接超时 3600s"
    "proxy_read_timeout 3600s;|读超时 3600s"
    "proxy_send_timeout 3600s;|写超时 3600s"
    "proxy_ssl_verify  off;|后端不校验证书"
)
ok=0
for item in "${checks[@]}"; do
    pattern="${item%%|*}"; label="${item##*|}"
    if grep -qF -- "${pattern}" "${CONF}"; then
        echo "    [OK]   ${label}"
        ok=$((ok + 1))
    else
        echo "    [FAIL] ${label}（未找到: ${pattern}）"
        exit 1
    fi
done
[ "${ok}" -eq "${#checks[@]}" ] || exit 1

# 0.1.7 起不得再出现 0.1.3-0.1.6 的 ssl/497 配置（纯 HTTP 直连，无证书跳转）
bad_patterns=(
    "listen       8006 ssl"
    "ssl_certificate"
    "error_page"
)
for bad in "${bad_patterns[@]}"; do
    if grep -qF -- "${bad}" "${CONF}"; then
        echo "    [FAIL] 配置仍含 0.1.6 及更早的 HTTPS 跳转指令（${bad}）"
        exit 1
    fi
done
echo "    [OK]   无 ssl 监听 / ssl_certificate / error_page 497（纯 HTTP 直连）"

# ---- 4. nginx -t 配置校验 -----------------------------------------------------
echo
echo "[4/7] nginx -t 配置校验"
"${ROOT}/fnos/bin/nginx" -t -c "${CONF}" -p "${TRIM_PKGVAR}/" 2>&1 | sed 's/^/    /'

# ---- 5. 启动 nginx 并端到端验证 ------------------------------------------------
echo
echo "[5/7] main start + 端到端透传（0.1.7 纯 HTTP 直连 + sub_filter 改写）"
"${ROOT}/fnos/cmd/main" start
NGINX_PID=$(cat "${TRIM_PKGVAR}/pvepilot.pid")
"${ROOT}/fnos/cmd/main" status

echo "    curl http://127.0.0.1:8006/pve/test → 应直接 200 透传（无 301、无证书校验）"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "Host: test.fnos.net" http://127.0.0.1:8006/pve/test 2>/dev/null || true)
[ "${HTTP_CODE}" = "200" ] || { echo "FAIL: HTTP 未 200 透传（code=${HTTP_CODE}）"; exit 1; }
RESP=$(curl -s --max-time 10 -H "Host: test.fnos.net" \
    http://127.0.0.1:8006/pve/test 2>/dev/null || true)
echo "${RESP}" | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || echo "    RESP: ${RESP}"
echo "${RESP}" | grep -q '"Host": "test.fnos.net"' \
    || { echo "FAIL: Host 头未透传"; exit 1; }
echo "${RESP}" | grep -q '"path": "/pve/test"' \
    || { echo "FAIL: 根路径透传异常"; exit 1; }
echo "    [OK] Host 头与路径透传正确（后端收到的 Host=客户端原始 Host）"

echo "    curl http://127.0.0.1:8006/proxmoxlib.js → sub_filter 把 Secure 参数改写为 false"
RESP_JS="${WORK}/proxmoxlib.out"
HTTP_JS_CODE=$(curl -s -o "${RESP_JS}" -w '%{http_code}' --max-time 10 \
    -H "Host: test.fnos.net" http://127.0.0.1:8006/proxmoxlib.js 2>/dev/null || true)
[ "${HTTP_JS_CODE}" = "200" ] || { echo "FAIL: /proxmoxlib.js 未 200（code=${HTTP_JS_CODE}）"; exit 1; }
python3 - "${RESP_JS}" <<'PYEOF'
import sys

body = open(sys.argv[1], encoding="utf-8").read()
required = [
    # authSet（20 空格缩进）：secure 参数应被改写为 false
    "data.ticket,\n                    null,\n                    '/',\n                    null,\n                    false,",
    # authClear（16 空格缩进）：secure 参数应被改写为 false
    "                '',\n                new Date(0),\n                null,\n                null,\n                false,",
    # 非 auth cookie 写入（不同上下文、同缩进）必须保持 true：证明 sub_filter 未误替换
    "'PVELangCookie',\n                    value,\n                    dt,\n                    null,\n                    null,\n                    true,",
    # 其余 JS 结构完整（lax 参数仍在）
    "'lax',",
]
for pat in required:
    if pat not in body:
        print("FAIL: 响应缺少期望片段: " + repr(pat[:60]))
        sys.exit(1)
for pat in [
    "data.ticket,\n                    null,\n                    '/',\n                    null,\n                    true,",
    "                '',\n                new Date(0),\n                null,\n                null,\n                true,",
]:
    if pat in body:
        print("FAIL: Secure=true 未被改写: " + repr(pat[:60]))
        sys.exit(1)
print("    [OK] sub_filter 已把 authSet/authClear 的 Secure=true 改写为 false，PVELangCookie 等无关调用不受影响")
PYEOF
echo "    [OK] 纯 HTTP 直连 200 + sub_filter 改写生效（http 请求无 301）"

# ---- 6. config_callback 重写配置并重启 -----------------------------------------
echo
echo "[6/7] config_callback（改监听端口 8801 并重启）"
export wizard_pve_addr="127.0.0.1"
export wizard_pve_port="8007"
export wizard_proxy_port="8801"
"${ROOT}/fnos/cmd/config_callback" >/dev/null 2>&1
echo "    config_callback 退出码=$?"
grep -q "listen       8801;" "${CONF}" || { echo "FAIL: 配置未重写"; exit 1; }
sleep 1
if curl -s --max-time 5 -o /dev/null http://127.0.0.1:8801/; then
    echo "    [OK] 新端口 8801 已监听（服务重启成功）"
else
    echo "FAIL: 8801 未监听"; exit 1
fi
if curl -s --max-time 3 -o /dev/null http://127.0.0.1:8006/ 2>/dev/null; then
    echo "FAIL: 旧端口 8006 仍监听"; exit 1
else
    echo "    [OK] 旧端口 8006 已释放"
fi

# ---- 7. main stop/restart/log ---------------------------------------------------
echo
echo "[7/7] main stop / restart / log"
"${ROOT}/fnos/cmd/main" restart
"${ROOT}/fnos/cmd/main" stop
sleep 1
if [ -f "${TRIM_PKGVAR}/pvepilot.pid" ]; then
    echo "FAIL: 停止后 PID 文件仍存在"; exit 1
fi
"${ROOT}/fnos/cmd/main" status 2>&1 | sed 's/^/    /' || true
"${ROOT}/fnos/cmd/main" log 5 2>&1 | sed 's/^/    /' || true

# ---- 8. 其余生命周期回调冒烟测试 + 配置缺失兜底重建 ------------------------------
echo
echo "[8/8] 生命周期回调冒烟 + 配置缺失兜底重建"
export wizard_pve_addr="127.0.0.1"
export wizard_pve_port="8007"
export wizard_proxy_port="8801"
for cb in install_init config_init upgrade_init upgrade_callback uninstall_init; do
    if "${ROOT}/fnos/cmd/${cb}" >/dev/null 2>&1; then
        echo "    [OK]   ${cb} 退出码=0"
    else
        echo "    [FAIL] ${cb} 执行失败"
        exit 1
    fi
done

# 手机 App 按 ui/config 的 "icon": "images/{0}.png" 请求多个尺寸，取两家实测并集
# （百度网盘/影视 trim.media 与 Jellyfin）全部补齐；校验内容/权限/owner
UI_ICON_SIZES="16 24 32 48 64 72 96 128 256"
check_ui_icons() {
    local ref="$1" label="$2"
    local size=""
    for size in ${UI_ICON_SIZES}; do
        local f="${APP_DEST}/ui/images/${size}.png"
        [ -f "${f}" ] || { echo "FAIL: ${label} 未补齐 ui/images/${size}.png"; exit 1; }
        cmp -s "${f}" "${ref}" \
            || { echo "FAIL: ${label} ${size}.png 内容与基准不一致"; exit 1; }
        [ "$(stat -c %a "${f}")" = "644" ] \
            || { echo "FAIL: ${label} ${size}.png 权限非 644"; exit 1; }
        [ "$(stat -c %u:%g "${f}")" = "$(stat -c %u:%g "${APP_DEST}/ui/config")" ] \
            || { echo "FAIL: ${label} ${size}.png owner 与 ui/config 不一致"; exit 1; }
    done
    [ "$(stat -c %a "${APP_DEST}/ui/images")" = "755" ] \
        || { echo "FAIL: ${label} ui/images 目录权限非 755"; exit 1; }
    [ "$(find "${APP_DEST}/ui/images" -maxdepth 1 -name '*.png' | wc -l)" -eq 9 ] \
        || { echo "FAIL: ${label} ui/images 下 png 文件数非 9"; exit 1; }
    echo "    [OK]   ${label}：ui/images 补齐 9 个尺寸（16/24/32/48/64/72/96/128/256.png，644/755，owner 与 ui/config 一致）"
}

# 模拟 0.1.2 → 0.1.3 升级场景（fnOS 升级不补齐新增的 ui/images 目录，手机 App
# 图标缺失）：service_postupgrade 应从包内 ICON_256.PNG 兜底生成全部尺寸
rm -rf "${APP_DEST}/ui/images"
"${ROOT}/fnos/cmd/upgrade_callback" >/dev/null 2>&1
ICON="${APP_DEST}/ui/images/256.png"
check_ui_icons "${APP_DEST}/ICON_256.PNG" "service_postupgrade 兜底（包内 ICON_256.PNG 源）"

# 模拟 0.1.4 实机场景（飞牛安装日志）：fpk 根目录的 ICON_256.PNG 被提取到框架注册
# 目录 /var/apps/${TRIM_APPNAME}/，应用安装目录下反而没有；service_postupgrade
# 应从 /var/apps 源兜底生成全部尺寸
FRAMEWORK_DIR="/var/apps/${TRIM_APPNAME}"
if [ -f "${FRAMEWORK_DIR}/ICON_256.PNG" ]; then
    # 真机/已有安装场景：文件已存在则直接作为源与比对基准，不做任何删除
    FRAMEWORK_ICON="${FRAMEWORK_DIR}/ICON_256.PNG"
else
    mkdir -p "${FRAMEWORK_DIR}"
    cp -f "${APP_DEST}/ICON_256.PNG" "${FRAMEWORK_DIR}/ICON_256.PNG"
    FRAMEWORK_ICON="${FRAMEWORK_DIR}/ICON_256.PNG"
    FRAMEWORK_ICON_CREATED=1
fi
FRAMEWORK_REF="${WORK}/icon256.framework.ref"
cp -f "${FRAMEWORK_ICON}" "${FRAMEWORK_REF}"
rm -f "${APP_DEST}/ICON_256.PNG" "${APP_DEST}/ICON.PNG"
rm -rf "${APP_DEST}/ui/images"
"${ROOT}/fnos/cmd/upgrade_callback" >/dev/null 2>&1
check_ui_icons "${FRAMEWORK_REF}" "service_postupgrade 兜底（/var/apps 源 ${FRAMEWORK_ICON}）"
# 恢复安装目录图标副本供后续 prestart/幂等用例使用；框架目录仅在我们创建时清理
cp -f "${FRAMEWORK_REF}" "${APP_DEST}/ICON_256.PNG"
if [ -n "${FRAMEWORK_ICON_CREATED}" ]; then
    rm -f "${FRAMEWORK_ICON}"
    rmdir "${FRAMEWORK_DIR}" 2>/dev/null || true
    FRAMEWORK_ICON_CREATED=""
fi

# 模拟 0.1.5 → 0.1.6 升级场景（当前实机状态）：256.png 已存在但其余尺寸缺失，
# 升级后应补齐其余尺寸，且 256.png 不被覆盖（幂等）
ICON_REF="${WORK}/icon256.pre-upgrade.ref"
cp -f "${ICON}" "${ICON_REF}"
rm -f "${APP_DEST}"/ui/images/{16,24,32,48,64,72,96,128}.png
"${ROOT}/fnos/cmd/upgrade_callback" >/dev/null 2>&1
cmp -s "${ICON}" "${ICON_REF}" \
    || { echo "FAIL: 0.1.5→0.1.6 场景 256.png 被重新生成（应幂等跳过）"; exit 1; }
check_ui_icons "${APP_DEST}/ICON_256.PNG" "0.1.5→0.1.6 升级（仅 256.png 存在，补齐其余尺寸）"

# service_prestart 兜底：再次删除后 main start 也应补齐，且已存在时不覆盖（幂等）
rm -rf "${APP_DEST}/ui/images"
"${ROOT}/fnos/cmd/main" start >/dev/null 2>&1
check_ui_icons "${APP_DEST}/ICON_256.PNG" "service_prestart 兜底补齐"
"${ROOT}/fnos/cmd/main" stop >/dev/null 2>&1
printf 'dirty' >> "${ICON}"
printf 'dirty' >> "${APP_DEST}/ui/images/128.png"
"${ROOT}/fnos/cmd/main" start >/dev/null 2>&1
grep -q "dirty" "${ICON}" \
    || { echo "FAIL: 已存在的 256.png 被重新生成（应幂等跳过）"; exit 1; }
grep -q "dirty" "${APP_DEST}/ui/images/128.png" \
    || { echo "FAIL: 已存在的 128.png 被重新生成（应幂等跳过）"; exit 1; }
"${ROOT}/fnos/cmd/main" stop >/dev/null 2>&1
echo "    [OK]   service_prestart 兜底补齐且幂等（已存在尺寸不覆盖）"

# 模拟 0.1.6 → 0.1.7 升级场景：旧配置为 ssl 监听 + error_page 497 跳转，升级后必须
# 重建为 0.1.7 纯 HTTP + sub_filter 方案（否则 App WebView 黑屏/登录 401 依旧）
cat > "${TRIM_PKGVAR}/nginx.conf" <<'OLDEOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen       8801 ssl;
        server_name  _;
        ssl_certificate     /tmp/server.crt;
        ssl_certificate_key /tmp/server.key;
        error_page   497 =301 https://$host:8801$request_uri;
        location / {
            proxy_pass        https://127.0.0.1:8007;
        }
    }
}
OLDEOF
"${ROOT}/fnos/cmd/upgrade_callback" >/dev/null 2>&1
grep -qF "sub_filter_types" "${TRIM_PKGVAR}/nginx.conf" \
    || { echo "FAIL: 0.1.6→0.1.7 升级未重建配置（无 sub_filter）"; exit 1; }
grep -qF "error_page" "${TRIM_PKGVAR}/nginx.conf" \
    && { echo "FAIL: 升级重建后仍残留 error_page 497"; exit 1; }
grep -qF "listen       8801;" "${TRIM_PKGVAR}/nginx.conf" \
    || { echo "FAIL: 升级重建后监听端口丢失"; exit 1; }
echo "    [OK]   0.1.6→0.1.7 升级：旧 ssl/497 配置自动重建为纯 HTTP + sub_filter（保留 8801）"

# 模拟升级后配置丢失：删除 nginx.conf，main start 应从 settings 兜底重建
rm -f "${TRIM_PKGVAR}/nginx.conf"
"${ROOT}/fnos/cmd/main" start >/dev/null 2>&1
sleep 1
grep -q "listen       8801;" "${TRIM_PKGVAR}/nginx.conf" \
    && echo "    [OK]   配置缺失时自动按保存的设置重建（8801）" \
    || { echo "FAIL: 配置缺失未自动重建"; exit 1; }
"${ROOT}/fnos/cmd/main" stop >/dev/null 2>&1

echo
echo "======================================================"
echo " 本地验证全部通过 ✅"
echo "======================================================"
