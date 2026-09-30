#!/usr/bin/env bash
# ============================================================================
# 苹果正式签名 · 本地辅助脚本（不需要 Xcode）
#
#   ./apple-signing-helper.sh csr            生成私钥 + CSR（拿去开发者后台申请证书）
#   ./apple-signing-helper.sh p12 <证书.cer> 把苹果签发的 .cer 转成 .p12
#   ./apple-signing-helper.sh secrets        把 .p12 / 描述文件编码成 GitHub Secret 文本
#   ./apple-signing-helper.sh udid           读取已连接 iPhone 的 UDID（Ad Hoc 需要）
#   ./apple-signing-helper.sh verify <x.ipa> 校验 IPA 的签名与描述文件
#   ./apple-signing-helper.sh checklist      打印操作顺序
# ============================================================================
set -euo pipefail

WORK="${SIGNING_DIR:-$HOME/Desktop/升级-iOS/apple-signing}"
KEY="$WORK/distribution.key"
CSR="$WORK/distribution.certSigningRequest"
P12="$WORK/distribution.p12"
EMAIL="${APPLE_EMAIL:-}"

c_ok()   { printf '\033[32m✅ %s\033[0m\n' "$1"; }
c_info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
c_warn() { printf '\033[33m⚠️  %s\033[0m\n' "$1"; }
c_err()  { printf '\033[31m❌ %s\033[0m\n' "$1"; }

need_openssl() {
  command -v openssl >/dev/null 2>&1 || { c_err "找不到 openssl"; exit 1; }
}

cmd_csr() {
  need_openssl
  mkdir -p "$WORK"
  if [ -f "$KEY" ]; then
    c_warn "已存在私钥 $KEY，不覆盖。如需重来请先手动删除它。"
  else
    c_info "生成 2048 位私钥…"
    openssl genrsa -out "$KEY" 2048 2>/dev/null
    chmod 600 "$KEY"
  fi

  if [ -z "$EMAIL" ]; then
    read -r -p "输入你的 Apple 账号邮箱（写进 CSR 用）: " EMAIL
  fi

  c_info "生成证书签名请求（CSR）…"
  openssl req -new -key "$KEY" -out "$CSR" \
    -subj "/emailAddress=$EMAIL/CN=iOS Distribution/C=CN" 2>/dev/null

  c_ok "完成"
  echo
  echo "  私钥     ：$KEY          ← 留着别删，后面转 p12 要用"
  echo "  请求文件 ：$CSR"
  echo
  echo "接下来："
  echo "  1. 打开 https://developer.apple.com/account/resources/certificates/list"
  echo "  2. 点 + → 勾选 Apple Distribution（Ad Hoc / TestFlight / 上架都用它）"
  echo "  3. 上传上面这个 .certSigningRequest 文件"
  echo "  4. 下载得到的 distribution.cer"
  echo "  5. 回来跑：./apple-signing-helper.sh p12 <下载的.cer路径>"
}

cmd_p12() {
  need_openssl
  local cer="${1:-}"
  [ -n "$cer" ] || { c_err "用法：$0 p12 <苹果签发的.cer>"; exit 1; }
  [ -f "$cer" ] || { c_err "找不到文件：$cer"; exit 1; }
  [ -f "$KEY" ] || { c_err "找不到私钥 $KEY，请先跑 csr"; exit 1; }
  mkdir -p "$WORK"

  local pem="$WORK/distribution.pem"
  c_info "转换证书格式 DER → PEM…"
  if ! openssl x509 -in "$cer" -inform DER -out "$pem" -outform PEM 2>/dev/null; then
    # 有些下载下来的 .cer 本身就是 PEM
    openssl x509 -in "$cer" -out "$pem" -outform PEM
  fi

  if [ -z "${P12_PASSWORD:-}" ]; then
    read -r -s -p "给 p12 设一个导出密码（记牢，要填进 GitHub Secret）: " P12_PASSWORD
    echo
  fi

  c_info "打包成 .p12…"
  openssl pkcs12 -export \
    -inkey "$KEY" -in "$pem" \
    -out "$P12" -name "Apple Distribution" \
    -passout "pass:$P12_PASSWORD" 2>/dev/null

  c_ok "完成：$P12"

  c_info "回读校验…"
  if openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -noout 2>/dev/null; then
    c_ok "p12 可正常打开"
  else
    c_warn "p12 回读失败，请确认密码"
  fi

  echo
  echo "把密码记进备忘录，下一步 secrets 会用到："
  echo "  P12_PASSWORD = $P12_PASSWORD"
}

cmd_secrets() {
  local p12="${1:-$P12}"
  local profile="${2:-}"
  [ -f "$p12" ] || { c_err "找不到 $p12，请先跑 p12"; exit 1; }

  if [ -z "$profile" ]; then
    # 优先从系统已安装的描述文件里挑
    local dir="$HOME/Library/MobileDevice/Provisioning Profiles"
    if [ -d "$dir" ]; then
      profile=$(ls -t "$dir"/*.mobileprovision 2>/dev/null | head -1 || true)
    fi
  fi
  [ -n "$profile" ] && [ -f "$profile" ] || { c_err "找不到描述文件，请把下载的 .mobileprovision 拖进来作为第二个参数"; exit 1; }

  echo "════════ GitHub 仓库 Secrets 内容 ════════"
  echo
  echo "──── 1) BUILD_CERTIFICATE_BASE64 ────"
  local cert_b64; cert_b64=$(base64 -i "$p12" | tr -d '\n')
  echo "$cert_b64"
  echo
  echo "──── 2) PROVISIONING_PROFILE_BASE64 ────"
  local prof_b64; prof_b64=$(base64 -i "$profile" | tr -d '\n')
  echo "$prof_b64"
  echo

  local plist="$WORK/profile.plist"
  security cms -D -i "$profile" > "$plist" 2>/dev/null || true
  if [ -s "$plist" ]; then
    echo "──── 描述文件信息（核对用）────"
    echo -n "名称    ："; plutil -extract Name raw -o - "$plist" 2>/dev/null || echo "?"
    echo -n "到期    ："; plutil -extract ExpirationDate raw -o - "$plist" 2>/dev/null || echo "?"
    echo -n "BundleID："; plutil -extract Entitlements.application-identifier raw -o - "$plist" 2>/dev/null || echo "?"
    echo
  fi

  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$cert_b64" | pbcopy
    c_info "证书 base64 已复制到剪贴板（先粘贴这个）"
  fi

  echo "════════ 还需要手工填的明文 Secrets ════════"
  echo "  P12_PASSWORD       = 刚才设的 p12 导出密码"
  echo "  KEYCHAIN_PASSWORD  = 随便编一个临时密码，例如 ShengjiCI2026"
  echo "  TEAM_ID            = 开发者后台 Membership 页的「团队 ID」（10 位，如 ABCDE12345）"
  echo
  echo "填入位置：GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret"
}

cmd_udid() {
  echo "════════ 查找 iPhone 的 UDID ════════"
  echo
  if command -v idevice_id >/dev/null 2>&1; then
    local ids; ids=$(idevice_id -l 2>/dev/null || true)
    if [ -n "$ids" ]; then echo "通过 libimobiledevice 读到："; echo "$ids"; return; fi
  fi

  echo "▸ 尝试从 USB 设备树读取…"
  local found=""
  if command -v system_profiler >/dev/null 2>&1; then
    found=$(system_profiler SPUSBDataType 2>/dev/null \
      | awk '/iPhone|iPad/{f=1} f&&/Serial Number/{print $NF; exit}')
  fi
  if [ -n "$found" ]; then
    echo
    c_ok "UDID：$found"
  else
    c_warn "自动读取没成功（新版 macOS + USB-C 机型常常读不到）"
    echo
    echo "手工取法（任选一种）："
    echo "  A. Finder → 左侧选中 iPhone → 反复点击设备名下方那行小字，"
    echo "     会依次切换「容量 → 序列号 → UDID」，出现 UDID 时右键拷贝"
    echo "  B. 装一个 Apple Configurator（App Store 免费），设备信息里直接显示 UDID"
    echo "  C. 开发者后台 Devices 页面如果之前加过，直接复制"
    echo "  D. Windows 上用 iMazing / 3uTools 也能读"
  fi
  echo
  echo "拿到后加到：https://developer.apple.com/account/resources/devices/list"
  echo "（每年每种设备类型上限 100 台，加了当年删不掉，只会占用名额）"
}

cmd_verify() {
  local ipa="${1:-}"
  [ -n "$ipa" ] || { c_err "用法：$0 verify <x.ipa>"; exit 1; }
  [ -f "$ipa" ] || { c_err "找不到文件：$ipa"; exit 1; }

  local tmp; tmp=$(mktemp -d)
  unzip -q "$ipa" -d "$tmp"
  local app; app=$(find "$tmp/Payload" -maxdepth 1 -name '*.app' | head -1)
  [ -n "$app" ] || { c_err "IPA 里没有 .app"; exit 1; }

  echo "════════ 签名信息 ════════"
  if codesign -dv --verbose=4 "$app" 2>&1 | grep -qE 'Authority'; then
    codesign -dv --verbose=4 "$app" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority|Timestamp'
    c_ok "已签名"
  else
    c_warn "未签名（这就是 Sideloadly 需要的那种包）"
    codesign -dv "$app" 2>&1 | head -2 || true
  fi

  echo
  echo "════════ 描述文件 ════════"
  if [ -f "$app/embedded.mobileprovision" ]; then
    security cms -D -i "$app/embedded.mobileprovision" > "$tmp/p.plist"
    echo -n "名称    ："; plutil -extract Name raw -o - "$tmp/p.plist"
    echo -n "到期    ："; plutil -extract ExpirationDate raw -o - "$tmp/p.plist"
    local devcount; devcount=$(plutil -extract ProvisionedDevices raw -o - "$tmp/p.plist" 2>/dev/null | grep -c '"' || echo 0)
    [ "$devcount" -gt 0 ] && echo "限定设备：$devcount 台" || echo "限定设备：否（App Store 型）"
  else
    c_warn "没有内嵌描述文件"
  fi

  echo
  echo "════════ 资源 ════════"
  ls -la "$app/www" 2>/dev/null && c_ok "www 资源在位" || c_err "缺少 www 目录"

  echo
  echo "════════ 深层校验 ════════"
  codesign --verify --deep --strict "$app" 2>&1 && c_ok "签名链校验通过"

  rm -rf "$tmp"
}

cmd_checklist() {
  cat <<'TXT'
════════ 换成苹果正式签名 · 操作顺序 ════════

第 0 步  加入 Apple Developer Program（¥688/年，$99）
         iPhone 装「Apple Developer」App → 账户 → 注册，48 小时内通过。

第 1 步  记下 Team ID
         developer.apple.com → Account → Membership → 「团队 ID」

第 2 步  注册 App ID
         Certificates, Identifiers & Profiles → Identifiers → +
         选 App IDs → App，Bundle ID 填：com.shengji.app（Explicit）

第 3 步  生成证书
         ./apple-signing-helper.sh csr
         上传 CSR → 下载 Apple Distribution 证书 → ./apple-signing-helper.sh p12 <证书.cer>

第 4 步  注册设备（仅 Ad Hoc 需要；走 TestFlight 可跳过）
         ./apple-signing-helper.sh udid

第 5 步  建描述文件
         Profiles → + → 选 Ad Hoc 或 App Store
         绑 App ID + 上面那张证书 +（Ad Hoc 还要勾设备）→ 下载 .mobileprovision

第 6 步  取 App Store Connect API Key（上传 TestFlight 才需要）
         App Store Connect → 用户和访问 → 集成 → App Store Connect API
         生成 Key（App Manager 角色），下载 AuthKey_XXXX.p8（只能下一次）

第 7 步  写 GitHub Secrets
         ./apple-signing-helper.sh secrets <证书.p12> <描述文件.mobileprovision>
         仓库 → Settings → Secrets and variables → Actions

第 8 步  跑编译
         GitHub 仓库 → Actions → 「Build signed IPA (手动签名)」→ Run workflow
         选 ad-hoc 或 app-store

第 9 步  校验
         ./apple-signing-helper.sh verify <下载回来的.ipa>

════════════════════════════════════════════
TXT
}

case "${1:-}" in
  csr)       shift; cmd_csr "$@" ;;
  p12)       shift; cmd_p12 "$@" ;;
  secrets)   shift; cmd_secrets "$@" ;;
  udid)      shift; cmd_udid "$@" ;;
  verify)    shift; cmd_verify "$@" ;;
  checklist) cmd_checklist ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
