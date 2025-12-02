#!/usr/bin/env python3
"""
worker-service: Example background worker for Azure Container Apps

This is a template for building background workers that run without HTTP ingress.
Use this pattern for:
- Queue processors (Azure Storage Queue, Service Bus)
- Scheduled jobs and cron-like tasks
- Event-driven processing
- Long-running background tasks

The worker runs in a loop and can be scaled based on CPU/memory or queue depth.
"""

import os
import signal
import sys
import time
from datetime import datetime

# Configuration from environment variables
WORKER_NAME = os.environ.get("HOSTNAME", "worker")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "5"))

# Graceful shutdown flag
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global shutdown_requested
    print(f"[{datetime.now().isoformat()}] Received signal {signum}, shutting down...")
    shutdown_requested = True


def process_work():
    """
    Main work processing function.

    Replace this with your actual work processing logic:
    - Read from a queue
    - Process files from storage
    - Execute scheduled tasks
    - Handle events
    """
    # Example: Simulate processing work
    print(f"[{datetime.now().isoformat()}] [{WORKER_NAME}] Processing work...")

    # Simulate some work being done
    time.sleep(1)

    print(f"[{datetime.now().isoformat()}] [{WORKER_NAME}] Work completed")


def main():
    """Main worker loop."""
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    print(f"[{datetime.now().isoformat()}] Worker '{WORKER_NAME}' starting...")
    print(f"[{datetime.now().isoformat()}] Poll interval: {POLL_INTERVAL} seconds")

    iteration = 0
    while not shutdown_requested:
        iteration += 1
        print(f"[{datetime.now().isoformat()}] [{WORKER_NAME}] Iteration {iteration}")

        try:
            process_work()
        except Exception as e:
            print(f"[{datetime.now().isoformat()}] [{WORKER_NAME}] Error: {e}")
            # Continue running despite errors
            # In production, you might want to implement exponential backoff

        # Wait before next iteration
        # Use a loop for faster shutdown response
        for _ in range(POLL_INTERVAL):
            if shutdown_requested:
                break
            time.sleep(1)

    print(f"[{datetime.now().isoformat()}] [{WORKER_NAME}] Shutdown complete")
    sys.exit(0)


if __name__ == "__main__":
    main()
