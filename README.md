# Dockter Agent

Dockter Agent 是 Dockter 分布式 Docker 管理系统中的 **远程节点组件**。  
安装在每一台需要被管理的服务器上，用于接收来自 Dockter Server 的指令并执行容器管理操作。

> 支持：Linux / macOS / 云服务器 / 物理机 / NAS（支持 Docker 环境）

## ✨ 功能特性

- 🐳 与 Docker Server 通信，直接远程管理 Docker
- 🔑 API Token 安全认证
- 🌐 多节点集中管理
- ⚙️ 支持 Compose 项目目录挂载
- 📦 自动持久化配置
- 🛠️ 支持 Docker Compose 部署
- 🌍 支持 Linux 多平台发行版
- 🍎 支持 macOS（Intel 和 Apple Silicon）

## 📦 环境要求

- 一台 Linux 主机或 macOS 系统
- 已安装 Docker
- 推荐同时安装 docker-compose / docker compose

> 如未安装 Docker，可先执行：

```bash
curl -fsSL https://get.docker.com | bash
```

# 🚀 安装方式

## 🎯 一键自动安装（推荐）

> **最简单的方式**：脚本会自动检测您的系统类型（Linux / macOS / Unraid），并下载对应的安装脚本执行。

### GitHub 直连（默认）

#### 二进制安装

**Linux / Unraid 系统：**

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh")
```

**macOS 系统：**

```bash
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh" -o /tmp/install.sh && bash /tmp/install.sh
```

#### Docker 部署

**Linux / Unraid 系统：**

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh")
```

**macOS 系统：**

```bash
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh" -o /tmp/install-docker.sh && bash /tmp/install-docker.sh
```

### CDN 加速源（推荐，国内访问更快）

> 💡 **推荐使用**：如果 GitHub 访问较慢，可以使用 CDN 加速源，下载速度更快。  
> 📝 **注意**：使用 CDN 安装后，`dt update` 命令会自动使用相同的 CDN 源进行更新。

#### 二进制安装

**Linux / Unraid 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh")
```

**macOS 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh" -o /tmp/install.sh && bash /tmp/install.sh
```

#### Docker 部署

**Linux / Unraid 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh")
```

**macOS 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent.sh" | bash
```

**支持的自动检测：**

- ✅ 普通 Linux 系统（Ubuntu / Debian / CentOS / RHEL 等）
- ✅ macOS 系统（Intel 和 Apple Silicon，自动识别）
- ✅ Unraid 系统（自动识别）
- ✅ 普通 Linux 系统可选择二进制安装或 Docker 部署

---

## 手动选择安装方式

如果您想手动选择特定的安装脚本，可以使用以下方式：

## 二进制安装

> ⚠️ **注意**:
>
> - OpenWrt 系统无法使用二进制安装方式，请使用下方的 Docker 部署方式。
> - **Unraid 系统请使用专用的 Unraid 安装脚本**（见下方）。
> - **macOS 系统请使用专用的 macOS 安装脚本**（见下方）。

### GitHub 直连

#### 标准 Linux 系统

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-binary.sh")
```

#### Unraid 系统

> Unraid 基于 Slackware Linux，使用 SysVinit 而非 systemd，需要使用专用安装脚本。

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-unraid.sh")
```

#### macOS 系统

> macOS 使用 launchd 而非 systemd，需要使用专用安装脚本。支持 Intel (amd64) 和 Apple Silicon (arm64) 架构。

```bash
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-macos.sh" -o /tmp/install-macos.sh && bash /tmp/install-macos.sh
```

### CDN 加速源（推荐，国内访问更快）

> 📝 **注意**：使用 CDN 安装后，`dt update` 命令会自动使用相同的 CDN 源进行更新。

#### 标准 Linux 系统

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-binary.sh")
```

#### Unraid 系统

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-unraid.sh")
```

#### macOS 系统

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-macos.sh" -o /tmp/install-macos.sh && bash /tmp/install-macos.sh
```

> ⚠️ **重要提示**: Unraid 系统运行在 RAM 中（从 U 盘启动），重启后需要重新启动服务。安装脚本会自动在 `/etc/rc.d/rc.local` 中添加启动命令。

## Docker 部署

### GitHub 直连

**Linux / Unraid 系统：**

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh")
```

**macOS 系统：**

```bash
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh" -o /tmp/install-docker.sh && bash /tmp/install-docker.sh
```

### CDN 加速源（推荐，国内访问更快）

> 📝 **注意**：使用 CDN 安装后，`dt update` 命令会自动使用相同的 CDN 源进行更新。

**Linux / Unraid 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
bash <(curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh")
```

**macOS 系统：**

```bash
GITHUB_BASE_URL="https://cdn.jsdelivr.net/gh/shenxianmq/Dockter-Agent@main" \
curl -fsSL "https://raw.githubusercontent.com/shenxianmq/Dockter-Agent/main/install-dockter-agent-docker.sh" -o /tmp/install-docker.sh && bash /tmp/install-docker.sh
```

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

放行端口：

```
19029/TCP（默认，可在安装时自定义）
```

示例：

```bash
# Ubuntu/Debian (ufw)
ufw allow 19029/tcp

# CentOS/RHEL (firewalld)
firewall-cmd --add-port=19029/tcp --permanent && firewall-cmd --reload

# OpenWrt (uci)
uci add firewall rule
uci set firewall.@rule[-1].name='Dockter Agent'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='19029'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload

# Unraid (iptables，通常通过 Web UI 配置)
# 或使用命令行：
iptables -A INPUT -p tcp --dport 19029 -j ACCEPT

# macOS (系统偏好设置 > 安全性与隐私 > 防火墙)
# 或使用命令行：
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/opt/dockter-agent/dockter-agent
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/local/opt/dockter-agent/dockter-agent
```

# 🛠️ 管理命令

安装完成后，可以使用 `dt` 命令管理服务：

```bash
dt status      # 查看服务状态
dt start       # 启动服务
dt stop        # 停止服务
dt restart     # 重启服务
dt info        # 查看访问信息（地址/Token/端口）
dt update      # 更新服务（自动使用安装时的 CDN 源，如果安装时使用了 CDN）
dt update URL  # 从指定 URL 更新服务
dt update sidecar  # 使用更新器服务更新（实时显示日志，仅 OpenWrt）
dt uninstall   # 卸载服务
```

> **Unraid 系统额外说明**:
>
> - 服务脚本位于 `/etc/rc.d/rc.dockter-agent`
> - 可直接使用 `/etc/rc.d/rc.dockter-agent {start|stop|restart|status}` 管理服务
> - 重启后服务会自动启动（已添加到 `/etc/rc.d/rc.local`）

> **macOS 系统额外说明**:
>
> - 使用 launchd 管理服务，plist 文件位于 `/Library/LaunchDaemons/com.dockter.agent.plist`
> - 安装目录位于 `/usr/local/opt/dockter-agent`
> - 服务会自动启动并在系统重启后保持运行
> - 如需手动管理服务，可使用 `launchctl` 命令或 `dt` 管理工具

# ❓ 常见问题

见仓库说明：

https://github.com/shenxianmq/Dockter-Agent
