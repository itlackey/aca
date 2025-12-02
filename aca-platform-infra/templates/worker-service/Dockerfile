# Build stage
FROM python:3.12-slim AS build

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.12-slim

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash worker

WORKDIR /app

# Copy dependencies from build stage
COPY --from=build /root/.local /home/worker/.local

# Copy application code
COPY --chown=worker:worker src/ ./src/

# Switch to non-root user
USER worker

# Ensure scripts are in PATH
ENV PATH=/home/worker/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

# Start the worker
CMD ["python", "src/worker.py"]
