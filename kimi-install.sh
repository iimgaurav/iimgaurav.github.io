#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://cdn.kimi.com/kimi-claw}"
TGZ_URL="${TGZ_URL:-$BASE_URL/kimi-claw-latest.tgz}"
SEARCH_TGZ_URL="${SEARCH_TGZ_URL:-$BASE_URL/openclaw-kimi-search-0.1.2.tgz}"

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
NPM_BIN="${NPM_BIN:-npm}"
TARGET_DIR="${TARGET_DIR:-$HOME/.openclaw/extensions/kimi-claw}"
SEARCH_TARGET_DIR="${SEARCH_TARGET_DIR:-$HOME/.openclaw/extensions/kimi-search}"
SEARCH_PLUGIN_ENABLED="${SEARCH_PLUGIN_ENABLED:-0}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
DEFAULT_LOCAL_CONFIG_PATH="${DEFAULT_LOCAL_CONFIG_PATH:-$HOME/.kimi/kimi-claw/kimi-claw-config.json}"
DEFAULT_BRIDGE_URL="${OPENCLAW_DEFAULT_BRIDGE_URL:-wss://www.kimi.com/api-claw/bots/agent-ws}"
DEFAULT_KIMIAPI_HOST="${OPENCLAW_DEFAULT_KIMIAPI_HOST:-https://www.kimi.com/api-claw}"

BRIDGE_MODE="${BRIDGE_MODE:-acp}"
WS_URL="${WS_URL:-${OPENCLAW_BRIDGE_URL:-}}"
BOT_TOKEN="${BOT_TOKEN:-${OPENCLAW_BRIDGE_TOKEN:-}}"
KIMIAPI_HOST="${OPENCLAW_KIMIAPI_HOST:-${KIMIAPI_HOST:-$DEFAULT_KIMIAPI_HOST}}"
BRIDGE_USER_ID="${BRIDGE_USER_ID:-}"
BRIDGE_INSTANCE_ID="${BRIDGE_INSTANCE_ID:-connector-$(hostname)}"
BRIDGE_DEVICE_ID="${BRIDGE_DEVICE_ID:-$(hostname)}"

GATEWAY_URL="${GATEWAY_URL:-ws://127.0.0.1:18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-}"
GATEWAY_AGENT_ID="${GATEWAY_AGENT_ID:-main}"

RETRY_BASE_MS="${RETRY_BASE_MS:-1000}"
RETRY_MAX_MS="${RETRY_MAX_MS:-600000}"
RETRY_MAX_ATTEMPTS="${RETRY_MAX_ATTEMPTS:-0}"
HISTORY_PENDING_TIMEOUT_MS="${HISTORY_PENDING_TIMEOUT_MS:-15000}"
LOG_ENABLED="0"

BRIDGE_CHECK_ENABLED="${BRIDGE_CHECK_ENABLED:-1}"
BRIDGE_CHECK_TIMEOUT_MS="${BRIDGE_CHECK_TIMEOUT_MS:-6000}"
BRIDGE_CHECK_SETTLE_MS="${BRIDGE_CHECK_SETTLE_MS:-800}"
GATEWAY_CHECK_ENABLED="${GATEWAY_CHECK_ENABLED:-1}"
GATEWAY_CHECK_TIMEOUT_MS="${GATEWAY_CHECK_TIMEOUT_MS:-8000}"
GATEWAY_CHECK_SETTLE_MS="${GATEWAY_CHECK_SETTLE_MS:-600}"
GATEWAY_CHECK_RETRIES="${GATEWAY_CHECK_RETRIES:-10}"
GATEWAY_CHECK_INTERVAL_MS="${GATEWAY_CHECK_INTERVAL_MS:-5000}"
GATEWAY_CHECK_INITIAL_DELAY_MS="${GATEWAY_CHECK_INITIAL_DELAY_MS:-5000}"
ALLOW_MISSING_BRIDGE_CONFIG="${ALLOW_MISSING_BRIDGE_CONFIG:-1}"
SETUP_DEFAULT_MODEL="${SETUP_DEFAULT_MODEL:-0}"
MODEL_ID="${MODEL_ID:-}"
HAS_BRIDGE_CONFIG="0"

BRIDGE_CHECK_STATUS="PENDING"
BRIDGE_CHECK_MESSAGE="not executed"
GATEWAY_CHECK_STATUS="PENDING"
GATEWAY_CHECK_MESSAGE="not executed"
GATEWAY_TOKEN_SOURCE="cli/env"

log() {
  printf "%b[install-oss]%b %s\n" "$COLOR_CYAN" "$COLOR_RESET" "$*"
}

init_colors() {
  COLOR_RESET=""
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_BOLD=""

  if [ -n "${NO_COLOR:-}" ]; then
    return
  fi
  if [ ! -t 1 ]; then
    return
  fi
  if ! command -v tput >/dev/null 2>&1; then
    return
  fi
  local ncolors
  ncolors="$(tput colors 2>/dev/null || printf "0")"
  if [ "${ncolors:-0}" -lt 8 ]; then
    return
  fi

  COLOR_RESET=$'\033[0m'
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
}

section() {
  printf "%b\n" "${COLOR_BOLD}${COLOR_BLUE}== $* ==${COLOR_RESET}"
}

log_ok() {
  printf "%b[ok]%b %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

log_warn() {
  printf "%b[warn]%b %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$*"
}

log_error() {
  printf "%b[error]%b %s\n" "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

print_kv() {
  local key="$1"
  local value="$2"
  printf "  %-24s %s\n" "$key" "$value"
}

mask_secret() {
  local raw="$1"
  local n
  n=${#raw}
  if [ "$n" -eq 0 ]; then
    printf "(empty)"
    return
  fi
  if [ "$n" -le 6 ]; then
    printf "*** (%s chars)" "$n"
    return
  fi
  printf "%s...%s (%s chars)" "${raw:0:3}" "${raw:$((n-2)):2}" "$n"
}

mask_url_for_log() {
  local raw="$1"
  if [ -z "$raw" ]; then
    printf "(empty)"
    return
  fi
  case "$raw" in
    *\?*)
      printf "%s?***" "${raw%%\?*}"
      ;;
    *)
      printf "%s" "$raw"
      ;;
  esac
}

single_line() {
  printf "%s" "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

render_status() {
  local status="$1"
  case "$status" in
    OK)
      printf "%bOK%b" "$COLOR_GREEN" "$COLOR_RESET"
      ;;
    FAILED)
      printf "%bFAILED%b" "$COLOR_RED" "$COLOR_RESET"
      ;;
    SKIPPED)
      printf "%bSKIPPED%b" "$COLOR_YELLOW" "$COLOR_RESET"
      ;;
    *)
      printf "%s" "$status"
      ;;
  esac
}

print_runtime_overview() {
  section "Install Inputs"
  print_kv "openclaw.bin" "$OPENCLAW_BIN"
  print_kv "npm.bin" "$NPM_BIN"
  print_kv "target.dir" "$TARGET_DIR"
  print_kv "openclaw.config" "$OPENCLAW_CONFIG_PATH"
  print_kv "package.url" "$(mask_url_for_log "$TGZ_URL")"
  print_kv "search.enabled" "$SEARCH_PLUGIN_ENABLED"
  if [ "$SEARCH_PLUGIN_ENABLED" = "1" ]; then
    print_kv "search.package.url" "$(mask_url_for_log "$SEARCH_TGZ_URL")"
    print_kv "search.target.dir" "$SEARCH_TARGET_DIR"
  fi
  print_kv "bridge.mode" "$BRIDGE_MODE"
  print_kv "bridge.url" "$(mask_url_for_log "$WS_URL")"
  print_kv "bridge.token" "$(mask_secret "$BOT_TOKEN")"
  print_kv "bridge.kimiapiHost" "$(mask_url_for_log "$KIMIAPI_HOST")"
  print_kv "gateway.url" "$(mask_url_for_log "$GATEWAY_URL")"
  print_kv "gateway.token" "$(mask_secret "$GATEWAY_TOKEN")"
  print_kv "gateway.token_source" "$GATEWAY_TOKEN_SOURCE"
  print_kv "gateway.agentId" "$GATEWAY_AGENT_ID"
  print_kv "retry.baseMs" "$RETRY_BASE_MS"
  print_kv "retry.maxMs" "$RETRY_MAX_MS"
  print_kv "retry.maxAttempts" "$RETRY_MAX_ATTEMPTS"
  print_kv "bridge.historyPendingTimeoutMs" "$HISTORY_PENDING_TIMEOUT_MS"
  print_kv "log.enabled" "$LOG_ENABLED"
  print_kv "check.bridge" "$BRIDGE_CHECK_ENABLED"
  print_kv "check.gateway" "$GATEWAY_CHECK_ENABLED"
  print_kv "allow.missing.bridge" "$ALLOW_MISSING_BRIDGE_CONFIG"
  print_kv "setup.defaultModel" "$SETUP_DEFAULT_MODEL"
  if [ -n "$MODEL_ID" ]; then
    print_kv "defaultModel.modelId" "$MODEL_ID"
  fi
  print_kv "check.gateway.retries" "$GATEWAY_CHECK_RETRIES"
  print_kv "check.gateway.interval" "${GATEWAY_CHECK_INTERVAL_MS}ms"
  print_kv "check.gateway.initial_delay" "${GATEWAY_CHECK_INITIAL_DELAY_MS}ms"
}

print_connectivity_summary() {
  local overall="OK"
  if [ "$BRIDGE_CHECK_STATUS" = "FAILED" ] || [ "$GATEWAY_CHECK_STATUS" = "FAILED" ]; then
    overall="FAILED"
  elif [ "$BRIDGE_CHECK_STATUS" = "SKIPPED" ] || [ "$GATEWAY_CHECK_STATUS" = "SKIPPED" ]; then
    overall="SKIPPED"
  fi
  section "Connectivity Summary"
  printf "  %-24s %s\n" "bridge.check" "$(render_status "$BRIDGE_CHECK_STATUS")"
  print_kv "bridge.detail" "$(single_line "$BRIDGE_CHECK_MESSAGE")"
  printf "  %-24s %s\n" "gateway.check" "$(render_status "$GATEWAY_CHECK_STATUS")"
  print_kv "gateway.detail" "$(single_line "$GATEWAY_CHECK_MESSAGE")"
  printf "  %-24s %s\n" "overall.connectivity" "$(render_status "$overall")"
}

print_bridge_troubleshooting() {
  section "Bridge Troubleshooting"
  log_warn "bridge auth/connectivity probe failed."
  log_warn "next-step commands:"
  log_warn "  curl -fsSL https://cdn.kimi.com/kimi-claw/install.sh | \\"
  log_warn "    bash -s -- --ws-url \"$(mask_url_for_log "$WS_URL")\" --bot-token '<BOT_TOKEN>' --skip-bridge-check"
  log_warn "  $OPENCLAW_BIN config get \"plugins.entries.kimi-claw.config.bridge.url\""
  log_warn "  $OPENCLAW_BIN config get \"plugins.entries.kimi-claw.config.bridge.token\""
  log_warn "  verify bridge token/endpoint or retry later if bridge is temporarily busy"
}

print_gateway_troubleshooting() {
  section "Gateway Troubleshooting"
  log "local gateway handshake still failing after retries."
  log "next-step commands:"
  log "  $OPENCLAW_BIN gateway status"
  log "  $OPENCLAW_BIN gateway restart"
  log "  $OPENCLAW_BIN config get gateway.auth.token"
  log "  curl -fsSL https://cdn.kimi.com/kimi-claw/install.sh | \\"
  log "    bash -s -- --ws-url \"$(mask_url_for_log "$WS_URL")\" --bot-token '<BOT_TOKEN>' --gateway-url \"$(mask_url_for_log "$GATEWAY_URL")\" --skip-gateway-check"

  if ! command -v "$OPENCLAW_BIN" >/dev/null 2>&1; then
    return
  fi

  local status_out status_rc
  set +e
  status_out="$($OPENCLAW_BIN gateway status 2>&1)"
  status_rc=$?
  set -e
  if [ "$status_rc" -eq 0 ] && [ -n "$status_out" ]; then
    log "gateway status output:"
    while IFS= read -r line; do
      log "  $line"
    done <<<"$status_out"
  elif [ "$status_rc" -ne 0 ]; then
    log "failed to run '$OPENCLAW_BIN gateway status': $status_out"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  curl -fsSL https://cdn.kimi.com/kimi-claw/install.sh | bash -s -- [options]

Optional:
  --ws-url <ws_url>              Bridge server WebSocket URL (alias: --bridge-url)
                                 default: wss://www.kimi.com/api-claw/bots/agent-ws
  --bot-token <token>            Kimi bot token (X-Kimi-Bot-Token)
  --tgz-url <url|s3://...>       Override package URL
  --target-dir <path>            Install directory for plugin
  --with-search-plugin           Install kimi-search plugin together (default: disabled)
  --search-tgz-url <url|s3://...> Override kimi-search package URL
  --search-target-dir <path>     Install directory for kimi-search plugin
  --skip-search-plugin           Explicitly disable kimi-search plugin install
  --bridge-mode <acp>            Default: acp
  --bridge-user-id <user_id>     Deprecated: ignored (ACP-only)
  --kimiapi-host <url>           Default: https://www.kimi.com/api-claw
  --gateway-url <ws_url>         Default: ws://127.0.0.1:18789
  --gateway-token <token>        If omitted, tries openclaw gateway.auth.token
  --agent-id <id>                Default: main
  --retry-base-ms <ms>           Default: 1000
  --retry-max-ms <ms>            Default: 600000
  --retry-max-attempts <n>       Default: 0
  --log-enabled <true|false>     Enable connector trace logs (default: false)
  --skip-bridge-check            Skip bridge ws auth/connectivity probe
  --bridge-check-timeout-ms <n>  Default: 6000
  --bridge-check-settle-ms <n>   Default: 800
  --skip-gateway-check           Skip local gateway handshake probe
  --skip-connectivity-checks     Skip bridge+gateway checks and allow missing bridge runtime config
  --allow-missing-bridge-config  Allow install without explicit --ws-url/--bot-token (default enabled)
  --setup-default-model          Enable auto-configure of default model (1P only)
  --model-id <id>                Override default model ID (default: k2p5)
  --gateway-check-timeout-ms <n> Default: 8000
  --gateway-check-settle-ms <n>  Default: 600
  --gateway-check-retries <n>    Default: 10
  --gateway-check-interval-ms <n> Default: 5000
  --gateway-check-initial-delay-ms <n> Default: 5000
  -h, --help

Examples:
  curl -fsSL https://cdn.kimi.com/kimi-claw/install.sh | \
    bash -s --

  curl -fsSL https://cdn.kimi.com/kimi-claw/install.sh | \
    bash -s -- --bridge-url wss://bridge.example.com/acp --bot-token sk_live_xxx --with-search-plugin --skip-gateway-check
USAGE
}

parse_bool_flag() {
  local raw="$1"
  local normalized
  normalized="$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    1|true|yes|on)
      printf "1"
      return 0
      ;;
    0|false|no|off)
      printf "0"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "missing command: $cmd"
    log_error "$hint"
    exit 1
  fi
}

download_to_file() {
  local src="$1"
  local dest="$2"
  case "$src" in
    s3://*)
      require_cmd aws "install aws cli and configure credentials/profile first"
      AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
      AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      aws s3 cp "$src" "$dest" >/dev/null
      ;;
    *)
      require_cmd curl "install curl then retry"
      curl -fsSL "$src" -o "$dest"
      ;;
  esac
}

sleep_ms() {
  local ms="$1"
  local seconds
  seconds="$(awk "BEGIN { printf \"%.3f\", (${ms} / 1000) }")"
  sleep "$seconds"
}

check_bridge_ws_auth() {
  local output rc
  set +e
  output=$(
    {
      cd "$TARGET_DIR" && \
        WS_URL="$WS_URL" \
        BOT_TOKEN="$BOT_TOKEN" \
        BRIDGE_CHECK_TIMEOUT_MS="$BRIDGE_CHECK_TIMEOUT_MS" \
        BRIDGE_CHECK_SETTLE_MS="$BRIDGE_CHECK_SETTLE_MS" \
        node --input-type=module - <<'NODE'
import WebSocket from "ws";

const url = String(process.env.WS_URL ?? "").trim();
const token = String(process.env.BOT_TOKEN ?? "");
const timeoutMs = Number(process.env.BRIDGE_CHECK_TIMEOUT_MS ?? "6000");
const settleMs = Number(process.env.BRIDGE_CHECK_SETTLE_MS ?? "800");
const headerName = "X-Kimi-Bot-Token";

if (!url) {
  console.error("missing ws url");
  process.exit(2);
}
if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  console.error("invalid BRIDGE_CHECK_TIMEOUT_MS");
  process.exit(2);
}
if (!Number.isFinite(settleMs) || settleMs < 0) {
  console.error("invalid BRIDGE_CHECK_SETTLE_MS");
  process.exit(2);
}

let done = false;
let opened = false;
let settled = false;
let settleTimer = null;

const finish = (ok, message) => {
  if (done) {
    return;
  }
  done = true;
  clearTimeout(overallTimer);
  if (settleTimer) {
    clearTimeout(settleTimer);
  }
  if (ok) {
    console.log(message);
    process.exit(0);
  }
  console.error(message);
  process.exit(1);
};

const headers = token ? { [headerName]: token } : {};
const ws = new WebSocket(url, {
  headers,
  handshakeTimeout: timeoutMs,
});

const overallTimer = setTimeout(() => {
  finish(false, `timeout after ${timeoutMs}ms`);
}, timeoutMs + settleMs + 500);

ws.on("unexpected-response", (_req, res) => {
  const status = Number(res?.statusCode ?? 0);
  if (status === 401 || status === 403) {
    finish(false, `auth rejected by bridge (http ${status})`);
    return;
  }
  finish(false, `unexpected http response ${status || "unknown"}`);
});

ws.on("open", () => {
  opened = true;
  settleTimer = setTimeout(() => {
    settled = true;
    try {
      ws.close(1000, "probe done");
    } catch {
      // ignore
    }
    finish(true, `ws connected and auth accepted (${url})`);
  }, settleMs);
});

ws.on("close", (code, reason) => {
  const reasonText = reason?.toString() || "";

  if (code === 1013) {
    finish(
      true,
      `bridge reachable and auth passed, but server is busy (close=${code}${reasonText ? ` ${reasonText}` : ""})`,
    );
    return;
  }

  if (!opened) {
    if (code === 4001 || code === 1008) {
      finish(false, `auth rejected by bridge (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
      return;
    }
    finish(false, `connection closed before websocket open (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
    return;
  }

  if (!settled) {
    if (code === 4001 || code === 1008) {
      finish(false, `auth rejected by bridge (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
      return;
    }
    finish(false, `connection dropped during settle window (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
  }
});

ws.on("error", (err) => {
  const msg = err instanceof Error ? err.message : String(err);
  if (/401|403|unauthor|forbidden/i.test(msg)) {
    finish(false, `auth rejected by bridge (${msg})`);
    return;
  }
  finish(false, `websocket connect error (${msg})`);
});
NODE
    } 2>&1
  )
  rc=$?
  set -e
  BRIDGE_CHECK_MESSAGE="$output"
  [ "$rc" -eq 0 ]
}

check_gateway_ws_handshake() {
  local output rc
  set +e
  output=$(
    {
      cd "$TARGET_DIR" && \
        GATEWAY_URL="$GATEWAY_URL" \
        GATEWAY_TOKEN="$GATEWAY_TOKEN" \
        GATEWAY_CHECK_TIMEOUT_MS="$GATEWAY_CHECK_TIMEOUT_MS" \
        GATEWAY_CHECK_SETTLE_MS="$GATEWAY_CHECK_SETTLE_MS" \
        node --input-type=module - <<'NODE'
import WebSocket from "ws";

const url = String(process.env.GATEWAY_URL ?? "").trim();
const token = String(process.env.GATEWAY_TOKEN ?? "");
const timeoutMs = Number(process.env.GATEWAY_CHECK_TIMEOUT_MS ?? "8000");
const settleMs = Number(process.env.GATEWAY_CHECK_SETTLE_MS ?? "600");

if (!url) {
  console.error("missing gateway url");
  process.exit(2);
}
if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  console.error("invalid GATEWAY_CHECK_TIMEOUT_MS");
  process.exit(2);
}
if (!Number.isFinite(settleMs) || settleMs < 0) {
  console.error("invalid GATEWAY_CHECK_SETTLE_MS");
  process.exit(2);
}

let done = false;
let opened = false;
let connectSent = false;
let settleTimer = null;

const finish = (ok, message) => {
  if (done) {
    return;
  }
  done = true;
  clearTimeout(overallTimer);
  if (settleTimer) {
    clearTimeout(settleTimer);
  }
  if (ok) {
    console.log(message);
    process.exit(0);
  }
  console.error(message);
  process.exit(1);
};

const ws = new WebSocket(url, {
  handshakeTimeout: timeoutMs,
});

const sendConnect = () => {
  if (connectSent || ws.readyState !== WebSocket.OPEN) {
    return;
  }
  connectSent = true;
  const params = {
    minProtocol: 3,
    maxProtocol: 3,
    client: {
      id: "gateway-client",
      version: "0.0.0",
      platform: process.platform,
      mode: "backend",
      displayName: "kimi-claw-installer",
    },
    role: "operator",
    scopes: ["operator.admin"],
    caps: ["tool-events"],
  };
  if (token) {
    params.auth = { token };
  }
  const frame = {
    type: "req",
    id: "connect",
    method: "connect",
    params,
  };
  try {
    ws.send(JSON.stringify(frame));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    finish(false, `failed to send gateway connect frame (${msg})`);
  }
};

const overallTimer = setTimeout(() => {
  finish(false, `timeout after ${timeoutMs}ms`);
}, timeoutMs + settleMs + 500);

ws.on("unexpected-response", (_req, res) => {
  const status = Number(res?.statusCode ?? 0);
  finish(false, `unexpected http response ${status || "unknown"}`);
});

ws.on("open", () => {
  opened = true;
  setTimeout(sendConnect, 250);
});

ws.on("message", (data) => {
  let parsed;
  try {
    parsed = JSON.parse(data.toString());
  } catch {
    return;
  }
  if (!parsed || typeof parsed !== "object") {
    return;
  }
  if (parsed.type === "event" && parsed.event === "connect.challenge") {
    sendConnect();
    return;
  }
  if (parsed.type === "res" && parsed.id === "connect") {
    if (!parsed.ok) {
      const errMsg =
        parsed.error && typeof parsed.error === "object" && typeof parsed.error.message === "string"
          ? parsed.error.message
          : "connect rejected";
      finish(false, `gateway handshake rejected (${errMsg})`);
      return;
    }
    settleTimer = setTimeout(() => {
      try {
        ws.close(1000, "probe done");
      } catch {
        // ignore close error
      }
      finish(true, `gateway handshake complete (${url})`);
    }, settleMs);
  }
});

ws.on("close", (code, reason) => {
  if (done) {
    return;
  }
  const reasonText = reason?.toString() || "";
  if (!opened) {
    finish(false, `gateway connection closed before open (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
    return;
  }
  finish(false, `gateway connection closed during handshake (close=${code}${reasonText ? ` ${reasonText}` : ""})`);
});

ws.on("error", (err) => {
  const msg = err instanceof Error ? err.message : String(err);
  finish(false, `gateway websocket error (${msg})`);
});
NODE
    } 2>&1
  )
  rc=$?
  set -e
  GATEWAY_CHECK_MESSAGE="$output"
  [ "$rc" -eq 0 ]
}

cleanup_legacy_plugin_config() {
  local config_path="$OPENCLAW_CONFIG_PATH"
  if [ "${config_path#\~}" != "$config_path" ]; then
    config_path="$HOME${config_path#\~}"
  fi
  if [ ! -f "$config_path" ]; then
    return
  fi

  OPENCLAW_CONFIG_PATH="$config_path" TARGET_DIR="$TARGET_DIR" node - <<'NODE'
const fs = require("fs");
const path = require("path");

const expandUserPath = (value) => {
  if (typeof value !== "string") {
    return "";
  }
  if (value === "~") {
    return process.env.HOME || value;
  }
  if (value.startsWith("~/")) {
    return path.join(process.env.HOME || "", value.slice(2));
  }
  return value;
};

const configPath = path.resolve(expandUserPath(process.env.OPENCLAW_CONFIG_PATH || ""));
const targetDir = path.resolve(expandUserPath(process.env.TARGET_DIR || ""));
const legacyDir = path.resolve(path.dirname(targetDir), "openclaw-kimi-bridge-connector");

let payload;
try {
  payload = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch {
  process.exit(0);
}

if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
  process.exit(0);
}

let changed = false;
const plugins =
  payload.plugins && typeof payload.plugins === "object" && !Array.isArray(payload.plugins)
    ? payload.plugins
    : {};
if (payload.plugins !== plugins) {
  payload.plugins = plugins;
  changed = true;
}

const entries = plugins.entries;
if (entries && typeof entries === "object" && !Array.isArray(entries)) {
  if (Object.prototype.hasOwnProperty.call(entries, "openclaw-kimi-bridge-connector")) {
    delete entries["openclaw-kimi-bridge-connector"];
    changed = true;
  }
}

const installs = plugins.installs;
if (installs && typeof installs === "object" && !Array.isArray(installs)) {
  if (Object.prototype.hasOwnProperty.call(installs, "openclaw-kimi-bridge-connector")) {
    delete installs["openclaw-kimi-bridge-connector"];
    changed = true;
  }
}

const load =
  plugins.load && typeof plugins.load === "object" && !Array.isArray(plugins.load)
    ? plugins.load
    : {};
if (plugins.load !== load) {
  plugins.load = load;
  changed = true;
}

const rawPaths = Array.isArray(load.paths) ? load.paths : [];
if (!Array.isArray(load.paths)) {
  changed = true;
}

const normalized = [];
const seen = new Set();
for (const raw of rawPaths) {
  if (typeof raw !== "string") {
    changed = true;
    continue;
  }
  const resolved = path.resolve(expandUserPath(raw));
  if (resolved === legacyDir) {
    changed = true;
    continue;
  }
  if (seen.has(resolved)) {
    changed = true;
    continue;
  }
  seen.add(resolved);
  normalized.push(resolved);
}

if (!seen.has(targetDir)) {
  normalized.push(targetDir);
  changed = true;
}

if (!Array.isArray(load.paths) || load.paths.length !== normalized.length || load.paths.some((value, index) => value !== normalized[index])) {
  load.paths = normalized;
  changed = true;
}

  if (changed) {
    fs.writeFileSync(configPath, `${JSON.stringify(payload, null, 2)}\n`);
  }
NODE
}

sync_search_plugin_api_key_from_local_config() {
  local config_path="$DEFAULT_LOCAL_CONFIG_PATH"
  if [ "${config_path#\~}" != "$config_path" ]; then
    config_path="$HOME${config_path#\~}"
  fi

  if [ ! -f "$config_path" ]; then
    log_warn "local config not found, skip kimiPluginAPIKey fallback: $config_path"
    return
  fi

  local sync_result
  sync_result="$(
    LOCAL_CFG="$config_path" node - <<'NODE'
const fs = require("fs");

const configPath = process.env.LOCAL_CFG || "";
if (!configPath) {
  process.stdout.write("invalid_path");
  process.exit(0);
}

try {
  const raw = fs.readFileSync(configPath, "utf8");
  const payload = JSON.parse(raw);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    process.stdout.write("invalid_json_shape");
    process.exit(0);
  }

  const bridge =
    payload.bridge && typeof payload.bridge === "object" && !Array.isArray(payload.bridge)
      ? payload.bridge
      : {};
  if (payload.bridge !== bridge) {
    payload.bridge = bridge;
  }

  const pluginApiKey =
    typeof bridge.kimiPluginAPIKey === "string" ? bridge.kimiPluginAPIKey.trim() : "";
  if (pluginApiKey) {
    process.stdout.write("already_set");
    process.exit(0);
  }

  const codeApiKey =
    typeof bridge.kimiCodeAPIKey === "string" ? bridge.kimiCodeAPIKey.trim() : "";
  if (!codeApiKey) {
    process.stdout.write("missing_kimi_code_api_key");
    process.exit(0);
  }

  bridge.kimiPluginAPIKey = codeApiKey;
  fs.writeFileSync(configPath, `${JSON.stringify(payload, null, 2)}\n`);
  process.stdout.write("updated");
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stdout.write(`error:${message}`);
}
NODE
  )"

  case "$sync_result" in
    updated)
      log "synced bridge.kimiPluginAPIKey from bridge.kimiCodeAPIKey in $config_path"
      ;;
    already_set)
      log "bridge.kimiPluginAPIKey already set in $config_path"
      ;;
    missing_kimi_code_api_key)
      log_warn "bridge.kimiPluginAPIKey is empty and bridge.kimiCodeAPIKey is missing in $config_path"
      ;;
    invalid_json_shape)
      log_warn "local config is not a JSON object; skip kimiPluginAPIKey fallback: $config_path"
      ;;
    invalid_path)
      log_warn "invalid local config path; skip kimiPluginAPIKey fallback"
      ;;
    error:*)
      log_warn "failed to sync kimiPluginAPIKey in $config_path: $(single_line "${sync_result#error:}")"
      ;;
    *)
      log_warn "unexpected kimiPluginAPIKey sync result ($sync_result); continuing"
      ;;
  esac
}

init_colors

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ws-url|--bridge-url)
      WS_URL="${2:-}"
      shift 2
      ;;
    --bot-token)
      BOT_TOKEN="${2:-}"
      shift 2
      ;;
    --tgz-url)
      TGZ_URL="${2:-}"
      shift 2
      ;;
    --target-dir)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --with-search-plugin)
      SEARCH_PLUGIN_ENABLED="1"
      shift
      ;;
    --search-tgz-url)
      SEARCH_TGZ_URL="${2:-}"
      shift 2
      ;;
    --search-target-dir)
      SEARCH_TARGET_DIR="${2:-}"
      shift 2
      ;;
    --skip-search-plugin)
      SEARCH_PLUGIN_ENABLED="0"
      shift
      ;;
    --bridge-mode)
      BRIDGE_MODE="${2:-}"
      shift 2
      ;;
    --bridge-user-id)
      BRIDGE_USER_ID="${2:-}"
      log_warn "--bridge-user-id is deprecated and ignored (ACP-only mode)"
      shift 2
      ;;
    --kimiapi-host)
      KIMIAPI_HOST="${2:-}"
      shift 2
      ;;
    --gateway-url)
      GATEWAY_URL="${2:-}"
      shift 2
      ;;
    --gateway-token)
      GATEWAY_TOKEN="${2:-}"
      shift 2
      ;;
    --agent-id)
      GATEWAY_AGENT_ID="${2:-}"
      shift 2
      ;;
    --retry-base-ms)
      RETRY_BASE_MS="${2:-}"
      shift 2
      ;;
    --retry-max-ms)
      RETRY_MAX_MS="${2:-}"
      shift 2
      ;;
    --retry-max-attempts)
      RETRY_MAX_ATTEMPTS="${2:-}"
      shift 2
      ;;
    --log-enabled)
      LOG_ENABLED="${2:-}"
      shift 2
      ;;
    --skip-bridge-check)
      BRIDGE_CHECK_ENABLED="0"
      shift
      ;;
    --bridge-check-timeout-ms)
      BRIDGE_CHECK_TIMEOUT_MS="${2:-}"
      shift 2
      ;;
    --bridge-check-settle-ms)
      BRIDGE_CHECK_SETTLE_MS="${2:-}"
      shift 2
      ;;
    --skip-gateway-check)
      GATEWAY_CHECK_ENABLED="0"
      shift
      ;;
    --skip-connectivity-checks)
      BRIDGE_CHECK_ENABLED="0"
      GATEWAY_CHECK_ENABLED="0"
      ALLOW_MISSING_BRIDGE_CONFIG="1"
      shift
      ;;
    --allow-missing-bridge-config)
      ALLOW_MISSING_BRIDGE_CONFIG="1"
      shift
      ;;
    --setup-default-model)
      SETUP_DEFAULT_MODEL="1"
      shift
      ;;
    --model-id)
      MODEL_ID="${2:-}"
      shift 2
      ;;
    --gateway-check-timeout-ms)
      GATEWAY_CHECK_TIMEOUT_MS="${2:-}"
      shift 2
      ;;
    --gateway-check-settle-ms)
      GATEWAY_CHECK_SETTLE_MS="${2:-}"
      shift 2
      ;;
    --gateway-check-retries)
      GATEWAY_CHECK_RETRIES="${2:-}"
      shift 2
      ;;
    --gateway-check-interval-ms)
      GATEWAY_CHECK_INTERVAL_MS="${2:-}"
      shift 2
      ;;
    --gateway-check-initial-delay-ms)
      GATEWAY_CHECK_INITIAL_DELAY_MS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

LOG_ENABLED_RAW="$LOG_ENABLED"
if ! LOG_ENABLED="$(parse_bool_flag "$LOG_ENABLED_RAW")"; then
  log_error "invalid --log-enabled value: '$LOG_ENABLED_RAW' (expected true/false)"
  usage
  exit 1
fi

if [ -z "$WS_URL" ] || [ -z "$BOT_TOKEN" ]; then
  if [ -f "$DEFAULT_LOCAL_CONFIG_PATH" ]; then
    log "loading missing parameters from local config: $DEFAULT_LOCAL_CONFIG_PATH"
    if [ -z "$WS_URL" ]; then
      WS_URL="$(LOCAL_CFG="$DEFAULT_LOCAL_CONFIG_PATH" node - <<'NODE'
const fs = require("fs");
try {
  const c = JSON.parse(fs.readFileSync(process.env.LOCAL_CFG, "utf-8"));
  const v = c && c.bridge && typeof c.bridge.url === "string" ? c.bridge.url.trim() : "";
  process.stdout.write(v);
} catch { /* ignore */ }
NODE
      )" || true
      if [ -n "$WS_URL" ]; then
        log "bridge.url loaded from local config: $(mask_url_for_log "$WS_URL")"
      fi
    fi
    if [ -z "$BOT_TOKEN" ]; then
      BOT_TOKEN="$(LOCAL_CFG="$DEFAULT_LOCAL_CONFIG_PATH" node - <<'NODE'
const fs = require("fs");
try {
  const c = JSON.parse(fs.readFileSync(process.env.LOCAL_CFG, "utf-8"));
  const v = c && c.bridge && typeof c.bridge.token === "string" ? c.bridge.token.trim() : "";
  process.stdout.write(v);
} catch { /* ignore */ }
NODE
      )" || true
      if [ -n "$BOT_TOKEN" ]; then
        log "bridge.token loaded from local config: $(mask_secret "$BOT_TOKEN")"
      fi
    fi
  fi
fi

if [ -z "$BOT_TOKEN" ]; then
  _cfg_path="$OPENCLAW_CONFIG_PATH"
  if [ "${_cfg_path#\~}" != "$_cfg_path" ]; then
    _cfg_path="$HOME${_cfg_path#\~}"
  fi
  if [ -f "$_cfg_path" ]; then
    log "loading missing bridge.token from existing openclaw plugin config: $_cfg_path"
    if [ -z "$BOT_TOKEN" ]; then
      BOT_TOKEN="$(OPENCLAW_CFG="$_cfg_path" node - <<'NODE'
const fs = require("fs");
try {
  const c = JSON.parse(fs.readFileSync(process.env.OPENCLAW_CFG, "utf-8"));
  const entries = c && c.plugins && c.plugins.entries;
  if (!entries) { process.exit(0); }
  const cfg = (entries["kimi-claw"] && entries["kimi-claw"].config)
    || (entries["openclaw-kimi-bridge-connector"] && entries["openclaw-kimi-bridge-connector"].config);
  if (!cfg || !cfg.bridge) { process.exit(0); }
  const v = typeof cfg.bridge.token === "string" ? cfg.bridge.token.trim() : "";
  process.stdout.write(v);
} catch { /* ignore */ }
NODE
      )" || true
      if [ -n "$BOT_TOKEN" ]; then
        log "bridge.token loaded from existing openclaw config: $(mask_secret "$BOT_TOKEN")"
      fi
    fi
  fi
fi

if [ -z "$WS_URL" ]; then
  WS_URL="$DEFAULT_BRIDGE_URL"
  log "bridge.url not provided; using default: $(mask_url_for_log "$WS_URL")"
fi

if [ -n "$WS_URL" ]; then
  HAS_BRIDGE_CONFIG="1"
fi

if [ "$HAS_BRIDGE_CONFIG" = "1" ] && [ -z "$BOT_TOKEN" ] && [ "$BRIDGE_CHECK_ENABLED" = "1" ]; then
  log_warn "bridge.token not set; skip bridge auth/connectivity probe"
  BRIDGE_CHECK_ENABLED="0"
  BRIDGE_CHECK_MESSAGE="skipped because bridge.token is empty"
fi

if [ "$HAS_BRIDGE_CONFIG" != "1" ]; then
  if [ "$ALLOW_MISSING_BRIDGE_CONFIG" = "1" ]; then
    log_warn "bridge.url missing; continuing install without bridge runtime config"
    BRIDGE_CHECK_ENABLED="0"
    BRIDGE_CHECK_MESSAGE="skipped because bridge.url is empty"
  else
    log_error "missing required argument: --ws-url (not found in local config either)"
    usage
    exit 1
  fi
fi

if [ "$BRIDGE_MODE" != "acp" ]; then
  log_error "invalid --bridge-mode: $BRIDGE_MODE (ACP-only; expected acp)"
  exit 1
fi

if [ "${TARGET_DIR#\~}" != "$TARGET_DIR" ]; then
  TARGET_DIR="$HOME${TARGET_DIR#\~}"
fi
if [ "${SEARCH_TARGET_DIR#\~}" != "$SEARCH_TARGET_DIR" ]; then
  SEARCH_TARGET_DIR="$HOME${SEARCH_TARGET_DIR#\~}"
fi
if [ "${OPENCLAW_CONFIG_PATH#\~}" != "$OPENCLAW_CONFIG_PATH" ]; then
  OPENCLAW_CONFIG_PATH="$HOME${OPENCLAW_CONFIG_PATH#\~}"
fi

require_cmd tar "install tar then retry"
require_cmd "$NPM_BIN" "install Node.js + npm then retry"
require_cmd "$OPENCLAW_BIN" "install OpenClaw CLI then retry"
require_cmd node "install Node.js then retry"

# Previous versions of this installer moved old plugin dirs to `${TARGET_DIR}.bak.<timestamp>`.
# Those backups live under `~/.openclaw/extensions` and get discovered as duplicate plugins,
# which makes *every* `openclaw` command print duplicate-plugin warnings. Migrate them out of
# the extensions scan path before running any OpenClaw CLI commands.
BACKUP_STASH_ROOT="${BACKUP_STASH_ROOT:-$HOME/.openclaw/extensions-backups}"
BACKUP_STASH_DIR="${BACKUP_STASH_DIR:-$BACKUP_STASH_ROOT/kimi-claw}"
RUN_TS="$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_STASH_DIR"
shopt -s nullglob
for legacy in "${TARGET_DIR}".bak.*; do
  if [ -e "$legacy" ]; then
    dest="$BACKUP_STASH_DIR/$(basename "$legacy").migrated.${RUN_TS}.$$"
    if mv "$legacy" "$dest"; then
      log_warn "migrated legacy backup out of extensions: $legacy -> $dest"
    else
      log_warn "failed to migrate legacy backup (permission/lock?): $legacy"
    fi
  fi
done
shopt -u nullglob

# If we're reinstalling over an existing install, stop it first to avoid bridge session conflicts.
if [ -e "$TARGET_DIR" ]; then
  log_warn "existing install detected; disabling connector before reinstall: $TARGET_DIR"
  "$OPENCLAW_BIN" plugins disable "kimi-claw" >/dev/null 2>&1 || true
  "$OPENCLAW_BIN" plugins disable "openclaw-kimi-bridge-connector" >/dev/null 2>&1 || true
  if "$OPENCLAW_BIN" gateway restart >/dev/null 2>&1; then
    log "gateway restarted to release existing bridge session"
    sleep 1
  fi
fi

if [ "$SEARCH_PLUGIN_ENABLED" = "1" ] && [ -e "$SEARCH_TARGET_DIR" ]; then
  log_warn "existing kimi-search install detected; disabling before reinstall: $SEARCH_TARGET_DIR"
  "$OPENCLAW_BIN" plugins disable "kimi-search" >/dev/null 2>&1 || true
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

section "Package Fetch"
log "downloading package archive"
download_to_file "$TGZ_URL" "$TMP_DIR/plugin.tgz"

section "Package Extract"
log "extracting package archive"
tar -xzf "$TMP_DIR/plugin.tgz" -C "$TMP_DIR"
SRC_DIR="$TMP_DIR/package"
if [ ! -f "$SRC_DIR/package.json" ]; then
  log_error "invalid tgz content (missing package/package.json)"
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"
if [ -e "$TARGET_DIR" ]; then
  BACKUP_DIR="$BACKUP_STASH_DIR/$(basename "$TARGET_DIR").bak.${RUN_TS}.$$"
  mv "$TARGET_DIR" "$BACKUP_DIR"
  log "existing target moved to backup (outside extensions scan path): $BACKUP_DIR"
fi
mkdir -p "$TARGET_DIR"
cp -R "$SRC_DIR"/. "$TARGET_DIR"/

section "Dependency Setup"
log "installing npm dependencies"
(cd "$TARGET_DIR" && "$NPM_BIN" install --omit=dev)

PLUGIN_NAME="kimi-claw"
if [ -f "$TARGET_DIR/openclaw.plugin.json" ]; then
  PLUGIN_ID="$(node - "$TARGET_DIR/openclaw.plugin.json" <<'NODE'
const fs = require("fs");

const filePath = process.argv[2];
if (!filePath) {
  process.stdout.write("");
  process.exit(0);
}

try {
  const payload = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const value = payload && typeof payload.id === "string" ? payload.id : "";
  process.stdout.write(value);
} catch {
  process.stdout.write("");
}
NODE
)"
  if [ -n "$PLUGIN_ID" ]; then
    PLUGIN_NAME="$PLUGIN_ID"
  fi
fi

if [ -z "$GATEWAY_TOKEN" ]; then
  # `openclaw config get` may print config warnings/UI to stdout when duplicate plugins exist.
  # Keep only the last line as the actual token value.
  GATEWAY_TOKEN="$($OPENCLAW_BIN config get gateway.auth.token 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
  if [ -n "$GATEWAY_TOKEN" ]; then
    GATEWAY_TOKEN_SOURCE="openclaw.gateway.auth.token"
  else
    GATEWAY_TOKEN_SOURCE="empty"
  fi
fi

print_runtime_overview

section "Bridge Check"
if [ "$BRIDGE_CHECK_ENABLED" = "1" ]; then
  log "checking bridge websocket auth/connectivity"
  if check_bridge_ws_auth; then
    BRIDGE_CHECK_STATUS="OK"
    log_ok "$BRIDGE_CHECK_MESSAGE"
  else
    BRIDGE_CHECK_STATUS="FAILED"
    log_error "$BRIDGE_CHECK_MESSAGE"
    print_bridge_troubleshooting
    GATEWAY_CHECK_STATUS="SKIPPED"
    GATEWAY_CHECK_MESSAGE="not executed because bridge check failed"
    print_connectivity_summary
    exit 1
  fi
else
  BRIDGE_CHECK_STATUS="SKIPPED"
  if [ "$BRIDGE_CHECK_MESSAGE" = "not executed" ]; then
    BRIDGE_CHECK_MESSAGE="skipped by --skip-bridge-check"
  fi
  log_warn "bridge websocket auth/connectivity check skipped"
fi

CONFIG_JSON=""
if [ "$HAS_BRIDGE_CONFIG" = "1" ]; then
CONFIG_JSON="$(
BRIDGE_MODE="$BRIDGE_MODE" \
WS_URL="$WS_URL" \
BOT_TOKEN="$BOT_TOKEN" \
KIMIAPI_HOST="$KIMIAPI_HOST" \
BRIDGE_INSTANCE_ID="$BRIDGE_INSTANCE_ID" \
BRIDGE_DEVICE_ID="$BRIDGE_DEVICE_ID" \
GATEWAY_URL="$GATEWAY_URL" \
GATEWAY_TOKEN="$GATEWAY_TOKEN" \
GATEWAY_AGENT_ID="$GATEWAY_AGENT_ID" \
RETRY_BASE_MS="$RETRY_BASE_MS" \
RETRY_MAX_MS="$RETRY_MAX_MS" \
RETRY_MAX_ATTEMPTS="$RETRY_MAX_ATTEMPTS" \
HISTORY_PENDING_TIMEOUT_MS="$HISTORY_PENDING_TIMEOUT_MS" \
LOG_ENABLED="$LOG_ENABLED" \
SETUP_DEFAULT_MODEL="$SETUP_DEFAULT_MODEL" \
MODEL_ID="$MODEL_ID" \
node - <<'NODE'
const parseIntStrict = (name) => {
  const raw = String(process.env[name] ?? "").trim();
  if (!/^-?\d+$/.test(raw)) {
    console.error(`invalid integer value for ${name}: ${raw}`);
    process.exit(1);
  }
  return Number(raw);
};
const parseBool = (name, defaultValue) => {
  const raw = String(process.env[name] ?? "").trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(raw)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(raw)) {
    return false;
  }
  return defaultValue;
};

const cfg = {
  bridge: {
    mode: process.env.BRIDGE_MODE,
    url: process.env.WS_URL,
    kimiapiHost: process.env.KIMIAPI_HOST,
    instanceId: process.env.BRIDGE_INSTANCE_ID,
    deviceId: process.env.BRIDGE_DEVICE_ID,
    historyPendingTimeoutMs: parseIntStrict("HISTORY_PENDING_TIMEOUT_MS"),
  },
  gateway: {
    url: process.env.GATEWAY_URL,
    agentId: process.env.GATEWAY_AGENT_ID,
  },
  retry: {
    baseMs: parseIntStrict("RETRY_BASE_MS"),
    maxMs: parseIntStrict("RETRY_MAX_MS"),
    maxAttempts: parseIntStrict("RETRY_MAX_ATTEMPTS"),
  },
  log: {
    enabled: parseBool("LOG_ENABLED", false),
  },
};

if (process.env.BOT_TOKEN) {
  cfg.bridge.token = process.env.BOT_TOKEN;
}

if (process.env.GATEWAY_TOKEN) {
  cfg.gateway.token = process.env.GATEWAY_TOKEN;
}

if (process.env.SETUP_DEFAULT_MODEL === "1") {
  cfg.defaultModel = { enabled: true };
  if (process.env.MODEL_ID) {
    cfg.defaultModel.modelId = process.env.MODEL_ID;
  }
}

process.stdout.write(JSON.stringify(cfg));
NODE
)"
fi

cleanup_legacy_plugin_config

section "Plugin Configure"
log "linking and enabling plugin"
$OPENCLAW_BIN plugins install -l "$TARGET_DIR" || true
$OPENCLAW_BIN plugins enable "$PLUGIN_NAME" || true

if [ "$HAS_BRIDGE_CONFIG" = "1" ]; then
  log "writing plugin config"
  $OPENCLAW_BIN config set "plugins.entries.$PLUGIN_NAME.config" --json "$CONFIG_JSON"
else
  log_warn "bridge.url not set; skip updating plugins.entries.$PLUGIN_NAME.config"
  log_warn "add ~/.kimi/kimi-claw/kimi-claw-config.json later, then restart gateway/plugin"
fi

if [ "$SEARCH_PLUGIN_ENABLED" = "1" ]; then
  section "Search Plugin"
  log "downloading kimi-search package archive"
  download_to_file "$SEARCH_TGZ_URL" "$TMP_DIR/search-plugin.tgz"

  log "extracting kimi-search package archive"
  SEARCH_TMP_DIR="$TMP_DIR/search-package"
  rm -rf "$SEARCH_TMP_DIR"
  mkdir -p "$SEARCH_TMP_DIR"
  tar -xzf "$TMP_DIR/search-plugin.tgz" -C "$SEARCH_TMP_DIR"
  SEARCH_SRC_DIR="$SEARCH_TMP_DIR/package"
  if [ ! -f "$SEARCH_SRC_DIR/package.json" ]; then
    log_error "invalid kimi-search tgz content (missing package/package.json)"
    exit 1
  fi

  mkdir -p "$(dirname "$SEARCH_TARGET_DIR")"
  if [ -e "$SEARCH_TARGET_DIR" ]; then
    SEARCH_BACKUP_DIR="$BACKUP_STASH_DIR/$(basename "$SEARCH_TARGET_DIR").bak.${RUN_TS}.$$"
    mv "$SEARCH_TARGET_DIR" "$SEARCH_BACKUP_DIR"
    log "existing kimi-search target moved to backup: $SEARCH_BACKUP_DIR"
  fi
  mkdir -p "$SEARCH_TARGET_DIR"
  cp -R "$SEARCH_SRC_DIR"/. "$SEARCH_TARGET_DIR"/

  log "installing kimi-search npm dependencies"
  (cd "$SEARCH_TARGET_DIR" && "$NPM_BIN" install --omit=dev)

  SEARCH_PLUGIN_NAME="kimi-search"
  if [ -f "$SEARCH_TARGET_DIR/openclaw.plugin.json" ]; then
    SEARCH_PLUGIN_ID="$(node - "$SEARCH_TARGET_DIR/openclaw.plugin.json" <<'NODE'
const fs = require("fs");

const filePath = process.argv[2];
if (!filePath) {
  process.stdout.write("");
  process.exit(0);
}

try {
  const payload = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const value = payload && typeof payload.id === "string" ? payload.id : "";
  process.stdout.write(value);
} catch {
  process.stdout.write("");
}
NODE
)"
    if [ -n "$SEARCH_PLUGIN_ID" ]; then
      SEARCH_PLUGIN_NAME="$SEARCH_PLUGIN_ID"
    fi
  fi

  if [ "$SETUP_DEFAULT_MODEL" = "1" ]; then
    sync_search_plugin_api_key_from_local_config
  else
    log "skip kimiPluginAPIKey sync because --setup-default-model is disabled"
  fi

  log "linking and enabling kimi-search plugin"
  $OPENCLAW_BIN plugins install -l "$SEARCH_TARGET_DIR" || true
  $OPENCLAW_BIN plugins enable "$SEARCH_PLUGIN_NAME" || true
else
  section "Search Plugin"
  log_warn "skip installing kimi-search plugin (--skip-search-plugin)"
fi

section "Gateway Check"
log "restarting OpenClaw gateway"
if $OPENCLAW_BIN gateway restart; then
  log_ok "gateway restart succeeded"
else
  log "gateway restart failed (please restart manually); continuing with handshake probe"
fi

if [ "$GATEWAY_CHECK_ENABLED" = "1" ]; then
  # Enforce friendly polling defaults: >=5s interval, <=10 attempts.
  retries="$GATEWAY_CHECK_RETRIES"
  case "$retries" in
    ''|*[!0-9]*)
      retries=10
      ;;
  esac
  if [ "${retries:-0}" -lt 1 ] 2>/dev/null; then
    retries=1
  fi
  if [ "${retries:-0}" -gt 10 ] 2>/dev/null; then
    retries=10
  fi
  GATEWAY_CHECK_RETRIES="$retries"

  interval_ms="$GATEWAY_CHECK_INTERVAL_MS"
  case "$interval_ms" in
    ''|*[!0-9]*)
      interval_ms=5000
      ;;
  esac
  if [ "${interval_ms:-0}" -lt 5000 ] 2>/dev/null; then
    interval_ms=5000
  fi
  GATEWAY_CHECK_INTERVAL_MS="$interval_ms"
  interval_s="$(awk "BEGIN { printf \"%.0f\", (${interval_ms} / 1000) }")"

  log "checking local gateway websocket handshake (poll every ${interval_s}s, up to ${retries} attempts)"
  if [ "${GATEWAY_CHECK_INITIAL_DELAY_MS:-0}" -gt 0 ] 2>/dev/null; then
    delay_s="$(awk "BEGIN { printf \"%.0f\", (${GATEWAY_CHECK_INITIAL_DELAY_MS} / 1000) }")"
    log "waiting ${delay_s}s before first gateway check"
    sleep_ms "$GATEWAY_CHECK_INITIAL_DELAY_MS"
  fi
  attempt=1
  while [ "$attempt" -le "$retries" ]; do
    if check_gateway_ws_handshake; then
      GATEWAY_CHECK_STATUS="OK"
      log_ok "$GATEWAY_CHECK_MESSAGE"
      break
    fi
    if [ "$attempt" -lt "$retries" ]; then
      log "gateway not ready yet (${attempt}/${retries}); waiting ${interval_s}s before retry"
      sleep_ms "$GATEWAY_CHECK_INTERVAL_MS"
    fi
    attempt=$((attempt + 1))
  done
  if [ "$GATEWAY_CHECK_STATUS" != "OK" ]; then
    GATEWAY_CHECK_STATUS="FAILED"
    log_error "$GATEWAY_CHECK_MESSAGE"
    print_gateway_troubleshooting
    print_connectivity_summary
    exit 1
  fi
else
  GATEWAY_CHECK_STATUS="SKIPPED"
  GATEWAY_CHECK_MESSAGE="skipped by --skip-gateway-check"
  log "local gateway handshake check skipped (--skip-gateway-check)"
fi

print_connectivity_summary
section "Done"
if [ "$BRIDGE_CHECK_STATUS" = "OK" ] && [ "$GATEWAY_CHECK_STATUS" = "OK" ]; then
  log_ok "install completed with bridge+gateway checks passed"
else
  log "install completed (one or more checks skipped)"
fi
if [ "$SEARCH_PLUGIN_ENABLED" = "1" ]; then
  log "plugins=$PLUGIN_NAME,$SEARCH_PLUGIN_NAME ws_url=$(mask_url_for_log "$WS_URL") target_dir=$TARGET_DIR search_target_dir=$SEARCH_TARGET_DIR"
else
  log "plugins=$PLUGIN_NAME ws_url=$(mask_url_for_log "$WS_URL") target_dir=$TARGET_DIR"
fi
