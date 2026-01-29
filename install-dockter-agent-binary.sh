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
    echo " Dockter Agent 二进制版本安装脚本"
    echo "====================================="
    echo
}

# GitHub 仓库信息
GITHUB_REPO="shenxianmq/Dockter-Agent"
# 支持通过环境变量或第一个参数传递 base URL
# 如果未指定，默认使用 GitHub raw 地址
if [ -n "$GITHUB_BASE_URL" ]; then
    # 使用环境变量
    :
elif [ -n "$1" ] && [[ "$1" =~ ^https?:// ]]; then
    # 第一个参数是 URL，使用它作为 base URL
    GITHUB_BASE_URL="$1"
    shift  # 移除第一个参数，剩余参数传递给其他函数
else
    # 默认使用 GitHub raw 地址
    GITHUB_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
fi
# 构建 releases 路径（用于下载二进制文件和版本信息）
if [[ "$GITHUB_BASE_URL" =~ cdn\.jsdelivr\.net ]]; then
    GITHUB_RELEASES_BASE="${GITHUB_BASE_URL}/releases/latest"
else
    GITHUB_RELEASES_BASE="${GITHUB_BASE_URL}/releases/latest"
fi

# 获取 wget 下载参数（兼容老版本）
get_wget_download_args() {
    # 检测 wget 是否支持 --show-progress
    if wget --help 2>&1 | grep -q "\--show-progress"; then
        # 新版本支持 --show-progress，不使用 -q 以显示进度
        echo "--show-progress"
    else
        # 老版本使用 --progress=bar（会显示进度条，即使有 -q）
        echo "--progress=bar"
    fi
}

# HTTP 代理设置
setup_proxy() {
    # 优先检查环境变量 DOCKTER_PROXY
    if [ -n "$DOCKTER_PROXY" ]; then
        export HTTP_PROXY="$DOCKTER_PROXY"
        export HTTPS_PROXY="$DOCKTER_PROXY"
        export http_proxy="$DOCKTER_PROXY"
        export https_proxy="$DOCKTER_PROXY"
        USE_PROXY="--proxy $DOCKTER_PROXY"
        print_info "✅ 从环境变量 DOCKTER_PROXY 读取代理: $DOCKTER_PROXY"
        return 0
    fi
    echo
    echo "是否需要使用 HTTP 代理？"
    echo "1) 不使用代理（默认）"
    echo "2) 使用代理"
    read -p "请选择 (1/2 默认1): " proxy_choice
    proxy_choice=${proxy_choice:-1}
    USE_PROXY=""
    if [[ "$proxy_choice" == "2" ]]; then
        read -p "请输入代理地址（例如: http://127.0.0.1:7890）: " PROXY_URL
        if [[ -n "$PROXY_URL" ]]; then
            export HTTP_PROXY="$PROXY_URL"
            export HTTPS_PROXY="$PROXY_URL"
            export http_proxy="$PROXY_URL"
            export https_proxy="$PROXY_URL"
            export DOCKTER_PROXY="$PROXY_URL"
            USE_PROXY="--proxy $PROXY_URL"
            print_success "✅ 已设置代理: $PROXY_URL"
        fi
    fi
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        echo "使用: sudo $0"
        exit 1
    fi
}

# 检测系统类型
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "无法检测系统类型"
        exit 1
    fi
    
    print_info "检测到系统: $OS $OS_VERSION"
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
        *)
            print_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    print_info "检测到架构: $ARCH"
}

# 获取当前安装的版本
get_current_version() {
    # 从本地 version.txt 文件读取版本
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
    local version_url="${GITHUB_RELEASES_BASE}/version.txt"
    
    if command -v curl >/dev/null 2>&1; then
        local version_info=$(curl -s $USE_PROXY --max-time 5 --connect-timeout 3 "$version_url" 2>/dev/null || echo "")
        if [ -n "$version_info" ]; then
            local version=$(echo "$version_info" | grep -i "^Version:" | sed 's/Version:[[:space:]]*//' | tr -d '\r\n' || echo "")
            if [ -n "$version" ]; then
                echo "$version"
                return 0
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        local version_info=$(wget -q --timeout=5 --tries=1 -O- "$version_url" 2>/dev/null || echo "")
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
    AUTO_IP=$(curl -s --max-time 5 --connect-timeout 3 https://ipinfo.io/ip 2>/dev/null || echo "")
    
    if [ -z "$AUTO_IP" ]; then
        AUTO_IP=$(hostname -I | awk '{print $1}')
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
BIN_DIR="/usr/local/bin"
CONFIG_DIR="$INSTALL_DIR/config"
LOG_DIR="$INSTALL_DIR/logs"
SERVICE_FILE="/etc/systemd/system/dockter-agent.service"

# 配置变量
DEFAULT_API_PORT="19029"
DEFAULT_COMPOSE_ROOT="/mnt/compose"
DEFAULT_FILE_MANAGER_DIR="/"
DEFAULT_HOST="0.0.0.0"
DEFAULT_TZ="Asia/Shanghai"

# 生成 Token
generate_token() {
    head -c 32 /dev/urandom | md5sum | cut -d' ' -f1
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
    COMPOSE_ROOT=$(realpath -m "$USER_COMPOSE_ROOT" 2>/dev/null || echo "$USER_COMPOSE_ROOT")
    
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
    FILE_MANAGER_DEFAULT_DIR=$(realpath -m "$USER_FILE_MANAGER_DIR" 2>/dev/null || echo "$USER_FILE_MANAGER_DIR")
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
    local github_url="${GITHUB_RELEASES_BASE}/$binary_name"
    
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
            WGET_PROGRESS=$(get_wget_download_args)
            if [[ "$WGET_PROGRESS" == "--show-progress" ]]; then
                wget --show-progress "$BINARY_URL" -O "$INSTALL_DIR/dockter-agent" || {
                    print_error "从指定 URL 下载失败"
                    exit 1
                }
            else
                wget -q --progress=bar "$BINARY_URL" -O "$INSTALL_DIR/dockter-agent" || {
                    print_error "从指定 URL 下载失败"
                    exit 1
                }
            fi
        elif command -v curl >/dev/null 2>&1; then
            curl -L $USE_PROXY --progress-bar "$BINARY_URL" -o "$INSTALL_DIR/dockter-agent" || {
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
        # 如果目标文件已存在，之前的检查已经询问过用户，这里直接覆盖
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
        WGET_PROGRESS=$(get_wget_download_args)
        if [[ "$WGET_PROGRESS" == "--show-progress" ]]; then
            if wget --show-progress "$github_url" -O "$INSTALL_DIR/dockter-agent"; then
                chmod +x "$INSTALL_DIR/dockter-agent"
                # 同时下载 version.txt
                local version_url="${GITHUB_RELEASES_BASE}/version.txt"
                wget -q "$version_url" -O "$INSTALL_DIR/version.txt" 2>/dev/null || print_warning "无法下载 version.txt，但不影响安装"
                print_success "二进制文件下载完成"
                return 0
            else
                print_error "从 GitHub 下载失败"
                print_info "请检查网络连接或手动下载: $github_url"
                exit 1
            fi
        else
            if wget -q --progress=bar "$github_url" -O "$INSTALL_DIR/dockter-agent"; then
                chmod +x "$INSTALL_DIR/dockter-agent"
                # 同时下载 version.txt
                local version_url="${GITHUB_RELEASES_BASE}/version.txt"
                wget -q "$version_url" -O "$INSTALL_DIR/version.txt" 2>/dev/null || print_warning "无法下载 version.txt，但不影响安装"
                print_success "二进制文件下载完成"
                return 0
            else
                print_error "从 GitHub 下载失败"
                print_info "请检查网络连接或手动下载: $github_url"
                exit 1
            fi
        fi
    elif command -v curl >/dev/null 2>&1; then
        print_info "使用 curl 下载..."
        if curl -L $USE_PROXY --progress-bar "$github_url" -o "$INSTALL_DIR/dockter-agent"; then
            chmod +x "$INSTALL_DIR/dockter-agent"
            # 同时下载 version.txt
            local version_url="${GITHUB_RELEASES_BASE}/version.txt"
            curl -s $USE_PROXY --max-time 5 --connect-timeout 3 "$version_url" -o "$INSTALL_DIR/version.txt" 2>/dev/null || print_warning "无法下载 version.txt，但不影响安装"
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
    "http_proxy": "${DOCKTER_PROXY:-}"
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
    
    # 创建环境变量配置文件（用于 systemd）
    cat > "$INSTALL_DIR/.env" <<EOF
DOCKTER_MODE=agent
DOCKTER_HOST=$DEFAULT_HOST
DOCKTER_API_PORT=$DOCKTER_API_PORT
TZ=$DEFAULT_TZ
DOCKTER_DEBUG=$DOCKTER_DEBUG
LOG_LEVEL=info
DATABASE_PATH=$CONFIG_DIR/dockter.db
LOG_PATH=$LOG_DIR/dockter.log
GITHUB_BASE_URL=$GITHUB_BASE_URL
EOF
    
    print_success "配置文件创建完成"
}

# 创建 systemd 服务文件
create_systemd_service() {
    print_info "创建 systemd 服务文件..."
    
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Dockter Agent Service
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/dockter-agent
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dockter-agent

# 安全设置
NoNewPrivileges=true
PrivateTmp=true

# 资源限制
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "systemd 服务文件创建完成"
}

# 创建 Agent 更新脚本
create_update_script() {
    print_info "创建 Agent 更新脚本..."
    
    cat > "$INSTALL_DIR/update-agent.sh" <<'UPDATEEOF'
#!/usr/bin/env bash
# Dockter Agent 自动更新脚本
# 此脚本由 dockter-agent-updater.service 调用

set -e

INSTALL_DIR="/opt/dockter-agent"
SERVICE_NAME="dockter-agent"
LOG_FILE="$INSTALL_DIR/logs/update.log"
LOCK_FILE="/tmp/dockter-agent-update.lock"

# 确保日志目录存在
mkdir -p "$INSTALL_DIR/logs"

# 清空日志文件（每次更新都从新开始）
> "$LOG_FILE"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
}

# 检查锁文件，防止并发更新
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        log_warning "更新进程正在运行中 (PID: $PID)，跳过本次更新"
        exit 0
    else
        log_warning "发现过期的锁文件，清理后继续"
        rm -f "$LOCK_FILE"
    fi
fi

# 创建锁文件
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

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
    *)
        log_error "不支持的架构: $ARCH"
        exit 1
        ;;
esac

log_info "检测到架构: $ARCH"

# 从配置文件读取 GitHub base URL（如果存在）
if [ -f "$INSTALL_DIR/.env" ]; then
    # 从 .env 文件读取 GITHUB_BASE_URL
    GITHUB_BASE_URL=$(grep "^GITHUB_BASE_URL=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
fi

# 如果未从配置文件读取到，使用默认值
if [ -z "$GITHUB_BASE_URL" ]; then
    GITHUB_BASE_URL="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main"
fi

# 构建 releases 路径
GITHUB_RELEASES_BASE="${GITHUB_BASE_URL}/releases/latest"

# 构建下载 URL
BINARY_NAME="dockter-agent_linux_$ARCH"
GITHUB_URL="${GITHUB_RELEASES_BASE}/$BINARY_NAME"
DOWNLOAD_URL="${1:-$GITHUB_URL}"

log_info "使用 base URL: $GITHUB_BASE_URL"
log_info "下载 URL: $DOWNLOAD_URL"

# 停止服务
if systemctl is-active --quiet "$SERVICE_NAME"; then
    log_info "停止服务..."
    systemctl stop "$SERVICE_NAME" || {
        log_error "停止服务失败"
        exit 1
    }
    sleep 2
    log_info "服务已停止"
else
    log_info "服务未运行，跳过停止步骤"
fi

# 获取 wget 下载参数（兼容老版本）
get_wget_download_args() {
    # 检测 wget 是否支持 --show-progress
    if wget --help 2>&1 | grep -q "\--show-progress"; then
        # 新版本支持 --show-progress，不使用 -q 以显示进度
        echo "--show-progress"
    else
        # 老版本使用 --progress=bar（会显示进度条，即使有 -q）
        echo "--progress=bar"
    fi
}

# 下载新版本
log_info "开始下载新版本..."
TEMP_FILE="$INSTALL_DIR/dockter-agent.new"

if command -v wget >/dev/null 2>&1; then
    WGET_PROGRESS=$(get_wget_download_args)
    if [[ "$WGET_PROGRESS" == "--show-progress" ]]; then
        if wget --show-progress "$DOWNLOAD_URL" -O "$TEMP_FILE"; then
            chmod +x "$TEMP_FILE"
            log_info "下载完成 (使用 wget)"
        else
            log_error "下载失败 (wget)"
            exit 1
        fi
    else
        if wget -q --progress=bar "$DOWNLOAD_URL" -O "$TEMP_FILE"; then
            chmod +x "$TEMP_FILE"
            log_info "下载完成 (使用 wget)"
        else
            log_error "下载失败 (wget)"
            exit 1
        fi
    fi
elif command -v curl >/dev/null 2>&1; then
    if curl -L $USE_PROXY --progress-bar "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
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
VERSION_URL="${GITHUB_RELEASES_BASE}/version.txt"
if command -v wget >/dev/null 2>&1; then
    wget -q "$VERSION_URL" -O "$INSTALL_DIR/version.txt" 2>/dev/null || log_warning "无法下载 version.txt"
elif command -v curl >/dev/null 2>&1; then
    curl -s $USE_PROXY --max-time 5 --connect-timeout 3 "$VERSION_URL" -o "$INSTALL_DIR/version.txt" 2>/dev/null || log_warning "无法下载 version.txt"
fi

# 启动服务
log_info "启动服务..."
if systemctl start "$SERVICE_NAME"; then
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "服务启动成功"
        log_info "========================================="
        log_info "Agent 更新完成"
        log_info "========================================="
    else
        log_error "服务启动失败"
        systemctl status "$SERVICE_NAME" --no-pager -l | tail -n 20 >> "$LOG_FILE" 2>&1
        exit 1
    fi
else
    log_error "启动服务命令失败"
    exit 1
fi
UPDATEEOF

    chmod +x "$INSTALL_DIR/update-agent.sh"
    print_success "Agent 更新脚本创建完成"
}

# 创建 Agent 更新器 systemd 服务
create_updater_service() {
    print_info "创建 Agent 更新器服务..."
    
    UPDATER_SERVICE_FILE="/etc/systemd/system/dockter-agent-updater.service"
    
    cat > "$UPDATER_SERVICE_FILE" <<EOF
[Unit]
Description=Dockter Agent Auto Updater Service
After=network.target
Documentation=man:systemd.service(5)

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/update-agent.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dockter-agent-updater

# 安全设置
NoNewPrivileges=true
PrivateTmp=true

# 资源限制
TimeoutStartSec=300
TimeoutStopSec=30
EOF
    
    systemctl daemon-reload
    print_success "Agent 更新器服务创建完成"
    print_info "使用方法: systemctl start dockter-agent-updater"
}

# 创建 dt 命令工具
create_dt_command() {
    print_info "创建 dt 命令工具..."
    
    cat > "$BIN_DIR/dt" <<'DTEOF'
#!/usr/bin/env bash
# Dockter Agent 管理工具

INSTALL_DIR="/opt/dockter-agent"
SERVICE_NAME="dockter-agent"
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
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_warning "服务未运行"
        return 1
    fi
    return 0
}

# 显示状态
show_status() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "服务运行中"
        systemctl status "$SERVICE_NAME" --no-pager -l | head -n 10
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
    systemctl start "$SERVICE_NAME"
    sleep 2
    if check_service; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        systemctl status "$SERVICE_NAME" --no-pager -l | tail -n 20
        exit 1
    fi
}

# 停止服务
stop_service() {
    print_info "停止服务..."
    systemctl stop "$SERVICE_NAME"
    sleep 1
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "服务已停止"
    else
        print_error "服务停止失败"
        exit 1
    fi
}

# 重启服务
restart_service() {
    print_info "重启服务..."
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if check_service; then
        print_success "服务重启成功"
    else
        print_error "服务重启失败"
        systemctl status "$SERVICE_NAME" --no-pager -l | tail -n 20
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
        if [ -f "/etc/systemd/system/dockter-agent-updater.service" ]; then
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
                print_info "启动更新器服务..."
                if systemctl start dockter-agent-updater.service; then
                    print_success "更新任务已启动"
                    echo
                    print_info "实时更新日志:"
                    echo "----------------------------------------"
                    
                    # 等待一小段时间让服务开始写入日志
                    sleep 0.5
                    
                    # 实时显示日志
                    LOG_FILE="$INSTALL_DIR/logs/update.log"
                    if [ -f "$LOG_FILE" ]; then
                        # 实时跟踪日志文件
                        # 在后台监控服务状态，当服务完成时停止 tail
                        (
                            # 等待服务完成
                            while systemctl is-active --quiet dockter-agent-updater.service 2>/dev/null; do
                                sleep 0.2
                            done
                            # 服务完成，停止 tail 进程
                            pkill -f "tail -f.*update.log" 2>/dev/null || true
                        ) &
                        
                        # 实时显示日志（带超时保护，最多等待 10 分钟）
                        timeout 600 tail -f "$LOG_FILE" 2>/dev/null || true
                    else
                        # 如果没有日志文件，使用 journalctl 实时显示
                        (
                            # 等待服务完成
                            while systemctl is-active --quiet dockter-agent-updater.service 2>/dev/null; do
                                sleep 0.2
                            done
                            # 服务完成，停止 journalctl
                            pkill -f "journalctl.*dockter-agent-updater" 2>/dev/null || true
                        ) &
                        
                        # 实时显示 journal 日志（带超时保护）
                        timeout 600 journalctl -u dockter-agent-updater -f --no-pager 2>/dev/null || true
                        
                        # 显示最终日志
                        journalctl -u dockter-agent-updater --no-pager -n 30 2>/dev/null
                    fi
                    
                    echo "----------------------------------------"
                    
                    # 检查更新结果
                    sleep 1
                    if systemctl is-failed --quiet dockter-agent-updater.service 2>/dev/null; then
                        print_error "更新失败"
                        print_info "详细日志请查看: $INSTALL_DIR/logs/update.log"
                        print_info "或使用: journalctl -u dockter-agent-updater -n 100"
                        exit 1
                    else
                        # 检查服务是否成功启动
                        sleep 2
                        if systemctl is-active --quiet "$SERVICE_NAME"; then
                            print_success "更新完成，服务已重启"
                        else
                            print_warning "更新完成，但服务未运行"
                            print_info "请检查服务状态: systemctl status $SERVICE_NAME"
                        fi
                    fi
                else
                    print_error "启动更新器服务失败"
                    exit 1
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
        print_warning "更新脚本不存在，使用传统方式更新..."
        # 检查更新器服务是否存在
        if [ -f "/etc/systemd/system/dockter-agent-updater.service" ]; then
            # 使用 systemd 服务触发更新
            print_info "启动更新器服务..."
            if systemctl start dockter-agent-updater.service; then
                print_success "更新任务已启动"
                echo
                print_info "实时更新日志:"
                echo "----------------------------------------"
                
                # 等待一小段时间让服务开始写入日志
                sleep 0.5
                
                # 实时显示日志
                LOG_FILE="$INSTALL_DIR/logs/update.log"
                if [ -f "$LOG_FILE" ]; then
                    # 实时跟踪日志文件
                    # 使用 tail -f 从文件末尾开始跟踪（日志文件每次更新都会清空，所以不会有重复）
                    # 在后台监控服务状态，当服务完成时停止 tail
                    (
                        # 等待服务完成
                        while systemctl is-active --quiet dockter-agent-updater.service 2>/dev/null; do
                            sleep 0.2
                        done
                        # 服务完成，停止 tail 进程
                        pkill -f "tail -f.*update.log" 2>/dev/null || true
                    ) &
                    
                    # 实时显示日志（带超时保护，最多等待 10 分钟）
                    timeout 600 tail -f "$LOG_FILE" 2>/dev/null || true
                else
                    # 如果没有日志文件，使用 journalctl 实时显示
                    (
                        # 等待服务完成
                        while systemctl is-active --quiet dockter-agent-updater.service 2>/dev/null; do
                            sleep 0.2
                        done
                        # 服务完成，停止 journalctl
                        pkill -f "journalctl.*dockter-agent-updater" 2>/dev/null || true
                    ) &
                    
                    # 实时显示 journal 日志（带超时保护）
                    timeout 600 journalctl -u dockter-agent-updater -f --no-pager 2>/dev/null || true
                    
                    # 显示最终日志
                    journalctl -u dockter-agent-updater --no-pager -n 30 2>/dev/null
                fi
                
                echo "----------------------------------------"
                
                # 检查更新结果
                sleep 1
                if systemctl is-failed --quiet dockter-agent-updater.service 2>/dev/null; then
                    print_error "更新失败"
                    print_info "详细日志请查看: $INSTALL_DIR/logs/update.log"
                    print_info "或使用: journalctl -u dockter-agent-updater -n 100"
                    exit 1
                else
                    # 检查服务是否成功启动
                    sleep 2
                    if systemctl is-active --quiet "$SERVICE_NAME"; then
                        print_success "更新完成，服务已重启"
                    else
                        print_warning "更新完成，但服务未运行"
                        print_info "请检查服务状态: systemctl status $SERVICE_NAME"
                    fi
                fi
            else
                print_error "启动更新器服务失败"
                exit 1
            fi
        else
            # 如果更新器服务不存在，使用传统方式更新
            print_warning "更新器服务未找到，使用传统方式更新..."
            
            # 从配置文件读取 GitHub base URL（如果存在）
            local github_base_url=""
            if [ -f "$INSTALL_DIR/.env" ]; then
                github_base_url=$(grep "^GITHUB_BASE_URL=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
            fi
            
            # 如果未从配置文件读取到，使用默认值
            if [ -z "$github_base_url" ]; then
                github_base_url="https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main"
            fi
            
            # 构建 releases 路径
            local github_releases_base="${github_base_url}/releases/latest"
            
            # 检测架构
            ARCH=$(uname -m)
            case $ARCH in
                x86_64)
                    ARCH="amd64"
                    ;;
                aarch64|arm64)
                    ARCH="arm64"
                    ;;
                *)
                    print_error "不支持的架构: $ARCH"
                    exit 1
                    ;;
            esac
            
            local binary_name="dockter-agent_linux_$ARCH"
            local github_url="${github_releases_base}/$binary_name"
            
            # 停止服务
            if systemctl is-active --quiet "$SERVICE_NAME"; then
                print_info "停止服务..."
                systemctl stop "$SERVICE_NAME"
                sleep 1
            fi
            
            # 下载新版本
            if [ -n "$1" ]; then
                # 使用用户指定的 URL
                print_info "从指定 URL 下载新版本: $1"
                download_url="$1"
            else
                # 自动从 GitHub latest 下载
                print_info "从 GitHub 自动下载最新版本..."
                print_info "架构: $ARCH"
                print_info "URL: $github_url"
                download_url="$github_url"
            fi
            
            # 下载文件
            if command -v wget &> /dev/null; then
                print_info "使用 wget 下载..."
                WGET_PROGRESS=$(get_wget_download_args)
                if [[ "$WGET_PROGRESS" == "--show-progress" ]]; then
                    if wget --show-progress "$download_url" -O "$INSTALL_DIR/dockter-agent.new"; then
                        chmod +x "$INSTALL_DIR/dockter-agent.new"
                        mv "$INSTALL_DIR/dockter-agent.new" "$INSTALL_DIR/dockter-agent"
                        print_success "下载完成"
                    else
                        print_error "下载失败"
                        exit 1
                    fi
                else
                    if wget -q --progress=bar "$download_url" -O "$INSTALL_DIR/dockter-agent.new"; then
                        chmod +x "$INSTALL_DIR/dockter-agent.new"
                        mv "$INSTALL_DIR/dockter-agent.new" "$INSTALL_DIR/dockter-agent"
                        print_success "下载完成"
                    else
                        print_error "下载失败"
                        exit 1
                    fi
                fi
            elif command -v curl &> /dev/null; then
                print_info "使用 curl 下载..."
                if curl -L $USE_PROXY --progress-bar "$download_url" -o "$INSTALL_DIR/dockter-agent.new"; then
                    chmod +x "$INSTALL_DIR/dockter-agent.new"
                    mv "$INSTALL_DIR/dockter-agent.new" "$INSTALL_DIR/dockter-agent"
                    print_success "下载完成"
                else
                    print_error "下载失败"
                    exit 1
                fi
            else
                print_error "未找到 wget 或 curl，无法下载"
                exit 1
            fi
            
            # 验证新版本
            if [ ! -f "$INSTALL_DIR/dockter-agent" ] || [ ! -x "$INSTALL_DIR/dockter-agent" ]; then
                print_error "更新后的二进制文件无效"
                exit 1
            fi
            
            print_success "更新完成"
            
            # 启动服务
            start_service
        fi
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
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    print_info "删除服务文件..."
    rm -f "$SERVICE_FILE"
    
    # 删除更新器服务
    if [ -f "/etc/systemd/system/dockter-agent-updater.service" ]; then
        print_info "删除更新器服务..."
        rm -f "/etc/systemd/system/dockter-agent-updater.service"
    fi
    
    systemctl daemon-reload
    
    print_info "删除命令工具..."
    rm -f "$BIN_DIR/dt"
    
    # 询问是否删除安装目录
    echo
    print_warning "是否要删除安装目录 $INSTALL_DIR 及其所有内容？"
    echo "这将删除："
    echo "  - 二进制文件"
    echo "  - 配置文件"
    echo "  - 日志文件"
    echo "  - 数据库文件"
    echo "  - 其他所有数据"
    read -p "确认删除安装目录？(y/N): " delete_dir
    delete_dir=${delete_dir:-N}
    
    if [[ "$delete_dir" =~ ^[Yy]$ ]]; then
        print_info "正在删除安装目录 $INSTALL_DIR..."
        if [ -d "$INSTALL_DIR" ]; then
            rm -rf "$INSTALL_DIR"
            print_success "安装目录已删除"
        else
            print_warning "安装目录不存在，跳过删除"
        fi
    else
        print_info "保留安装目录 $INSTALL_DIR"
        print_info "如需手动删除，请执行: sudo rm -rf $INSTALL_DIR"
    fi
    
    print_success "卸载完成"
}

# 启用自启动
enable_autostart() {
    print_info "启用自启动..."
    systemctl enable "$SERVICE_NAME"
    print_success "自启动已启用"
}

# 禁用自启动
disable_autostart() {
    print_info "禁用自启动..."
    systemctl disable "$SERVICE_NAME"
    print_success "自启动已禁用"
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
        PORT="8080"  # 默认端口
    fi
    
    # 读取 Token
    TOKEN=""
    if [ -f "$CONFIG_FILE" ]; then
        TOKEN=$(grep -o '"api_token"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    fi
    
    # 尝试获取服务器 IP
    SERVER_IP=$(curl -s $USE_PROXY --max-time 5 --connect-timeout 3 https://ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
    
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

# 显示日志
show_logs() {
    local lines="${2:-50}"
    local follow="${3:-false}"
    
    # 尝试多个可能的日志路径
    local log_files=(
        "$INSTALL_DIR/logs/dockter.log"
        "$CONFIG_DIR/logs/dockter.log"
        "$INSTALL_DIR/logs/dockter-agent.log"
    )
    
    local log_file=""
    for file in "${log_files[@]}"; do
        if [ -f "$file" ]; then
            log_file="$file"
            break
        fi
    done
    
    # 如果找不到日志文件，尝试从 .env 读取 LOG_PATH
    if [ -z "$log_file" ] && [ -f "$INSTALL_DIR/.env" ]; then
        local env_log_path=$(grep "^LOG_PATH=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
        if [ -n "$env_log_path" ] && [ -f "$env_log_path" ]; then
            log_file="$env_log_path"
        fi
    fi
    
    # 如果还是找不到，尝试 systemd journal
    if [ -z "$log_file" ]; then
        print_info "未找到日志文件，尝试使用 systemd journal..."
        echo
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null || systemctl list-units --type=service | grep -q "$SERVICE_NAME" 2>/dev/null; then
            if [ "$follow" = "true" ] || [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
                print_info "实时查看 systemd 日志（按 Ctrl+C 退出）..."
                journalctl -u "$SERVICE_NAME" -f --no-pager
            else
                journalctl -u "$SERVICE_NAME" -n "$lines" --no-pager
            fi
            return 0
        else
            print_error "未找到日志文件，且服务未运行"
            print_info "可能的日志文件位置："
            for file in "${log_files[@]}"; do
                echo "  - $file"
            done
            return 1
        fi
    fi
    
    print_info "日志文件: $log_file"
    echo
    
    if [ "$follow" = "true" ] || [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
        print_info "实时查看日志（按 Ctrl+C 退出）..."
        tail -f "$log_file"
    else
        if [ "$lines" = "all" ] || [ "$lines" = "-a" ]; then
            cat "$log_file"
        else
            tail -n "$lines" "$log_file"
        fi
    fi
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
        echo "6) 查看日志"
        echo "7) 更新服务"
        echo "8) 启用自启动"
        echo "9) 禁用自启动"
        echo "10) 卸载服务"
        echo "0) 退出"
        echo
        read -p "请选择操作 [0-10]: " choice
        
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
                echo "查看日志选项："
                echo "1) 查看最后 50 行（默认）"
                echo "2) 查看最后 100 行"
                echo "3) 查看最后 200 行"
                echo "4) 查看全部日志"
                echo "5) 实时跟踪日志（tail -f）"
                read -p "请选择 [1-5 默认1]: " log_choice
                log_choice=${log_choice:-1}
                echo
                case "$log_choice" in
                    2)
                        show_logs "" "100"
                        ;;
                    3)
                        show_logs "" "200"
                        ;;
                    4)
                        show_logs "" "all"
                        ;;
                    5)
                        show_logs "" "-f"
                        ;;
                    *)
                        show_logs "" "50"
                        ;;
                esac
                echo
                read -p "按 Enter 键继续..."
                ;;
            7)
                echo
                update_service
                echo
                read -p "按 Enter 键继续..."
                ;;
            8)
                echo
                enable_autostart
                echo
                read -p "按 Enter 键继续..."
                ;;
            9)
                echo
                disable_autostart
                echo
                read -p "按 Enter 键继续..."
                ;;
            10)
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
Dockter Agent 管理工具

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
  logs [N|-f]     查看日志（默认最后 50 行）
                  logs 100      # 查看最后 100 行
                  logs -f       # 实时跟踪日志
                  logs all      # 查看全部日志
  update [URL]    更新服务（自动从 GitHub latest 下载，可选：指定下载 URL）
                  使用更新器服务进行更新，可通过以下命令查看更新日志：
                  journalctl -u dockter-agent-updater -f
                  或 tail -f /opt/dockter-agent/logs/update.log
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
  dt logs          # 查看日志（最后 50 行）
  dt logs 100      # 查看最后 100 行日志
  dt logs -f       # 实时跟踪日志
  dt update        # 更新服务（使用更新器服务）
  dt update URL    # 从指定 URL 更新服务

更新器服务:
  系统还安装了一个独立的更新器服务，可以通过以下方式触发更新：
  systemctl start dockter-agent-updater
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
        SERVER_IP=$(curl -s $USE_PROXY --max-time 5 --connect-timeout 3 https://ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
        echo "http://$SERVER_IP:$PORT"
        ;;
    logs|log)
        if [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
            show_logs "" "-f"
        else
            show_logs "" "${2:-50}"
        fi
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
    systemctl enable dockter-agent
    print_success "自启动已启用"
}

# 启动服务
start_service() {
    print_info "启动服务..."
    systemctl start dockter-agent
    sleep 2
    
    if systemctl is-active --quiet dockter-agent; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        systemctl status dockter-agent --no-pager -l | tail -n 20
        exit 1
    fi
}

# 防火墙提示
firewall_notice() {
    echo
    print_warning "重要提示"
    echo "如果您的服务器开启了防火墙或云厂商安全组："
    echo "👉 请务必放行端口 $DOCKTER_API_PORT/TCP"
    echo
    echo "例如："
    echo "  ufw allow $DOCKTER_API_PORT/tcp"
    echo "  firewall-cmd --add-port=$DOCKTER_API_PORT/tcp --permanent && firewall-cmd --reload"
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
    echo "   dt update    # 更新服务（使用更新器服务）"
    echo "   dt uninstall # 卸载服务"
    echo
    echo "🔄  更新器服务:"
    echo "   systemctl start dockter-agent-updater  # 触发自动更新"
    echo "   journalctl -u dockter-agent-updater -f  # 查看更新日志"
    echo "   tail -f $INSTALL_DIR/logs/update.log    # 查看更新日志文件"
    echo
    firewall_notice
    echo "====================================="
}

# 主函数
main() {
    print_title
    check_root
    setup_proxy
    detect_system
    
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
    create_systemd_service
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
