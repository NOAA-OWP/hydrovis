FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y git

COPY requirements.txt ./
COPY pyproject.toml ./
COPY README.md ./

RUN pip install uv
RUN uv venv
RUN uv pip install --no-cache-dir -r requirements.txt

COPY src/ /app/src

ENV PYTHONPATH=/app:$PYTHONPATH
