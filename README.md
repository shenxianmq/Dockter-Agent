# Dockter Agent

Dockter Agent 是 Dockter 分布式 Docker 管理系统中的 **远程节点组件**。  
安装在每一台需要被管理的服务器上，用于接收来自 Dockter Server 的指令并执行容器管理操作。

> 支持：Linux / 云服务器 / 物理机 / NAS（支持 Docker 环境）

## ✨ 功能特性

- 🐳 与 Docker Server 通信，直接远程管理 Docker
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

如未安装 Docker，可先执行：
```bash
curl -fsSL https://get.docker.com | bash
```

# 🚀 一键安装

脚本会自动检测您的系统类型（Linux / Unraid），并下载对应的安装脚本执行。

**Linux / Unraid 系统：**

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh")
```

**macOS 系统：**

```bash
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh" -o /tmp/install-dockter-agent.sh && bash /tmp/install-dockter-agent.sh
```

💡 **国内用户**：如果 GitHub 访问较慢，可以使用 CDN 加速源：

**Linux / Unraid 系统：**

```bash
export GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main"
bash <(curl -fsSL "$GITHUB_BASE_URL/install-dockter-agent.sh")
```

**macOS 系统：**

```bash
export GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main"
curl -fsSL "$GITHUB_BASE_URL/install-dockter-agent.sh" -o /tmp/install-dockter-agent.sh && bash /tmp/install-dockter-agent.sh
```

# 🐳 Docker Compose 部署

如果您想手动使用 Docker Compose 部署，可以按照以下步骤：

1. **下载或创建 `docker-compose.yml` 文件**

   项目根目录已包含 `docker-compose.yml` 文件，您可以直接使用或根据需要进行修改。

2. **修改配置**

   编辑 `docker-compose.yml` 文件，修改以下关键配置：
   - `DOCKTER_API_TOKEN`: 设置您的 API Token（建议使用强随机字符串）
   - `DOCKTER_CONTAINER_BASE_URL`: 设置服务器 IP 地址（如：`http://192.168.1.100`）
   - `DOCKTER_API_PORT`: API 端口（默认 19029）
   - `HOST_STACK_DIR` 和挂载路径：Compose 项目根目录（默认 `/mnt/compose`）

3. **启动服务**

   ```bash
   # 使用 docker compose（推荐）
   docker compose up -d
   
   # 或使用 docker-compose
   docker-compose up -d
   ```

4. **查看日志**

   ```bash
   docker compose logs -f dockter-agent
   ```

5. **停止服务**

   ```bash
   docker compose down
   ```

> 💡 **提示**：使用 Docker Compose 部署时，请确保已放行相应的端口（默认 19029）。

# 🔐 安装完成后信息

安装完成后，脚本会显示以下信息：

```
Agent 地址:
 http://<服务器IP>:19029

API Token:
 <自动生成>

Compose 目录:
 /mnt/compose
```

> 注意：默认 API 端口为 **19029**，可在安装时自定义。

# 🔥 防火墙说明

放行端口：**19029/TCP**（默认，可在安装时自定义）

示例：

```bash
# Ubuntu/Debian (ufw)
ufw allow 19029/tcp

# CentOS/RHEL (firewalld)
firewall-cmd --add-port=19029/tcp --permanent && firewall-cmd --reload
```

# 🛠️ 管理命令

安装完成后，可以使用 `dt` 命令管理服务：

```bash
dt status      # 查看服务状态
dt start       # 启动服务
dt stop        # 停止服务
dt restart     # 重启服务
dt info        # 查看访问信息（地址/Token/端口）
dt update      # 更新服务
dt uninstall   # 卸载服务
```

# ❓ 常见问题

见仓库说明：https://github.com/shenxianmq/Dockter-Agent
