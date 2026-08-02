#!/bin/bash
# ============================================================================
# PVE 管家本地验证脚本（无飞牛实机时可在开发机执行的部分）
# ----------------------------------------------------------------------------
# 覆盖：
#   1. install_callback 生成 nginx.conf（模拟 fnOS TRIM_* 环境变量）
#   2. §5 配置要点逐项核对
#   3. nginx -t 配置语法校验
#   4. 真实启动 nginx 并经由本地自签 HTTPS 后端做端到端透传
#      （验证 Host 头透传、https→https 自签后端、websocket 头）
#   5. config_callback 重写配置并重启（改监听端口）
#   6. main stop/status/restart
#
# 用法：./build/test/local-verify.sh
# 环境：需可执行 fnos/bin/nginx（x86_64 或 aarch64 本机二进制）
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/pvepilot-verify.XXXXXX)"
BACKEND_PID=""
NGINX_PID=""

cleanup() {
    [ -n "${BACKEND_PID}" ] && kill "${BACKEND_PID}" 2>/dev/null || true
    [ -n "${NGINX_PID}" ] && kill "${NGINX_PID}" 2>/dev/null || true
    rm -rf "${WORK}"
}
trap cleanup EXIT

echo "======================================================"
echo " PVE 管家 本地验证  work=${WORK}"
echo "======================================================"

# ---- 1. 自签 HTTPS 后端（模拟 PVE 8006）-------------------------------------
echo
echo "[1/7] 准备自签 HTTPS 后端（模拟 PVE 8006）"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${WORK}/pve.key" -out "${WORK}/pve.crt" \
    -days 1 -subj "/CN=pve.local" >/dev/null 2>&1

cat > "${WORK}/backend.py" <<'PYEOF'
import http.server
import json
import ssl
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self):
        body = json.dumps({
            "path": self.path,
            "headers": {k: v for k, v in self.headers.items()},
            "remote": self.client_address[0],
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
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
server = http.server.HTTPServer(("127.0.0.1", 8006), Handler)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PYEOF

python3 "${WORK}/backend.py" "${WORK}/pve.crt" "${WORK}/pve.key" \
    >"${WORK}/backend.log" 2>&1 &
BACKEND_PID=$!
sleep 1
echo "    后端已启动 pid=${BACKEND_PID}（https://127.0.0.1:8006，自签证书）"

# ---- 2. 模拟 fnOS 安装回调 ---------------------------------------------------
echo
echo "[2/7] 模拟 install_callback（TRIM_* 环境变量 + 向导输入）"
export PVE_PILOT_DEV=1
export TRIM_APPDEST="${ROOT}/fnos"
export TRIM_PKGVAR="${WORK}/var"
export TRIM_APPNAME="pvepilot"
export TRIM_TEMP_LOGFILE="${WORK}/install.tmp.log"
export wizard_pve_addr="127.0.0.1"
export wizard_pve_port="8006"
export wizard_proxy_port="8800"
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
    "listen       8800;|透传端口 8800"
    "server_name  _;|server_name _"
    "proxy_pass        https://127.0.0.1:8006;|proxy_pass https://地址:端口"
    "proxy_set_header  Host \$host;|Host 头必须透传"
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

# ---- 4. nginx -t 配置校验 -----------------------------------------------------
echo
echo "[4/7] nginx -t 配置校验"
"${ROOT}/fnos/bin/nginx" -t -c "${CONF}" -p "${TRIM_PKGVAR}/" 2>&1 | sed 's/^/    /'

# ---- 5. 启动 nginx 并端到端验证 ------------------------------------------------
echo
echo "[5/7] main start + 端到端透传"
"${ROOT}/fnos/cmd/main" start
NGINX_PID=$(cat "${TRIM_PKGVAR}/pvepilot.pid")
"${ROOT}/fnos/cmd/main" status

echo "    curl http://127.0.0.1:8800/"
RESP=$(curl -sk --max-time 10 -H "Host: test.fnos.net" \
    http://127.0.0.1:8800/pve/test 2>/dev/null || true)
echo "${RESP}" | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || echo "    RESP: ${RESP}"
echo "${RESP}" | grep -q '"Host": "test.fnos.net"' \
    || { echo "FAIL: Host 头未透传"; exit 1; }
echo "${RESP}" | grep -q '"path": "/pve/test"' \
    || { echo "FAIL: 根路径透传异常"; exit 1; }
echo "    [OK] Host 头与路径透传正确（后端收到的 Host=客户端原始 Host）"

# ---- 6. config_callback 重写配置并重启 -----------------------------------------
echo
echo "[6/7] config_callback（改监听端口 8801 并重启）"
export wizard_pve_addr="127.0.0.1"
export wizard_pve_port="8006"
export wizard_proxy_port="8801"
"${ROOT}/fnos/cmd/config_callback" >/dev/null 2>&1
echo "    config_callback 退出码=$?"
grep -q "listen       8801;" "${CONF}" || { echo "FAIL: 配置未重写"; exit 1; }
sleep 1
if curl -sk --max-time 5 -o /dev/null http://127.0.0.1:8801/; then
    echo "    [OK] 新端口 8801 已监听（服务重启成功）"
else
    echo "FAIL: 8801 未监听"; exit 1
fi
if curl -sk --max-time 3 -o /dev/null http://127.0.0.1:8800/ 2>/dev/null; then
    echo "FAIL: 旧端口 8800 仍监听"; exit 1
else
    echo "    [OK] 旧端口 8800 已释放"
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
export wizard_pve_port="8006"
export wizard_proxy_port="8801"
for cb in install_init config_init upgrade_init upgrade_callback uninstall_init; do
    if "${ROOT}/fnos/cmd/${cb}" >/dev/null 2>&1; then
        echo "    [OK]   ${cb} 退出码=0"
    else
        echo "    [FAIL] ${cb} 执行失败"
        exit 1
    fi
done

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
