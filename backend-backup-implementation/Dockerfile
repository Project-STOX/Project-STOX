FROM python:3.11-slim

WORKDIR /app

# Install PostgreSQL client tools and dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    curl \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    psycopg2-binary==2.9.9 \
    python-dotenv==1.0.0 \
    requests==2.31.0 \
    schedule==1.2.1

# Copy application code
COPY backup.py .
COPY ind_backup.py .

# Create backups directory
RUN mkdir -p /backups

# Default to running the backup script
CMD ["python", "backup.py"]
