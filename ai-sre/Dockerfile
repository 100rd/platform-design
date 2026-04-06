FROM python:3.12-slim AS base

RUN groupadd -r aisre && useradd -r -g aisre -s /sbin/nologin aisre

WORKDIR /app

COPY pyproject.toml .
RUN pip install --no-cache-dir . && rm -rf /root/.cache

COPY . .

RUN chown -R aisre:aisre /app

USER aisre

EXPOSE 8000 9090

CMD ["uvicorn", "agents.orchestrator.main:app", "--host", "0.0.0.0", "--port", "8000"]
