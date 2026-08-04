FROM python:3.12-slim

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Not root. The container's only job is to write one SQLite file in /data,
# which the compose file mounts and chowns to this uid.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin fks
USER fks

ENV FKS_DB_PATH=/data/financekitsync.db
EXPOSE 8501

# Single worker: SQLite is a single-writer store and the workload is one phone
# posting a few batches. Multiple workers would add lock contention for nothing.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8501", "--workers", "1"]
