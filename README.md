# Dockter Agent

Dockter Agent 是 Dockter 分布式 Docker 管理系统中的 **远程节点组件**。  
安装在每一台需要被管理的服务器上，用于接收来自 Dockter Server 的指令并执行容器管理操作。

> 支持：Linux / 云服务器 / 物理机 / NAS（支持 Docker 环境）

## ✨ 功能特性

- 🐳 与 Docker Server 通信，直接远程管理Docker
- 🔑 API Token 安全认证  
- 🌐 多节点集中管理  
- ⚙️ 支持 Compose 项目目录挂载  
- 📦 自动持久化配置  
- 🛠️ 支持 Docker Compose 部署  
- 🌍 支持 Linux 多平台发行版  

## 📦 环境要求

- 一台 Linux 主机
- 已安装 Docker
- 推荐同时安装 docker-compose / docker compose

> 如未安装 Docker，可先执行：

```bash
curl -fsSL https://get.docker.com | sudo bash
```

# 🚀 一键部署

```bash
curl -fsSL https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh | sudo bash
```

或

```bash
wget -qO- https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh | sudo bash
```

## 安装过程包括：

1. 自动检测服务器 IPv4  
2. 选择 Compose 根目录（默认 /mnt/compose）  
3. 自动创建 dockter-agent 目录  
4. 自动生成 API Token（可手动输入）  
5. 设置 Base URL（不带端口）  
6. 生成 docker-compose.yml  
7. 确认后启动服务  

# 🔐 安装完成后信息

```
Agent 地址:
 http://<服务器IP>:19028

API Token:
 <自动生成>

Compose 目录:
 /mnt/compose
```

# 🔥 防火墙说明

放行端口：

```
19028/TCP
```

示例：

```bash
ufw allow 19028/tcp
firewall-cmd --add-port=19028/tcp --permanent && firewall-cmd --reload
```

# 🔄 升级

```bash
cd /mnt/compose/dockter-agent
docker compose pull
docker compose up -d
```

# 🧹 卸载

```bash
cd /mnt/compose/dockter-agent
docker compose down
rm -rf /mnt/compose/dockter-agent
```

# ❓ 常见问题

见仓库说明：

https://github.com/shenxianmq/Dockter-Agent
