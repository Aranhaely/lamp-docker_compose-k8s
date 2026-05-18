# syntax=docker/dockerfile:1

# ============================================================
# STAGE 1: BUILDER
# ============================================================
FROM python:3.12-slim AS builder

# BP: фиксация версии базового образа, slim для баланса размера и совместимости

ENV PYTHONDONTWRITEBYTECODE=1 \
PYTHONUNBUFFERED=1 \
PIP_DISABLE_PIP_VERSION_CHECK=1
# BP: отключение .pyc, буферизации, кэша pip, проверки версии pip

WORKDIR /build

# BP: кэширование apt через BuildKit для ускорения повторных сборок
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
--mount=type=cache,target=/var/lib/apt,sharing=locked \
apt-get update && \
apt-get install -y --no-install-recommends \
gcc g++ make libpq-dev && \
rm -rf /var/lib/apt/lists/*
# BP: --no-install-recommends для минимизации, очистка списков apt

COPY requirements.txt .
# BP: копирование зависимостей до кода — кэширование слоя при изменениях в src

# BP: кэширование pip через BuildKit
RUN --mount=type=cache,target=/root/.cache/pip \
pip install --upgrade pip setuptools wheel && \
pip install -r requirements.txt --prefix=/install
# BP: --prefix=/install изолирует артефакты pip в одном каталоге

# ============================================================
# STAGE 2: RUNTIME
# ============================================================
FROM python:3.12-slim AS runtime

LABEL maintainer="your-team@example.com" \
version="1.0.0" \
description="Production Python service"
# BP: метаданные образа

ENV PYTHONDONTWRITEBYTECODE=1 \
PYTHONUNBUFFERED=1 \
PYTHONPATH=/app
# BP: PYTHONPATH включает рабочий каталог в пути импорта

WORKDIR /app

# BP: только рантайм-библиотеки, без компиляторов и -dev пакетов
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
--mount=type=cache,target=/var/lib/apt,sharing=locked \
apt-get update && \
apt-get install -y --no-install-recommends \
libpq5 && \
rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local
# BP: копирование только артефактов pip, без pip/setuptools/компиляторов

RUN groupadd -r appgroup && \
useradd -r -g appgroup -u 1000 appuser && \
mkdir -p /home/appuser/.cache && \
chown -R appuser:appgroup /home/appuser /app
# BP: непривилегированный пользователь с фиксированным UID

COPY --chown=appuser:appgroup src/ /app/
# BP: копирование кода последним слоем, владелец — appuser

USER appuser
# BP: переключение на непривилегированного пользователя

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
# BP: проверка работоспособности контейнера

EXPOSE 8000
# BP: документирование порта

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
# BP: exec-форма CMD, приложение не запускается от PID 1 в shell