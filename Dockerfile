# Imagen del lab: motor, API y web. El modelo va aparte, en el contenedor de Ollama.
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY --from=ghcr.io/astral-sh/uv:0.8.22 /uv /usr/local/bin/uv
WORKDIR /app

COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project

COPY src ./src
COPY data ./data
COPY site/assets ./site/assets
COPY site/data ./site/data
COPY retos ./retos
RUN uv sync --frozen --no-dev && useradd --uid 10001 --no-create-home lab

USER 10001
ENV PATH="/app/.venv/bin:$PATH" ATTACKLAB_DATA=/data ATTACKLAB_RETOS=/app/retos
EXPOSE 8080
CMD ["attacklab", "serve", "--host", "0.0.0.0", "--port", "8080"]
