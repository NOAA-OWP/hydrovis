FROM python:3.11-slim

WORKDIR /app

COPY src/ /app/src

COPY requirements.txt ./
COPY pyproject.toml ./
COPY README.md ./

RUN pip install uv==0.2.5
RUN uv venv
RUN uv pip install --no-cache-dir -r requirements.txt

ENV PYTHONPATH=/app:$PYTHONPATH
