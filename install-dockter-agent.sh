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
    echo " Dockter Agent 自动安装脚本"
    echo "====================================="
    echo
    echo "此脚本将自动检测您的系统类型，并下载对应的安装脚本"
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
    shift  # 移除第一个参数，剩余参数传递给子脚本
else
    # 默认使用 GitHub raw 地址
    GITHUB_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
fi

# HTTP 代理设置
setup_proxy() {
    # 优先检查环境变量 DOCKTER_PROXY
    if [ -n "$DOCKTER_PROXY" ]; then
        export HTTP_PROXY="$DOCKTER_PROXY"
        export HTTPS_PROXY="$DOCKTER_PROXY"
        export http_proxy="$DOCKTER_PROXY"
        export https_proxy="$DOCKTER_PROXY"
        CURL_PROXY="--proxy $DOCKTER_PROXY"
        print_info "✅ 从环境变量 DOCKTER_PROXY 读取代理: $DOCKTER_PROXY"
        return 0
    fi
    # 检查是否在交互式终端中
    if [ ! -t 0 ]; then
        CURL_PROXY=""
        return 0
    fi
    echo
    echo "是否需要使用 HTTP 代理？"
    echo "1) 不使用代理（默认）"
    echo "2) 使用代理"
    read -p "请选择 (1/2 默认1): " proxy_choice
    proxy_choice=${proxy_choice:-1}
    CURL_PROXY=""
    if [[ "$proxy_choice" == "2" ]]; then
        read -p "请输入代理地址（例如: http://127.0.0.1:7890）: " PROXY_URL
        if [[ -n "$PROXY_URL" ]]; then
            export HTTP_PROXY="$PROXY_URL"
            export HTTPS_PROXY="$PROXY_URL"
            export http_proxy="$PROXY_URL"
            export https_proxy="$PROXY_URL"
            export DOCKTER_PROXY="$PROXY_URL"
            CURL_PROXY="--proxy $PROXY_URL"
            print_success "✅ 已设置代理: $PROXY_URL"
        fi
    fi
}

# 检测系统类型
detect_system() {
    print_info "正在检测系统类型..."
    
    # 检测 macOS
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "未知")
        print_warning "检测到 macOS 系统: $OS_VERSION"
        echo
        print_error "macOS 系统不支持二进制安装方式"
        echo
        print_info "请使用 Docker 部署方式："
        echo "  bash <(curl -fsSL \"https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh\")"
        echo
        print_info "或 macOS 用户："
        echo "  curl -fsSL \"https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh\" -o /tmp/install-docker.sh && bash /tmp/install-docker.sh"
        echo
        exit 1
    fi
    
    # 检测 Unraid
    if [ -f /etc/unraid-version ] || [ -d /boot/config/plugins ]; then
        if [ -f /etc/unraid-version ]; then
            UNRAID_VERSION=$(cat /etc/unraid-version)
            print_success "检测到 Unraid 系统: $UNRAID_VERSION"
        else
            print_success "检测到 Unraid 系统"
        fi
        SYSTEM_TYPE="unraid"
        INSTALL_SCRIPT="install-dockter-agent-unraid.sh"
        return 0
    fi
    
    # 检测是否为 Slackware 系统（Unraid 基于 Slackware）
    if [ -f /etc/slackware-version ] || [ -f /etc/slackware-release ]; then
        print_warning "检测到 Slackware 系统，可能是 Unraid"
        # 检查是否在交互式终端中
        if [ -t 0 ]; then
            echo
            read -p "这是 Unraid 系统吗？(y/N): " is_unraid
            is_unraid=${is_unraid:-N}
            if [[ "$is_unraid" =~ ^[Yy]$ ]]; then
                SYSTEM_TYPE="unraid"
                INSTALL_SCRIPT="install-dockter-agent-unraid.sh"
                return 0
            fi
        else
            # 非交互式环境，默认不是 Unraid
            print_info "非交互式环境，默认按普通 Linux 系统处理"
        fi
    fi
    
    # 检测 OpenWrt（不支持二进制安装，需要使用 Docker）
    if [ -f /etc/openwrt_release ] || [ -d /etc/config ]; then
        if [ -f /etc/openwrt_release ]; then
            . /etc/openwrt_release 2>/dev/null || true
            print_warning "检测到 OpenWrt 系统: ${DISTRIB_ID:-OpenWrt} ${DISTRIB_RELEASE:-未知版本}"
        else
            print_warning "检测到 OpenWrt 系统"
        fi
        SYSTEM_TYPE="openwrt"
        INSTALL_SCRIPT="install-dockter-agent-docker.sh"
        return 0
    fi
    
    # 默认：普通 Linux 系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_success "检测到 Linux 系统: $PRETTY_NAME"
    else
        print_info "检测到 Linux 系统（无法识别具体发行版）"
    fi
    
    SYSTEM_TYPE="linux"
    INSTALL_SCRIPT="install-dockter-agent-binary.sh"
    return 0
}

# 下载并执行安装脚本
download_and_execute_script() {
    # 直接使用根目录的脚本（不再使用 cdn/ 目录）
    local script_url="${GITHUB_BASE_URL}/${INSTALL_SCRIPT}"
    local temp_script="/tmp/${INSTALL_SCRIPT}"
    
    print_info "正在下载安装脚本: ${INSTALL_SCRIPT}"
    print_info "URL: ${script_url}"
    
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s $CURL_PROXY --max-time 10 --connect-timeout 5 -f "${script_url}" -o "${temp_script}"; then
            print_error "下载失败，请检查网络连接"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --timeout=10 --tries=1 "${script_url}" -O "${temp_script}"; then
            print_error "下载失败，请检查网络连接"
            exit 1
        fi
    else
        print_error "未找到 curl 或 wget，无法下载脚本"
        exit 1
    fi
    
    chmod +x "${temp_script}"
    print_success "脚本下载完成"
    
    echo
    print_success "准备执行安装脚本..."
    echo "====================================="
    echo
    
    exec "${temp_script}" "$@"
}

# 询问安装方式（仅普通 Linux 系统）
ask_install_method() {
    if [ "$SYSTEM_TYPE" != "linux" ]; then
        return 0
    fi
    
    # 检查是否在交互式终端中
    if [ ! -t 0 ]; then
        # 非交互式环境，使用默认值（二进制安装）
        print_info "非交互式环境，使用默认安装方式：二进制安装"
        return 0
    fi
    
    echo
    echo "请选择安装方式："
    echo "1) 二进制安装（默认，推荐）"
    echo "2) Docker 部署"
    read -p "请选择 (1/2 默认1): " install_method
    install_method=${install_method:-1}
    
    case "$install_method" in
        2)
            SYSTEM_TYPE="docker"
            INSTALL_SCRIPT="install-dockter-agent-docker.sh"
            print_info "已选择 Docker 部署方式"
            ;;
        *)
            print_info "已选择二进制安装方式"
            ;;
    esac
}

# 主函数
main() {
    # 只在交互式终端中清屏
    if [ -t 0 ]; then
        clear
    fi
    
    print_title
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        echo "使用: sudo $0"
        exit 1
    fi
    
    # 设置代理（如果需要）
    setup_proxy
    
    # 检测系统类型
    detect_system
    
    # 如果是 OpenWrt，提示使用 Docker 版本
    if [ "$SYSTEM_TYPE" = "openwrt" ]; then
        echo
        print_warning "⚠️  重要提示"
        echo "OpenWrt 系统不支持二进制安装方式"
        echo "将自动使用 Docker 部署方式"
        # 检查是否在交互式终端中
        if [ -t 0 ]; then
            echo
            read -p "按 Enter 键继续使用 Docker 部署，或按 Ctrl+C 取消..." dummy
        else
            print_info "非交互式环境，自动继续使用 Docker 部署"
        fi
        SYSTEM_TYPE="docker"
        INSTALL_SCRIPT="install-dockter-agent-docker.sh"
    fi
    
    # 询问安装方式（仅普通 Linux）
    ask_install_method
    
    echo
    print_info "系统类型: ${SYSTEM_TYPE}"
    print_info "将使用安装脚本: ${INSTALL_SCRIPT}"
    echo
    
    # 下载并执行安装脚本
    download_and_execute_script "$@"
}

# 解析命令行参数（传递给子脚本）
main "$@"
