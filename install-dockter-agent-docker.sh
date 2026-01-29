#!/usr/bin/env bash
set -e

echo "====================================="
echo " Dockter Agent 安装与部署脚本"
echo "====================================="


#####################################
# HTTP 代理设置
#####################################
# 优先检查环境变量 DOCKTER_PROXY
if [ -n "$DOCKTER_PROXY" ]; then
  export HTTP_PROXY="$DOCKTER_PROXY"
  export HTTPS_PROXY="$DOCKTER_PROXY"
  export http_proxy="$DOCKTER_PROXY"
  export https_proxy="$DOCKTER_PROXY"
  USE_PROXY="--proxy $DOCKTER_PROXY"
  echo "✅ 从环境变量 DOCKTER_PROXY 读取代理: $DOCKTER_PROXY"
else
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
      echo "✅ 已设置代理: $PROXY_URL"
    fi
  fi
fi


#####################################
# 检测本机真实 IPv4
#####################################


AUTO_IP=$(curl -s https://ipinfo.io/ip && echo)

echo
echo "检测到本机 IPv4 地址：$AUTO_IP"
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


#####################################
# API 端口设置
#####################################
DEFAULT_API_PORT="19029"

echo
echo "设置 DOCKTER_API_PORT："
read -p "按回车使用默认 [$DEFAULT_API_PORT]，或输入端口号: " USER_API_PORT
USER_API_PORT=${USER_API_PORT:-$DEFAULT_API_PORT}
DOCKTER_API_PORT="$USER_API_PORT"

# 检查 SERVER_IP 是否已包含协议，如果没有则添加 http://
if [[ "$SERVER_IP" =~ ^https?:// ]]; then
  AGENT_ENDPOINT="$SERVER_IP:$DOCKTER_API_PORT"
else
  AGENT_ENDPOINT="http://$SERVER_IP:$DOCKTER_API_PORT"
fi


#####################################
# Compose 根目录
#####################################
DEFAULT_COMPOSE_ROOT="/mnt/compose"

echo
echo "请选择 Dockter Compose 根目录（用于存放项目目录）"
read -p "按回车使用默认 [$DEFAULT_COMPOSE_ROOT]，或输入路径: " USER_COMPOSE_ROOT
USER_COMPOSE_ROOT=${USER_COMPOSE_ROOT:-$DEFAULT_COMPOSE_ROOT}

# 兼容性处理：尝试规范化路径（支持没有 realpath 的系统）
if command -v realpath >/dev/null 2>&1; then
  # 如果 realpath 存在，使用它（-m 允许路径不存在）
  COMPOSE_ROOT=$(realpath -m "$USER_COMPOSE_ROOT" 2>/dev/null || echo "$USER_COMPOSE_ROOT")
elif [ -d "$USER_COMPOSE_ROOT" ]; then
  # 如果路径存在，使用 cd + pwd 获取绝对路径
  COMPOSE_ROOT=$(cd "$USER_COMPOSE_ROOT" && pwd)
else
  # 如果路径不存在且没有 realpath，直接使用用户输入（后续 mkdir 会创建）
  COMPOSE_ROOT="$USER_COMPOSE_ROOT"
fi

AGENT_DIR="$COMPOSE_ROOT/dockter-agent"
YAML_FILE="$AGENT_DIR/docker-compose.yml"

mkdir -p "$AGENT_DIR"


#####################################
# Token 生成
#####################################
generate_token() {
  head -c 32 /dev/urandom | md5sum | cut -d' ' -f1
}

echo
echo "设置 DOCKTER_API_TOKEN："
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


#####################################
# Base URL（不带端口）
#####################################
# 检查 SERVER_IP 是否已包含协议，如果没有则添加 http://
if [[ "$SERVER_IP" =~ ^https?:// ]]; then
  DEFAULT_BASE_URL="$SERVER_IP"
else
  DEFAULT_BASE_URL="http://$SERVER_IP"
fi

echo
echo "设置 DOCKTER_CONTAINER_BASE_URL："
echo "1) 默认：$DEFAULT_BASE_URL"
echo "2) 手动输入（⚠ 不要带端口）"
read -p "请选择 (1/2 默认1): " base_choice
base_choice=${base_choice:-1}

case "$base_choice" in
  2)
    read -p "请输入 URL（不要带端口）: " DOCKTER_CONTAINER_BASE_URL
    # 检查是否已经包含 http:// 或 https://，如果没有则添加 http://
    if [[ ! "$DOCKTER_CONTAINER_BASE_URL" =~ ^https?:// ]]; then
      DOCKTER_CONTAINER_BASE_URL="http://$DOCKTER_CONTAINER_BASE_URL"
    fi
    ;;
  *)
    DOCKTER_CONTAINER_BASE_URL="$DEFAULT_BASE_URL"
    ;;
esac


#####################################
# 是否自动拉镜像
#####################################
echo
echo "设置 DOCKTER_COMPOSE_PULL_IMAGES："
echo "1) false（默认）"
echo "2) true"
read -p "请选择 (1/2 默认1): " pull_choice
pull_choice=${pull_choice:-1}

case "$pull_choice" in
  2) DOCKTER_COMPOSE_PULL_IMAGES="true" ;;
  *) DOCKTER_COMPOSE_PULL_IMAGES="false" ;;
esac


#####################################
# 写入 YAML
#####################################
cat > "$YAML_FILE" <<EOF
services:
  dockter-agent:
    image: shenxianmq/dockter-agent:latest
    container_name: dockter-agent
    restart: unless-stopped

    environment:
      - DOCKTER_MODE=agent
      - HOST_STACK_DIR=$COMPOSE_ROOT
      - DOCKTER_STACK_DIR=/opt/docker-compose
      - DOCKTER_API_TOKEN=$DOCKTER_API_TOKEN
      - DOCKTER_COMPOSE_PULL_IMAGES=$DOCKTER_COMPOSE_PULL_IMAGES
      - DOCKTER_CONTAINER_BASE_URL=$DOCKTER_CONTAINER_BASE_URL
      - DOCKTER_SELF_CONTAINER=dockter-agent
      - DOCKTER_API_PORT=$DOCKTER_API_PORT
      - TZ=Asia/Shanghai
      - LOG_LEVEL=debug

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./static/icons:/app/static/icons
      - $COMPOSE_ROOT:/opt/docker-compose
      - ./config:/app/config
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro

    network_mode: host
    
EOF


#####################################
# 防火墙提示
#####################################
echo
echo "⚠️ 重要提示"
echo "如果您的服务器开启了防火墙或云厂商安全组："
echo "👉 请务必放行端口 $DOCKTER_API_PORT/TCP"
echo
echo "例如："
echo "  ufw allow $DOCKTER_API_PORT/tcp"
echo "  firewall-cmd --add-port=$DOCKTER_API_PORT/tcp --permanent && firewall-cmd --reload"
echo
echo "否则外部将无法访问 Agent"
echo


#####################################
# 确认部署（默认执行）
#####################################
echo "====================================="
echo " YAML 文件位置:"
echo " $YAML_FILE"
echo
echo "=============== 内容预览 ==============="
cat "$YAML_FILE"
echo "====================================="

read -p "是否立即部署？(Y/n): " confirm
confirm=${confirm:-Y}

if [[ "$confirm" =~ ^[Yy]$ ]]; then
  cd "$AGENT_DIR"

  # 检测 Docker Compose 命令
  if docker compose version &>/dev/null; then
    echo "正在拉取最新镜像..."
    docker compose pull
    echo "启动服务..."
    docker compose up -d
  elif command -v docker-compose &>/dev/null; then
    echo "正在拉取最新镜像..."
    docker-compose pull
    echo "启动服务..."
    docker-compose up -d
  else
    echo "❌ 错误：未找到 docker compose 或 docker-compose 命令"
    echo "请先安装 Docker Compose"
    exit 1
  fi

  echo
  echo "🚀 部署完成"
else
  echo "❌ 已取消部署"
fi


#####################################
# 最终信息
#####################################
echo
echo "====================================="
echo " Dockter Agent 信息"
echo "====================================="
echo "👉 Agent 访问地址:"
# 检查 SERVER_IP 是否已包含协议，如果没有则添加 http://
if [[ "$SERVER_IP" =~ ^https?:// ]]; then
  echo "   $SERVER_IP:$DOCKTER_API_PORT"
else
  echo "   http://$SERVER_IP:$DOCKTER_API_PORT"
fi
echo
echo "🔑 API Token:"
echo "   $DOCKTER_API_TOKEN"
echo
echo "📁 Compose 根目录:"
echo "   $COMPOSE_ROOT"
echo
echo "⚠️ 请确认 $DOCKTER_API_PORT 端口已放行！"
echo "====================================="
