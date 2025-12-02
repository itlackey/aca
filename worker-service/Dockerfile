# Use a slim Python base image
FROM python:3.11-slim as base

# Set working directory
WORKDIR /app

# Install dependencies
COPY app/requirements.txt ./app/requirements.txt
RUN pip install --no-cache-dir -r app/requirements.txt

# Copy the application code
COPY app ./app

# Run the worker
CMD ["python", "app/main.py"]