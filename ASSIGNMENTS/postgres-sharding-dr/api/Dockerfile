FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir --default-timeout=120 --retries 10 fastapi "uvicorn[standard]" asyncpg
COPY . .
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 2"]
