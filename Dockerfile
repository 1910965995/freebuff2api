# ============================================================
# Stage 1: build — install deps with uv
# ============================================================
FROM ghcr.io/astral-sh/uv:python3.13-alpine AS builder

WORKDIR /app

# 先拷依赖元数据，利用 Docker 缓存层
COPY pyproject.toml uv.lock .python-version ./

RUN uv sync --no-dev --no-install-project

# ============================================================
# Stage 2: runtime — 最小化镜像
# ============================================================
FROM python:3.13-alpine

# 时区 & ca-certificates
RUN apk add --no-cache tzdata ca-certificates && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app

# 从 builder 复制已安装的依赖
COPY --from=builder /app /app
ENV PATH="/app/.venv/bin:$PATH"

# 复制项目源码
COPY freebuff2api/ ./freebuff2api/
COPY main.py pyproject.toml ./

# 非 root 用户运行
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"

EXPOSE 8000

CMD ["uvicorn", "freebuff2api.app:app", "--host", "0.0.0.0", "--port", "8000"]
