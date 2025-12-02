"""
Example worker service for Azure Container Apps.

This script runs an infinite loop, printing a timestamped message every
`INTERVAL_SECONDS` seconds.  It reads configuration from environment
variables.  You can customise these variables in your Container Apps
deployment (see aca/containerapp.yml and the deploy script).
"""

import os
import sys
import time
from datetime import datetime


def main() -> None:
    message = os.getenv("MESSAGE", "Hello from worker-service!")
    # Interval is in seconds; default to 10 if not provided or invalid
    try:
        interval = int(os.getenv("INTERVAL_SECONDS", "10"))
    except ValueError:
        interval = 10
    environment = os.getenv("ENVIRONMENT", "development")
    db_connection_string = os.getenv("DB_CONNECTION_STRING", "")

    print(
        f"Worker starting in {environment} environment with interval {interval} seconds",
        flush=True,
    )
    if db_connection_string:
        print(
            "A database connection string was provided. In a real application this "+
            "value would be used to connect to your data store.",
            flush=True,
        )

    try:
        while True:
            now = datetime.utcnow().isoformat()
            print(f"{now} - {message}", flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        print("Worker stopped.", file=sys.stderr)


if __name__ == "__main__":
    main()