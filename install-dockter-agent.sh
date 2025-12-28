#!/usr/bin/env bash
set -e

echo "====================================="
echo " Dockter Agent 安装与部署脚本"
echo "====================================="


#####################################
# 检测本机真实 IPv4
#####################################
detect_ipv4() {
  ip route get 1.1.1.1 2>/dev/null \
    | awk '/src/ {print $7; exit}' \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' && return

  ip -4 addr show 2>/dev/null \
    | grep -oP '(?<=inet\s)\d+(\.\d+){3}' \
    | grep -v '^127\.' \
    | grep -v '^172\.17\.' \
    | grep -v '^172\.18\.' \
    | grep -v '^172\.19\.' \
    | head -n1 && return

  hostname -I 2>/dev/null \
    | tr ' ' '\n' \
    | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -v '^127\.' \
    | head -n1 && return

  echo "127.0.0.1"
}


AUTO_IP=$(detect_ipv4)

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

AGENT_ENDPOINT="http://$SERVER_IP:19028"


#####################################
# Compose 根目录
#####################################
DEFAULT_COMPOSE_ROOT="/mnt/compose"

echo
echo "请选择 Dockter Compose 根目录（用于存放项目目录）"
read -p "按回车使用默认 [$DEFAULT_COMPOSE_ROOT]，或输入路径: " USER_COMPOSE_ROOT
USER_COMPOSE_ROOT=${USER_COMPOSE_ROOT:-$DEFAULT_COMPOSE_ROOT}

COMPOSE_ROOT=$(realpath -m "$USER_COMPOSE_ROOT")
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
DEFAULT_BASE_URL="http://$SERVER_IP"

echo
echo "设置 DOCKTER_CONTAINER_BASE_URL："
echo "1) 默认：$DEFAULT_BASE_URL"
echo "2) 手动输入（⚠ 不要带端口）"
read -p "请选择 (1/2 默认1): " base_choice
base_choice=${base_choice:-1}

case "$base_choice" in
  2)
    read -p "请输入 URL（不要带端口）: " DOCKTER_CONTAINER_BASE_URL
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

    ports:
      - 19028:19028

    environment:
      - DOCKTER_MODE=agent
      - DOCKTER_STACK_DIR=/opt/docker-compose
      - DOCKTER_API_TOKEN=$DOCKTER_API_TOKEN
      - DOCKTER_COMPOSE_PULL_IMAGES=$DOCKTER_COMPOSE_PULL_IMAGES
      - DOCKTER_CONTAINER_BASE_URL=$DOCKTER_CONTAINER_BASE_URL
      - DOCKTER_SELF_CONTAINER=dockter-agent
      - TZ=Asia/Shanghai
      - LOG_LEVEL=debug

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./static/icons:/app/static/icons
      - $COMPOSE_ROOT:/opt/docker-compose
      - ./config:/app/config

    networks:
      - dockter-agent-network

networks:
  dockter-agent-network:
    driver: bridge
    name: dockter-agent-network
EOF


#####################################
# 防火墙提示
#####################################
echo
echo "⚠️ 重要提示"
echo "如果您的服务器开启了防火墙或云厂商安全组："
echo "👉 请务必放行端口 19028/TCP"
echo
echo "例如："
echo "  ufw allow 19028/tcp"
echo "  firewall-cmd --add-port=19028/tcp --permanent && firewall-cmd --reload"
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

  if command -v docker compose &>/dev/null; then
    docker compose up -d
  else
    docker-compose up -d
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
echo "   http://$SERVER_IP:19028"
echo
echo "🔑 API Token:"
echo "   $DOCKTER_API_TOKEN"
echo
echo "📁 Compose 根目录:"
echo "   $COMPOSE_ROOT"
echo
echo "⚠️ 请确认 19028 端口已放行！"
echo "====================================="
