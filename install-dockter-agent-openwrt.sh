#!/usr/bin/env bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_title() {
    echo
    echo "====================================="
    echo " Dockter Agent OpenWrt 安装脚本"
    echo "====================================="
    echo
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检测是否为 OpenWrt 系统
detect_openwrt() {
    if [ ! -f /etc/openwrt_release ] && [ ! -d /etc/config ]; then
        print_error "此脚本仅适用于 OpenWrt 系统"
        exit 1
    fi
    
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        print_info "检测到系统: $DISTRIB_ID $DISTRIB_RELEASE"
    else
        print_info "检测到 OpenWrt 系统"
    fi
}

# 检测架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l|armv6l|arm)
            # 检测 ARM 架构类型
            if [ -f /proc/cpuinfo ]; then
                CPUINFO=$(cat /proc/cpuinfo | grep -i "model name" | head -1)
                if echo "$CPUINFO" | grep -qi "cortex-a"; then
                    ARCH="arm64"
                else
                    # 尝试使用 arm64，如果不支持再回退到 arm
                    ARCH="arm64"
                fi
            else
                ARCH="arm64"
            fi
            ;;
        mips|mipsel|mips64|mips64el)
            # MIPS 架构通常使用 arm64 二进制（如果可用）
            print_warning "检测到 MIPS 架构，尝试使用 arm64 二进制"
            ARCH="arm64"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            print_info "支持的架构: amd64, arm64"
            exit 1
            ;;
    esac
    print_info "检测到架构: $ARCH"
}

# 获取当前安装的版本
get_current_version() {
    local version_file="$INSTALL_DIR/version.txt"
    if [ -f "$version_file" ]; then
        local version=$(grep -i "^Version:" "$version_file" 2>/dev/null | sed 's/Version:[[:space:]]*//' | tr -d '\r\n' || echo "")
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    echo ""
    return 1
}

# 获取远程最新版本
get_latest_version() {
    local version_url="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/version.txt"
    
    if command -v curl >/dev/null 2>&1; then
        local version_info=$(curl -s --max-time 10 --connect-timeout 5 "$version_url" 2>/dev/null || echo "")
        if [ -n "$version_info" ]; then
            local version=$(echo "$version_info" | grep -i "^Version:" | sed 's/Version:[[:space:]]*//' | tr -d '\r\n' || echo "")
            if [ -n "$version" ]; then
                echo "$version"
                return 0
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        local version_info=$(wget -q --timeout=10 --tries=1 -O- "$version_url" 2>/dev/null || echo "")
        if [ -n "$version_info" ]; then
            local version=$(echo "$version_info" | grep -i "^Version:" | sed 's/Version:[[:space:]]*//' | tr -d '\r\n' || echo "")
            if [ -n "$version" ]; then
                echo "$version"
                return 0
            fi
        fi
    fi
    
    echo ""
    return 1
}

# 比较版本号
compare_versions() {
    local version1="$1"
    local version2="$2"
    
    # 移除 'v' 前缀
    version1=$(echo "$version1" | sed 's/^v//')
    version2=$(echo "$version2" | sed 's/^v//')
    
    # 使用 sort -V 进行版本比较
    if [ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" = "$version1" ]; then
        if [ "$version1" = "$version2" ]; then
            echo "equal"
        else
            echo "older"
        fi
    else
        echo "newer"
    fi
}

# 检查版本信息
check_version() {
    print_info "检查版本信息..."
    
    local current_version=""
    local latest_version=""
    
    # 获取当前版本（从本地 version.txt）
    if [ -f "$INSTALL_DIR/version.txt" ]; then
        current_version=$(get_current_version)
        if [ -n "$current_version" ]; then
            print_info "当前安装版本: $current_version"
        else
            print_warning "无法从 version.txt 读取当前版本信息"
        fi
    else
        print_info "未检测到已安装的版本"
    fi
    
    # 获取最新版本
    print_info "正在获取最新版本信息..."
    latest_version=$(get_latest_version)
    
    if [ -n "$latest_version" ]; then
        print_success "最新可用版本: $latest_version"
        
        # 如果有当前版本，进行比较
        if [ -n "$current_version" ]; then
            local comparison=$(compare_versions "$current_version" "$latest_version")
            case "$comparison" in
                "equal")
                    print_success "当前版本已是最新版本"
                    ;;
                "older")
                    print_warning "发现新版本: $latest_version（当前: $current_version）"
                    echo
                    read -p "是否继续安装/更新到最新版本？(Y/n): " update_choice
                    update_choice=${update_choice:-Y}
                    if [[ ! "$update_choice" =~ ^[Yy]$ ]]; then
                        print_info "已取消安装"
                        exit 0
                    fi
                    ;;
                "newer")
                    print_warning "当前版本 ($current_version) 比远程版本 ($latest_version) 更新"
                    echo
                    read -p "是否继续安装？(y/N): " continue_choice
                    continue_choice=${continue_choice:-N}
                    if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                        print_info "已取消安装"
                        exit 0
                    fi
                    ;;
            esac
        fi
    else
        print_warning "无法获取最新版本信息，将使用默认下载源"
    fi
    
    echo
}

# 检测本机真实 IPv4
detect_ip() {
    AUTO_IP=$(curl -s --max-time 10 --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || echo "")
    
    if [ -z "$AUTO_IP" ]; then
        # OpenWrt 获取 IP 的方式
        AUTO_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    fi
    
    if [ -z "$AUTO_IP" ]; then
        AUTO_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
    fi
    
    if [ -z "$AUTO_IP" ]; then
        print_warning "无法自动检测 IP 地址"
        read -p "请输入服务器 IPv4 地址: " AUTO_IP
    else
        echo
        print_info "检测到本机 IPv4 地址：$AUTO_IP"
        echo
        echo "是否使用该地址作为 Agent 连接地址？"
        echo "1) 使用检测到的 IP（默认）"
        echo "2) 手动输入 IPv4"
        read -p "请选择 (1/2 默认1): " ip_choice
        ip_choice=${ip_choice:-1}
        
        case "$ip_choice" in
            2)
                read -p "请输入 IPv4 地址: " SERVER_IP
                ;;
            *)
                SERVER_IP="$AUTO_IP"
                ;;
        esac
    fi
}

# 安装目录配置
INSTALL_DIR="/opt/dockter-agent"
BIN_DIR="/usr/bin"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"
INIT_SCRIPT="/etc/init.d/dockter-agent"

# 配置变量
DEFAULT_API_PORT="19029"
DEFAULT_COMPOSE_ROOT="/mnt/compose"
DEFAULT_FILE_MANAGER_DIR="/"
DEFAULT_HOST="0.0.0.0"
DEFAULT_TZ="Asia/Shanghai"

# 生成 Token
generate_token() {
    if command -v md5sum >/dev/null 2>&1; then
        head -c 32 /dev/urandom 2>/dev/null | md5sum | cut -d' ' -f1
    elif command -v md5 >/dev/null 2>&1; then
        head -c 32 /dev/urandom 2>/dev/null | md5 | cut -d' ' -f1
    else
        # 备用方案：使用 openssl
        openssl rand -hex 16 2>/dev/null || date +%s | sha256sum | cut -d' ' -f1
    fi
}

# 交互式配置
interactive_config() {
    # API 端口设置
    echo
    echo "设置 API 端口："
    read -p "按回车使用默认 [$DEFAULT_API_PORT]，或输入端口号: " USER_API_PORT
    USER_API_PORT=${USER_API_PORT:-$DEFAULT_API_PORT}
    DOCKTER_API_PORT="$USER_API_PORT"
    
    # Compose 根目录
    echo
    echo "请选择 Dockter Compose 根目录（用于存放项目目录）"
    read -p "按回车使用默认 [$DEFAULT_COMPOSE_ROOT]，或输入路径: " USER_COMPOSE_ROOT
    USER_COMPOSE_ROOT=${USER_COMPOSE_ROOT:-$DEFAULT_COMPOSE_ROOT}
    # OpenWrt 可能没有 realpath，使用简化处理
    COMPOSE_ROOT="$USER_COMPOSE_ROOT"
    
    # Token 生成
    echo
    echo "设置 API Token："
    echo "1) 自动生成（默认，推荐）"
    echo "2) 手动输入"
    read -p "请选择 (1/2 默认1): " token_choice
    token_choice=${token_choice:-1}
    
    case "$token_choice" in
        2)
            read -p "请输入 Token: " DOCKTER_API_TOKEN
            ;;
        *)
            DOCKTER_API_TOKEN=$(generate_token)
            ;;
    esac
    
    # Base URL
    if [[ "$SERVER_IP" =~ ^https?:// ]]; then
        DEFAULT_BASE_URL="$SERVER_IP"
    else
        DEFAULT_BASE_URL="http://$SERVER_IP"
    fi
    
    echo
    echo "设置 Container Base URL："
    echo "1) 默认：$DEFAULT_BASE_URL"
    echo "2) 手动输入（⚠ 不要带端口）"
    read -p "请选择 (1/2 默认1): " base_choice
    base_choice=${base_choice:-1}
    
    case "$base_choice" in
        2)
            read -p "请输入 URL（不要带端口）: " DOCKTER_CONTAINER_BASE_URL
            if [[ ! "$DOCKTER_CONTAINER_BASE_URL" =~ ^https?:// ]]; then
                DOCKTER_CONTAINER_BASE_URL="http://$DOCKTER_CONTAINER_BASE_URL"
            fi
            ;;
        *)
            DOCKTER_CONTAINER_BASE_URL="$DEFAULT_BASE_URL"
            ;;
    esac
    
    # 是否自动拉镜像
    echo
    echo "设置 Compose 重构建时是否拉取镜像："
    echo "1) false（默认）"
    echo "2) true"
    read -p "请选择 (1/2 默认1): " pull_choice
    pull_choice=${pull_choice:-1}
    
    case "$pull_choice" in
        2) DOCKTER_COMPOSE_PULL_IMAGES="true" ;;
        *) DOCKTER_COMPOSE_PULL_IMAGES="false" ;;
    esac
    
    # 调试模式
    echo
    echo "设置调试模式："
    echo "1) false（默认，生产环境推荐）"
    echo "2) true（开发调试）"
    read -p "请选择 (1/2 默认1): " debug_choice
    debug_choice=${debug_choice:-1}
    
    case "$debug_choice" in
        2) DOCKTER_DEBUG="true" ;;
        *) DOCKTER_DEBUG="false" ;;
    esac
    
    # 文件管理默认目录
    echo
    echo "设置文件管理默认目录："
    read -p "按回车使用默认 [$DEFAULT_FILE_MANAGER_DIR]，或输入路径: " USER_FILE_MANAGER_DIR
    USER_FILE_MANAGER_DIR=${USER_FILE_MANAGER_DIR:-$DEFAULT_FILE_MANAGER_DIR}
    FILE_MANAGER_DEFAULT_DIR="$USER_FILE_MANAGER_DIR"
}

# 创建目录结构
create_directories() {
    print_info "创建目录结构..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$COMPOSE_ROOT"
    print_success "目录创建完成"
}

# 下载二进制文件
download_binary() {
    local binary_name="dockter-agent_linux_$ARCH"
    local github_url="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/$binary_name"
    
    print_info "准备下载二进制文件..."
    print_info "架构: $ARCH"
    print_info "文件: $binary_name"
    
    # 检查安装目录是否已存在二进制文件
    if [ -f "$INSTALL_DIR/dockter-agent" ]; then
        print_warning "检测到安装目录已存在二进制文件: $INSTALL_DIR/dockter-agent"
        echo
        echo "是否要覆盖现有文件？"
        echo "1) 是，覆盖现有文件（默认）"
        echo "2) 否，跳过下载，使用现有文件"
        read -p "请选择 (1/2 默认1): " overwrite_choice
        overwrite_choice=${overwrite_choice:-1}
        
        case "$overwrite_choice" in
            2)
                print_info "跳过下载，使用现有二进制文件"
                chmod +x "$INSTALL_DIR/dockter-agent"
                print_success "使用现有二进制文件"
                return 0
                ;;
            *)
                print_info "将覆盖现有二进制文件"
                ;;
        esac
    fi
    
    # 优先使用用户指定的 URL
    if [ -n "$BINARY_URL" ]; then
        print_info "从用户指定的 URL 下载: $BINARY_URL"
        if command -v wget >/dev/null 2>&1; then
            wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/dockter-agent" || {
                print_error "从指定 URL 下载失败"
                exit 1
            }
        elif command -v curl >/dev/null 2>&1; then
            curl -L --progress-bar "$BINARY_URL" -o "$INSTALL_DIR/dockter-agent" || {
                print_error "从指定 URL 下载失败"
                exit 1
            }
        else
            print_error "未找到 wget 或 curl，无法下载"
            exit 1
        fi
        chmod +x "$INSTALL_DIR/dockter-agent"
        print_success "二进制文件下载完成"
        return 0
    fi
    
    # 检查本地文件
    if [ -f "./$binary_name" ]; then
        print_info "使用本地二进制文件: ./$binary_name"
        cp "./$binary_name" "$INSTALL_DIR/dockter-agent"
        chmod +x "$INSTALL_DIR/dockter-agent"
        print_success "二进制文件复制完成"
        return 0
    fi
    
    # 从 GitHub 自动下载
    print_info "从 GitHub 自动下载最新版本..."
    print_info "URL: $github_url"
    
    if command -v wget >/dev/null 2>&1; then
        print_info "使用 wget 下载..."
        if wget -q --show-progress "$github_url" -O "$INSTALL_DIR/dockter-agent"; then
            chmod +x "$INSTALL_DIR/dockter-agent"
            # 同时下载 version.txt
            local version_url="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/version.txt"
            wget -q "$version_url" -O "$INSTALL_DIR/version.txt" 2>/dev/null || print_warning "无法下载 version.txt，但不影响安装"
            print_success "二进制文件下载完成"
            return 0
        else
            print_error "从 GitHub 下载失败"
            print_info "请检查网络连接或手动下载: $github_url"
            exit 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        print_info "使用 curl 下载..."
        if curl -L --progress-bar "$github_url" -o "$INSTALL_DIR/dockter-agent"; then
            chmod +x "$INSTALL_DIR/dockter-agent"
            # 同时下载 version.txt
            local version_url="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/version.txt"
            curl -s --max-time 10 --connect-timeout 5 "$version_url" -o "$INSTALL_DIR/version.txt" 2>/dev/null || print_warning "无法下载 version.txt，但不影响安装"
            print_success "二进制文件下载完成"
            return 0
        else
            print_error "从 GitHub 下载失败"
            print_info "请检查网络连接或手动下载: $github_url"
            exit 1
        fi
    else
        print_error "未找到 wget 或 curl，无法自动下载"
        print_info "请安装 wget 或 curl，或手动下载文件: $github_url"
        print_info "安装命令: opkg update && opkg install wget"
        exit 1
    fi
}

# 创建配置文件
create_config() {
    print_info "创建配置文件..."
    
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "global_settings": {
    "api_token": "$DOCKTER_API_TOKEN",
    "debug_mode": $DOCKTER_DEBUG,
    "http_proxy": ""
  },
  "docker_settings": {
    "docker_stack_directory": "$COMPOSE_ROOT",
    "compose_rebuild_pull_images": $DOCKTER_COMPOSE_PULL_IMAGES,
    "container_base_url": "$DOCKTER_CONTAINER_BASE_URL",
    "extend_stack_dirs": [],
    "self_container": "dockter-agent",
    "host_stack_dir": "$COMPOSE_ROOT"
  },
  "file_manager_settings": {
    "default_dir": "$FILE_MANAGER_DEFAULT_DIR"
  },
  "dashboard": {},
  "docker_bot_settings": {},
  "notify_config": {
    "telegram": {
      "switch": false,
      "bot_token": "",
      "chat_id": "",
      "user_id": ""
    },
    "wechat": {
      "switch": false
    }
  },
  "page_settings": {
    "page_title": "Dockter Agent"
  },
  "search_engines_settings": {
    "search_open_in_new_tab": false,
    "show_search_box": true,
    "show_search_box_in_mobile": false,
    "default_search_engine_id": "550e8400-e29b-41d4-a716-446655440001",
    "search_engines": []
  },
  "theme": "dark",
  "license": "",
  "favorite_directory": []
}
EOF
    
    # 创建环境变量配置文件
    cat > "$INSTALL_DIR/.env" <<EOF
DOCKTER_MODE=agent
DOCKTER_HOST=$DEFAULT_HOST
DOCKTER_API_PORT=$DOCKTER_API_PORT
TZ=$DEFAULT_TZ
DOCKTER_DEBUG=$DOCKTER_DEBUG
LOG_LEVEL=info
DATABASE_PATH=$CONFIG_DIR/dockter.db
LOG_PATH=$LOG_DIR/dockter.log
EOF
    
    print_success "配置文件创建完成"
}

# 创建 OpenWrt init.d 服务脚本
create_init_script() {
    print_info "创建 OpenWrt init.d 服务脚本..."
    
    cat > "$INIT_SCRIPT" <<'INITEOF'
#!/bin/sh /etc/rc.common
# Dockter Agent Service Script for OpenWrt

START=99
STOP=10

INSTALL_DIR="/opt/dockter-agent"
BINARY="$INSTALL_DIR/dockter-agent"
ENV_FILE="$INSTALL_DIR/.env"
PID_FILE="/var/run/dockter-agent.pid"

start_service() {
    if [ ! -f "$BINARY" ]; then
        echo "错误: 二进制文件不存在: $BINARY"
        return 1
    fi
    
    if [ ! -x "$BINARY" ]; then
        chmod +x "$BINARY"
    fi
    
    # 加载环境变量
    if [ -f "$ENV_FILE" ]; then
        . "$ENV_FILE"
    fi
    
    procd_open_instance
    procd_set_param command "$BINARY"
    
    # 设置工作目录
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    
    # 设置环境变量
    if [ -f "$ENV_FILE" ]; then
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            case "$key" in
                \#*|"") continue ;;
            esac
            # 移除引号
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            procd_set_param env "$key=$value"
        done < "$ENV_FILE"
    fi
    
    procd_close_instance
}

stop_service() {
    # procd 会自动处理停止
    return 0
}
INITEOF
    
    chmod +x "$INIT_SCRIPT"
    print_success "OpenWrt init.d 服务脚本创建完成"
}

# 创建 Agent 更新脚本
create_update_script() {
    print_info "创建 Agent 更新脚本..."
    
    cat > "$INSTALL_DIR/update-agent.sh" <<'UPDATEEOF'
#!/usr/bin/env bash
# Dockter Agent 自动更新脚本 (OpenWrt)

set -e

INSTALL_DIR="/opt/dockter-agent"
SERVICE_NAME="dockter-agent"
LOG_FILE="$INSTALL_DIR/logs/update.log"
LOCK_DIR="/tmp/dockter-agent-update.lock"
LOCK_FILE="/tmp/dockter-agent-update.lock.pid"

# 检查锁文件，防止并发更新（必须在最前面，在任何日志操作之前）
# 使用原子操作：使用 mkdir 创建锁目录（mkdir 是原子的）
if mkdir "$LOCK_DIR" 2>/dev/null; then
    # 成功创建锁目录，写入 PID 到锁文件
    echo $$ > "$LOCK_FILE"
    trap "rm -rf $LOCK_DIR $LOCK_FILE" EXIT
else
    # 锁目录已存在，检查是否有进程在运行
    if [ -f "$LOCK_FILE" ]; then
        PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            # 进程正在运行，直接退出（不使用日志函数，因为还没定义）
            exit 0
        else
            # 发现过期的锁文件，清理后继续
            rm -rf "$LOCK_DIR" "$LOCK_FILE" 2>/dev/null || true
            # 重试创建锁目录
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                echo $$ > "$LOCK_FILE"
                trap "rm -rf $LOCK_DIR $LOCK_FILE" EXIT
            else
                # 无法创建锁文件，直接退出
                exit 1
            fi
        fi
    else
        # 锁目录存在但锁文件不存在，清理后继续
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_FILE"
            trap "rm -rf $LOCK_DIR $LOCK_FILE" EXIT
        else
            # 无法创建锁文件，直接退出
            exit 1
        fi
    fi
fi

# 确保日志目录存在
mkdir -p "$INSTALL_DIR/logs"

# 清空日志文件（每次更新都从新开始）
> "$LOG_FILE"

# 日志函数（在锁检查之后定义）
# 直接写入文件，避免 tee 导致的重复输出
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_info "========================================="
log_info "开始执行 Agent 自动更新"
log_info "========================================="

# 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    armv7l|armv6l|arm)
        ARCH="arm64"
        ;;
    *)
        ARCH="arm64"
        ;;
esac

log_info "检测到架构: $ARCH"

# 构建下载 URL
BINARY_NAME="dockter-agent_linux_$ARCH"
GITHUB_URL="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/$BINARY_NAME"
DOWNLOAD_URL="${1:-$GITHUB_URL}"

log_info "下载 URL: $DOWNLOAD_URL"

# 停止服务
if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
    if /etc/init.d/$SERVICE_NAME running >/dev/null 2>&1; then
        log_info "停止服务..."
        /etc/init.d/$SERVICE_NAME stop || {
            log_error "停止服务失败"
            exit 1
        }
        sleep 2
        log_info "服务已停止"
    else
        log_info "服务未运行，跳过停止步骤"
    fi
fi

# 下载新版本
log_info "开始下载新版本..."
TEMP_FILE="$INSTALL_DIR/dockter-agent.new"

if command -v wget >/dev/null 2>&1; then
    if wget -q --show-progress "$DOWNLOAD_URL" -O "$TEMP_FILE"; then
        chmod +x "$TEMP_FILE"
        log_info "下载完成 (使用 wget)"
    else
        log_error "下载失败 (wget)"
        exit 1
    fi
elif command -v curl >/dev/null 2>&1; then
    if curl -L --progress-bar "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
        chmod +x "$TEMP_FILE"
        log_info "下载完成 (使用 curl)"
    else
        log_error "下载失败 (curl)"
        exit 1
    fi
else
    log_error "未找到 wget 或 curl，无法下载"
    exit 1
fi

# 验证新版本
if [ ! -f "$TEMP_FILE" ] || [ ! -x "$TEMP_FILE" ]; then
    log_error "下载的文件无效"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 替换旧版本
mv "$TEMP_FILE" "$INSTALL_DIR/dockter-agent"
log_info "新版本已安装"

# 同时下载 version.txt（如果可用）
VERSION_URL="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/releases/latest/version.txt"
if command -v wget >/dev/null 2>&1; then
    wget -q "$VERSION_URL" -O "$INSTALL_DIR/version.txt" 2>/dev/null || log_warning "无法下载 version.txt"
elif command -v curl >/dev/null 2>&1; then
    curl -s --max-time 10 --connect-timeout 5 "$VERSION_URL" -o "$INSTALL_DIR/version.txt" 2>/dev/null || log_warning "无法下载 version.txt"
fi

# 启动服务
log_info "启动服务..."
if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
    if /etc/init.d/$SERVICE_NAME start; then
        sleep 2
        if /etc/init.d/$SERVICE_NAME running >/dev/null 2>&1; then
            log_info "服务启动成功"
            log_info "========================================="
            log_info "Agent 更新完成"
            log_info "========================================="
        else
            log_error "服务启动失败"
            exit 1
        fi
    else
        log_error "启动服务命令失败"
        exit 1
    fi
else
    log_error "服务脚本不存在"
    exit 1
fi
UPDATEEOF

    chmod +x "$INSTALL_DIR/update-agent.sh"
    print_success "Agent 更新脚本创建完成"
}

# 创建 OpenWrt 更新器 init.d 服务脚本
create_updater_service() {
    print_info "创建 Agent 更新器服务..."
    
    UPDATER_INIT_SCRIPT="/etc/init.d/dockter-agent-updater"
    
    cat > "$UPDATER_INIT_SCRIPT" <<'UPDATERINITEOF'
#!/bin/sh /etc/rc.common
# Dockter Agent Updater Service Script for OpenWrt

START=99

INSTALL_DIR="/opt/dockter-agent"
UPDATE_SCRIPT="$INSTALL_DIR/update-agent.sh"

start_service() {
    if [ ! -f "$UPDATE_SCRIPT" ]; then
        echo "错误: 更新脚本不存在: $UPDATE_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$UPDATE_SCRIPT" ]; then
        chmod +x "$UPDATE_SCRIPT"
    fi
    
    # 从环境变量获取 URL（如果设置）
    DOWNLOAD_URL="${DOCKTER_UPDATE_URL:-}"
    
    # 在后台执行更新脚本
    if [ -n "$DOWNLOAD_URL" ]; then
        "$UPDATE_SCRIPT" "$DOWNLOAD_URL" >/dev/null 2>&1 &
    else
        "$UPDATE_SCRIPT" >/dev/null 2>&1 &
    fi
}

stop_service() {
    # 更新器服务是一次性的，不需要停止
    return 0
}
UPDATERINITEOF
    
    chmod +x "$UPDATER_INIT_SCRIPT"
    print_success "Agent 更新器服务创建完成"
    print_info "使用方法: DOCKTER_UPDATE_URL=<URL> /etc/init.d/dockter-agent-updater start"
}

# 创建 dt 命令工具
create_dt_command() {
    print_info "创建 dt 命令工具..."
    
    cat > "$BIN_DIR/dt" <<'DTEOF'
#!/usr/bin/env bash
# Dockter Agent 管理工具 (OpenWrt)

INSTALL_DIR="/opt/dockter-agent"
SERVICE_NAME="dockter-agent"
INIT_SCRIPT="/etc/init.d/$SERVICE_NAME"
CONFIG_FILE="$INSTALL_DIR/config/config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 检查服务状态
check_service() {
    if [ -f "$INIT_SCRIPT" ]; then
        if $INIT_SCRIPT running >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 显示状态
show_status() {
    if check_service; then
        print_success "服务运行中"
        $INIT_SCRIPT status
    else
        print_error "服务未运行"
    fi
}

# 显示端口
show_port() {
    if [ -f "$INSTALL_DIR/.env" ]; then
        PORT=$(grep "^DOCKTER_API_PORT=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
        if [ -n "$PORT" ]; then
            echo "API 端口: $PORT"
        else
            print_warning "未找到端口配置"
        fi
    else
        print_warning "配置文件不存在"
    fi
}

# 显示 Token
show_token() {
    if [ -f "$CONFIG_FILE" ]; then
        TOKEN=$(grep -o '"api_token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
        if [ -n "$TOKEN" ]; then
            echo "API Token: $TOKEN"
        else
            print_warning "未找到 Token 配置"
        fi
    else
        print_warning "配置文件不存在"
    fi
}

# 启动服务
start_service() {
    print_info "启动服务..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT start
        sleep 2
        if check_service; then
            print_success "服务启动成功"
        else
            print_error "服务启动失败"
            exit 1
        fi
    else
        print_error "服务脚本不存在: $INIT_SCRIPT"
        exit 1
    fi
}

# 停止服务
stop_service() {
    print_info "停止服务..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT stop
        sleep 1
        if ! check_service; then
            print_success "服务已停止"
        else
            print_error "服务停止失败"
            exit 1
        fi
    else
        print_error "服务脚本不存在: $INIT_SCRIPT"
        exit 1
    fi
}

# 重启服务
restart_service() {
    print_info "重启服务..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT restart
        sleep 2
        if check_service; then
            print_success "服务重启成功"
        else
            print_error "服务重启失败"
            exit 1
        fi
    else
        print_error "服务脚本不存在: $INIT_SCRIPT"
        exit 1
    fi
}

# 更新服务
update_service() {
    print_info "更新服务..."
    
    # 如果指定了参数（如 "sidebar"），使用更新器服务更新
    # dt update sidebar - 使用更新器服务更新（用于 agent 自更新）
    if [ -n "$1" ]; then
        # 检查更新器服务是否存在
        if [ -f "/etc/init.d/dockter-agent-updater" ]; then
            print_info "使用更新器服务进行更新（参数: $1）..."
            
            # 如果参数是 URL，传递给更新脚本
            if [[ "$1" =~ ^https?:// ]]; then
                print_info "从指定 URL 更新: $1"
                if "$INSTALL_DIR/update-agent.sh" "$1"; then
                    print_success "更新完成"
                else
                    print_error "更新失败，请查看日志: $INSTALL_DIR/logs/update.log"
                    exit 1
                fi
            else
                # 使用更新器服务（不带 URL 参数，使用默认 GitHub URL）
                print_info "使用更新器服务进行更新..."
                
                # 检查是否已有更新进程在运行
                LOCK_DIR="/tmp/dockter-agent-update.lock"
                LOCK_FILE="/tmp/dockter-agent-update.lock.pid"
                if [ -d "$LOCK_DIR" ] || [ -f "$LOCK_FILE" ]; then
                    if [ -f "$LOCK_FILE" ]; then
                        LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
                        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
                            print_warning "更新进程正在运行中 (PID: $LOCK_PID)，跳过本次更新"
                            print_info "如果确认没有更新进程，请删除锁: rm -rf $LOCK_DIR $LOCK_FILE"
                            exit 0
                        else
                            print_warning "发现过期的锁文件，清理后继续"
                            rm -rf "$LOCK_DIR" "$LOCK_FILE" 2>/dev/null || true
                        fi
                    else
                        print_warning "发现锁目录但无锁文件，清理后继续"
                        rm -rf "$LOCK_DIR" 2>/dev/null || true
                    fi
                fi
                
                # 直接在后台启动更新脚本（不使用 init.d，因为 init.d 不能传参）
                LOG_FILE="$INSTALL_DIR/logs/update.log"
                
                # 确保日志目录存在
                mkdir -p "$INSTALL_DIR/logs"
                
                # 在后台执行更新脚本（不重定向输出，让日志写入文件）
                # 注意：更新脚本内部已经有锁机制，这里只启动一次
                "$INSTALL_DIR/update-agent.sh" >/dev/null 2>&1 &
                UPDATER_PID=$!
                
                # 等待一小段时间，让更新脚本创建锁文件
                sleep 1
                
                # 验证更新脚本是否成功启动（检查锁文件中的 PID 是否匹配）
                if [ -f "$LOCK_FILE" ]; then
                    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
                    if [ -n "$LOCK_PID" ] && [ "$LOCK_PID" = "$UPDATER_PID" ]; then
                        print_success "更新任务已启动 (PID: $UPDATER_PID)"
                    else
                        # PID 不匹配，可能是另一个进程正在运行
                        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
                            print_warning "检测到另一个更新进程正在运行 (PID: $LOCK_PID)"
                            print_info "等待当前更新完成..."
                            UPDATER_PID="$LOCK_PID"
                        else
                            print_success "更新任务已启动 (PID: $UPDATER_PID)"
                        fi
                    fi
                else
                    print_success "更新任务已启动 (PID: $UPDATER_PID)"
                fi
                echo
                print_info "实时更新日志:"
                echo "----------------------------------------"
                
                # 等待一小段时间让服务开始写入日志
                sleep 1
                
                # 实时显示日志
                if [ -f "$LOG_FILE" ]; then
                    # 实时跟踪日志文件
                    # 在后台监控更新进程状态，当更新完成时停止 tail
                    (
                        # 等待更新脚本完成（检查锁目录或进程）
                        while kill -0 "$UPDATER_PID" 2>/dev/null || [ -d "/tmp/dockter-agent-update.lock" ]; do
                            sleep 1
                        done
                        # 更新完成，等待一下让日志写入完成
                        sleep 1
                        # 停止 tail 进程
                        pkill -f "tail -f.*update.log" 2>/dev/null || true
                    ) &
                    
                    # 实时显示日志（带超时保护，最多等待 10 分钟）
                    if command -v timeout >/dev/null 2>&1; then
                        timeout 600 tail -f "$LOG_FILE" 2>/dev/null || true
                    else
                        # 如果没有 timeout 命令，直接使用 tail（OpenWrt 可能没有 timeout）
                        tail -f "$LOG_FILE" 2>/dev/null &
                        TAIL_PID=$!
                        # 等待更新完成
                        wait "$UPDATER_PID" 2>/dev/null || true
                        sleep 1
                        kill "$TAIL_PID" 2>/dev/null || true
                    fi
                else
                    # 如果没有日志文件，等待更新完成
                    print_info "等待更新完成..."
                    wait "$UPDATER_PID" 2>/dev/null || true
                    
                    # 显示最终日志
                    if [ -f "$LOG_FILE" ]; then
                        tail -n 30 "$LOG_FILE" 2>/dev/null || true
                    fi
                fi
                
                echo "----------------------------------------"
                
                # 检查更新结果
                sleep 1
                if [ -f "$LOG_FILE" ] && grep -qi "ERROR\|失败" "$LOG_FILE" 2>/dev/null; then
                    print_error "更新失败"
                    print_info "详细日志请查看: $INSTALL_DIR/logs/update.log"
                    exit 1
                else
                    # 检查服务是否成功启动
                    sleep 2
                    if check_service; then
                        print_success "更新完成，服务已重启"
                    else
                        print_warning "更新完成，但服务未运行"
                        print_info "请检查服务状态: dt status"
                    fi
                fi
            fi
        else
            print_error "更新器服务不存在，无法使用更新器更新"
            exit 1
        fi
        return 0
    fi
    
    # dt update - 直接更新（不使用更新器服务，用于用户手动更新）
    # 直接调用更新脚本，不使用更新器服务
    print_info "直接更新（不使用更新器服务）..."
    
    # 检查更新脚本是否存在
    if [ -f "$INSTALL_DIR/update-agent.sh" ]; then
        # 直接调用更新脚本（不带参数，使用默认 GitHub URL）
        if "$INSTALL_DIR/update-agent.sh"; then
            print_success "更新完成"
            return 0
        else
            print_error "更新失败，请查看日志: $INSTALL_DIR/logs/update.log"
            exit 1
        fi
    else
        print_error "更新脚本不存在: $INSTALL_DIR/update-agent.sh"
        exit 1
    fi
}

# 卸载服务
uninstall_service() {
    print_warning "这将卸载 Dockter Agent 服务"
    read -p "确认卸载？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "已取消卸载"
        exit 0
    fi
    
    print_info "停止服务..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT stop 2>/dev/null || true
        $INIT_SCRIPT disable 2>/dev/null || true
    fi
    
    print_info "删除服务文件..."
    rm -f "$INIT_SCRIPT"
    
    # 删除更新器服务
    if [ -f "/etc/init.d/dockter-agent-updater" ]; then
        print_info "删除更新器服务..."
        rm -f "/etc/init.d/dockter-agent-updater"
    fi
    
    print_info "删除命令工具..."
    rm -f "$BIN_DIR/dt"
    
    print_warning "安装目录 $INSTALL_DIR 未删除，如需完全卸载请手动删除:"
    print_info "  rm -rf $INSTALL_DIR"
    print_success "卸载完成"
}

# 启用自启动
enable_autostart() {
    print_info "启用自启动..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT enable
        print_success "自启动已启用"
    else
        print_error "服务脚本不存在: $INIT_SCRIPT"
        exit 1
    fi
}

# 禁用自启动
disable_autostart() {
    print_info "禁用自启动..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT disable
        print_success "自启动已禁用"
    else
        print_error "服务脚本不存在: $INIT_SCRIPT"
        exit 1
    fi
}

# 显示访问信息（地址、Token、端口）
show_access_info() {
    echo
    
    # 读取端口
    PORT=""
    if [ -f "$INSTALL_DIR/.env" ]; then
        PORT=$(grep "^DOCKTER_API_PORT=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
    fi
    if [ -z "$PORT" ] && [ -f "$CONFIG_FILE" ]; then
        PORT=$(grep -o '"api_port"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[0-9]*' | head -1)
    fi
    if [ -z "$PORT" ]; then
        PORT="19029"  # 默认端口
    fi
    
    # 读取 Token
    TOKEN=""
    if [ -f "$CONFIG_FILE" ]; then
        TOKEN=$(grep -o '"api_token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
    
    # 尝试获取服务器 IP
    SERVER_IP=$(curl -s --max-time 10 --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1 || echo "localhost")
    
    # 显示访问地址
    print_info "Agent 访问地址:"
    echo "  http://$SERVER_IP:$PORT"
    echo
    
    # 显示端口
    print_info "API 端口:"
    echo "  $PORT"
    echo
    
    # 显示 Token
    if [ -n "$TOKEN" ]; then
        print_info "API Token:"
        echo "  $TOKEN"
    else
        print_warning "未找到 Token 配置"
    fi
    echo
    
    print_info "如果使用域名，请替换 IP 地址为您的域名"
}

# 显示交互式菜单
show_menu() {
    while true; do
        clear
        echo "====================================="
        echo "  Dockter Agent 管理菜单"
        echo "====================================="
        echo
        echo "1) 查看服务状态"
        echo "2) 启动服务"
        echo "3) 停止服务"
        echo "4) 重启服务"
        echo "5) 查看访问信息（地址/Token/端口）"
        echo "6) 更新服务"
        echo "7) 启用自启动"
        echo "8) 禁用自启动"
        echo "9) 卸载服务"
        echo "0) 退出"
        echo
        read -p "请选择操作 [0-9]: " choice
        
        case "$choice" in
            1)
                echo
                show_status
                echo
                read -p "按 Enter 键继续..."
                ;;
            2)
                echo
                start_service
                echo
                read -p "按 Enter 键继续..."
                ;;
            3)
                echo
                stop_service
                echo
                read -p "按 Enter 键继续..."
                ;;
            4)
                echo
                restart_service
                echo
                read -p "按 Enter 键继续..."
                ;;
            5)
                echo
                show_access_info
                echo
                read -p "按 Enter 键继续..."
                ;;
            6)
                echo
                update_service
                echo
                read -p "按 Enter 键继续..."
                ;;
            7)
                echo
                enable_autostart
                echo
                read -p "按 Enter 键继续..."
                ;;
            8)
                echo
                disable_autostart
                echo
                read -p "按 Enter 键继续..."
                ;;
            9)
                echo
                uninstall_service
                echo
                read -p "按 Enter 键继续..."
                break
                ;;
            0)
                echo
                print_info "退出菜单"
                exit 0
                ;;
            *)
                print_error "无效选择，请重新输入"
                sleep 1
                ;;
        esac
    done
}

# 显示帮助
show_help() {
    cat <<EOF
Dockter Agent 管理工具 (OpenWrt)

用法: dt <命令> [参数]

命令:
  status          显示服务状态
  start           启动服务
  stop            停止服务
  restart         重启服务
  info            显示访问信息（地址/Token/端口）
  port            显示 API 端口
  token           显示 API Token
  address         显示访问地址
  update [URL]    更新服务（自动从 GitHub latest 下载，可选：指定下载 URL）
                  使用更新器服务进行更新，可通过以下命令查看更新日志：
                  tail -f /opt/dockter-agent/logs/update.log
  uninstall       卸载服务
  enable          启用自启动
  disable         禁用自启动
  menu            显示交互式菜单
  help            显示此帮助信息

示例:
  dt               # 显示交互式菜单
  dt status        # 查看服务状态
  dt start         # 启动服务
  dt info          # 查看访问信息（地址/Token/端口）
  dt address       # 查看访问地址
  dt token         # 查看 Token
  dt update        # 更新服务（直接更新）
  dt update URL    # 从指定 URL 更新服务
  dt update sidebar # 使用更新器服务更新（用于 agent 自更新，实时显示日志）

更新器服务:
  系统还安装了一个独立的更新器服务，可以通过以下方式触发更新：
  /etc/init.d/dockter-agent-updater start
EOF
}

# 主逻辑
case "$1" in
    status)
        show_status
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    info)
        show_access_info
        ;;
    port)
        show_port
        ;;
    token)
        show_token
        ;;
    address|url)
        # 显示访问地址
        PORT=""
        if [ -f "$INSTALL_DIR/.env" ]; then
            PORT=$(grep "^DOCKTER_API_PORT=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
        fi
        if [ -z "$PORT" ]; then
            PORT="19029"  # 默认端口
        fi
        SERVER_IP=$(curl -s --max-time 10 --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1 || echo "localhost")
        echo "http://$SERVER_IP:$PORT"
        ;;
    update)
        update_service "$2"
        ;;
    uninstall)
        uninstall_service
        ;;
    enable)
        enable_autostart
        ;;
    disable)
        disable_autostart
        ;;
    menu|--menu|-m)
        show_menu
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "$1" ]; then
            # 没有参数时显示交互式菜单
            show_menu
        else
            print_error "未知命令: $1"
            echo
            show_help
            exit 1
        fi
        ;;
esac
DTEOF
    
    chmod +x "$BIN_DIR/dt"
    print_success "dt 命令工具创建完成"
}

# 启用自启动
enable_autostart() {
    print_info "启用自启动..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT enable
        print_success "自启动已启用"
    else
        print_error "服务脚本不存在"
        exit 1
    fi
}

# 启动服务
start_service() {
    print_info "启动服务..."
    if [ -f "$INIT_SCRIPT" ]; then
        $INIT_SCRIPT start
        sleep 2
        
        if $INIT_SCRIPT running >/dev/null 2>&1; then
            print_success "服务启动成功"
        else
            print_error "服务启动失败"
            $INIT_SCRIPT status
            exit 1
        fi
    else
        print_error "服务脚本不存在"
        exit 1
    fi
}

# 防火墙提示
firewall_notice() {
    echo
    print_warning "重要提示"
    echo "如果您的 OpenWrt 开启了防火墙："
    echo "👉 请务必放行端口 $DOCKTER_API_PORT/TCP"
    echo
    echo "例如："
    echo "  uci add firewall rule"
    echo "  uci set firewall.@rule[-1].name='Dockter Agent'"
    echo "  uci set firewall.@rule[-1].src='wan'"
    echo "  uci set firewall.@rule[-1].dest_port='$DOCKTER_API_PORT'"
    echo "  uci set firewall.@rule[-1].target='ACCEPT'"
    echo "  uci commit firewall"
    echo "  /etc/init.d/firewall reload"
    echo
}

# 显示安装信息
show_install_info() {
    echo
    echo "====================================="
    echo " Dockter Agent 安装完成"
    echo "====================================="
    echo
    echo "👉 Agent 访问地址:"
    if [[ "$SERVER_IP" =~ ^https?:// ]]; then
        echo "   $SERVER_IP:$DOCKTER_API_PORT"
    else
        echo "   http://$SERVER_IP:$DOCKTER_API_PORT"
    fi
    echo
    echo "🔑 API Token:"
    echo "   $DOCKTER_API_TOKEN"
    echo
    echo "📁 安装目录:"
    echo "   $INSTALL_DIR"
    echo
    echo "📁 Compose 根目录:"
    echo "   $COMPOSE_ROOT"
    echo
    echo "📝 配置文件:"
    echo "   $CONFIG_DIR/config.json"
    echo
    echo "🛠️  管理命令:"
    echo "   dt status    # 查看状态"
    echo "   dt start     # 启动服务"
    echo "   dt stop      # 停止服务"
    echo "   dt restart   # 重启服务"
    echo "   dt port      # 查看端口"
    echo "   dt token     # 查看 Token"
    echo "   dt update    # 更新服务"
    echo "   dt uninstall # 卸载服务"
    echo
    echo "🔄  服务管理:"
    echo "   /etc/init.d/dockter-agent start    # 启动服务"
    echo "   /etc/init.d/dockter-agent stop     # 停止服务"
    echo "   /etc/init.d/dockter-agent restart  # 重启服务"
    echo "   /etc/init.d/dockter-agent enable   # 启用自启动"
    echo "   /etc/init.d/dockter-agent disable  # 禁用自启动"
    echo
    echo "🔄  更新器服务:"
    echo "   dt update sidebar  # 使用更新器服务更新（用于 agent 自更新）"
    echo "   /etc/init.d/dockter-agent-updater start  # 触发自动更新"
    echo "   tail -f $INSTALL_DIR/logs/update.log     # 查看更新日志"
    echo
    firewall_notice
    echo "====================================="
}

# 主函数
main() {
    print_title
    check_root
    detect_openwrt
    
    # 首先检测架构（下载二进制文件需要）
    detect_arch
    
    # 创建安装目录（下载二进制文件需要）
    INSTALL_DIR="/opt/dockter-agent"
    CONFIG_DIR="$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # 检查版本信息（在下载之前）
    check_version
    
    # 在配置之前先下载二进制文件
    print_info "开始下载二进制文件..."
    download_binary
    
    # 继续配置流程
    detect_ip
    interactive_config
    
    echo
    print_info "开始安装..."
    echo
    
    create_directories
    # download_binary 已在前面调用，这里不再重复下载
    create_config
    create_init_script
    create_update_script
    create_updater_service
    create_dt_command
    enable_autostart
    
    echo
    read -p "是否立即启动服务？(Y/n): " start_now
    start_now=${start_now:-Y}
    
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_service
    fi
    
    show_install_info
}

# 解析命令行参数
BINARY_URL=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            BINARY_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo
            echo "选项:"
            echo "  -u, --url URL    指定二进制文件下载 URL"
            echo "  -h, --help       显示帮助信息"
            exit 0
            ;;
        *)
            print_error "未知参数: $1"
            exit 1
            ;;
    esac
done

# 执行主函数
main
