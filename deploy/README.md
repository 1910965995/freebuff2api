# 使用 Docker 部署 freebuff2api 到 Linux 服务器

## 目录

- [快速开始](#快速开始)
- [文件说明](#文件说明)
- [详细步骤](#详细步骤)
- [Docker 镜像说明](#docker-镜像说明)
- [Nginx 反向代理](#nginx-反向代理)
- [安全加固](#安全加固)
- [维护命令](#维护命令)
- [常见问题](#常见问题)

---

## 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/XxxXTeam/freebuff2api.git
cd freebuff2api

# 2. 配置环境变量
cp .env.example .env
# 编辑 .env 填入你的 FREEBUFF_TOKEN
nano .env

# 3. 一条命令启动
docker compose up -d
```

启动后访问 `http://你的服务器IP:8000/v1/models` 即可测试。

---

## 文件说明

```
freebuff2api/
├── Dockerfile            # 多阶段构建镜像
├── docker-compose.yml    # 编排文件（API + Nginx）
├── .dockerignore         # 构建上下文排除
└── deploy/
    ├── README.md         # 本文档
    └── nginx.conf        # Nginx 反向代理配置
```

---

## 详细步骤

### 1️⃣ 在服务器上安装 Docker

```bash
# Ubuntu / Debian
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
# 重新登录或 newgrp docker

# 验证
docker --version && docker compose version
```

### 2️⃣ 克隆项目并配置

```bash
git clone https://github.com/XxxXTeam/freebuff2api.git
cd freebuff2api
cp .env.example .env
```

### 3️⃣ 编辑 `.env` 文件

```dotenv
FREEBUFF_TOKEN=your-token-here          # 必填，你的 Freebuff Bearer Token
FREEBUFF_API_KEY=sk-your-secret-key     # 强烈建议设置，保护本地 API
FREEBUFF_HOST=0.0.0.0                   # 容器内必须监听所有接口
FREEBUFF_PORT=8000                      # 容器内部端口
FREEBUFF_DEBUG=false                    # 生产环境关闭调试
FREEBUFF_LOG_LEVEL=INFO                 # 日志级别
```

### 4️⃣ 启动服务

```bash
# 后台启动
docker compose up -d

# 查看日志
docker compose logs -f

# 测试接口
curl http://localhost:8000/healthz
curl http://localhost:8000/v1/models
```

---

## Docker 镜像说明

### 多阶段构建

| 阶段 | 基础镜像 | 用途 |
|------|---------|------|
| `builder` | `uv:python3.13-alpine` | 用 uv 快速安装依赖 |
| `runtime` | `python:3.13-alpine` | 最小运行环境（~120MB） |

### 构建优化

- **分层缓存**：`pyproject.toml` / `uv.lock` 先拷贝，源码后拷贝——不改依赖时不重复安装
- **非 root 运行**：使用 `appuser` 用户运行，提升容器安全性
- **健康检查**：Docker 自动检测服务是否存活

### 手动构建

```bash
# 如果你不想用 docker compose，可以单独构建
docker build -t freebuff2api .
docker run -d \
  --name freebuff2api \
  --env-file .env \
  -p 8000:8000 \
  --restart unless-stopped \
  freebuff2api
```

---

## Nginx 反向代理

`docker-compose.yml` 中包含了一个可选的 Nginx 服务。

### 启用 HTTPS（推荐）

1. 安装证书（使用 Let's Encrypt / Certbot）：

```bash
# 先确保域名解析到服务器
sudo apt install certbot
sudo certbot certonly --standalone -d your-domain.com
```

2. 修改 `deploy/nginx.conf`：
   - 取消 SSL 相关行的注释
   - 将 `your-domain.com` 改为你的实际域名
   - 确认证书路径正确

3. 修改 `docker-compose.yml` 中 nginx 服务的端口映射和证书挂载

4. 重启：

```bash
docker compose down nginx && docker compose up -d nginx
```

### 仅用 HTTP（快速测试，不推荐生产）

默认的 Nginx 配置监听 80 端口，开箱即用：

```bash
# 如果你只需要 API 对外暴露 80 端口
docker compose up -d
```

---

## 安全加固

### ⚡ 必做项

| 措施 | 配置 | 说明 |
|------|------|------|
| ✅ 设置 API Key | `FREEBUFF_API_KEY=sk-强密码` | 不设置则无需认证即可调用 |
| ✅ 关闭调试 | `FREEBUFF_DEBUG=false` | 避免敏感信息泄露 |
| ✅ 绑定 Nginx | 不用直接将 8000 暴露公网 | 通过 Nginx 反代增加控制层 |

### 🔒 进阶加固

1. **Nginx 基础认证**（简单有效）：

```bash
# 生成密码文件
sudo apt install apache2-utils
htpasswd -c ./deploy/.htpasswd admin
```

在 `nginx.conf` 的 `location /` 块中添加：

```nginx
auth_basic "Restricted";
auth_basic_user_file /etc/nginx/.htpasswd;
```

并在 `docker-compose.yml` 中挂载：

```yaml
volumes:
  - ./deploy/.htpasswd:/etc/nginx/.htpasswd:ro
```

2. **IP 白名单**（如仅你使用）：

```nginx
allow 你的IP;
deny all;
```

3. **速率限制**：

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
location / {
    limit_req zone=api burst=20 nodelay;
    # ...
}
```

4. **防火墙**：

```bash
# 只开放必要端口
ufw allow 22/tcp        # SSH
ufw allow 80/tcp        # HTTP
ufw allow 443/tcp       # HTTPS
ufw deny 8000           # 不直接暴露 API
ufw enable
```

---

## 维护命令

### 启动 / 停止

```bash
docker compose up -d           # 启动
docker compose stop            # 停止
docker compose restart         # 重启
docker compose down            # 停止并删除容器
```

### 日志

```bash
docker compose logs -f         # 跟踪所有日志
docker compose logs -f api     # 只跟踪 API 日志
docker compose logs -f nginx   # 只跟踪 Nginx 日志
```

### 更新

```bash
# 拉取最新代码
git pull origin main

# 重新构建并重启
docker compose build --no-cache api
docker compose up -d
```

### 清理

```bash
docker system prune -f         # 清理未使用的容器/镜像
docker compose down -v         # 清理所有（含卷）
```

---

## 常见问题

### Q: 启动后访问 http://IP:8000 没反应？

确保：
1. 容器在运行：`docker ps | grep freebuff2api`
2. 端口映射正确：`docker compose ps`
3. 防火墙未阻止 8000 端口
   ```bash
   sudo ufw status
   sudo ufw allow 8000  # 或通过 Nginx 反代走 80/443
   ```

### Q: 日志报 "FREEBUFF_TOKEN is required"？

检查 `.env` 文件是否存在并正确配置，然后重启：
```bash
docker compose down && docker compose up -d
```

### Q: 怎么查看容器内的配置？

```bash
docker exec freebuff2api env | grep FREEBUFF
```

### Q: 容器一直重启 (restart loop)？

查看日志找出原因：
```bash
docker compose logs api --tail=50
```

常见原因：
- `.env` 文件缺失或格式错误
- 端口被占用（改 `docker-compose.yml` 的端口映射）
- Python 依赖安装失败

### Q: 需要改端口映射？

编辑 `docker-compose.yml`：
```yaml
ports:
  - "8080:8000"   # 宿主机 8080 → 容器 8000
```

### Q: 怎么用 GPU？不需要 —— 本项目只是 API 代理，不跑推理模型。

---
