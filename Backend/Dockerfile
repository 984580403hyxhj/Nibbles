
# Use Alpine Linux (smaller, often more accessible in China network)
FROM alpine:3.19

# Install Python 3.10 and pip
RUN apk add --no-cache python3 py3-pip python3-dev build-base && \
    ln -sf python3 /usr/bin/python

# Set environment variables to prevent Python from writing pyc files to disc
# and buffering stdout/stderr.
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Set work directory
WORKDIR /app

# Install system dependencies if required (e.g. for lxml or regex if needed)
# RUN apt-get update && apt-get install -y --no-install-recommends gcc libpq-dev && rm -rf /var/lib/apt/lists/*

# Copy requirements keys
COPY requirements.txt .

# Install dependencies from Aliyun PyPI mirror for faster speeds in China
RUN pip3 install --no-cache-dir --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/ --break-system-packages && \
    pip3 install --no-cache-dir -i https://mirrors.aliyun.com/pypi/simple/ -r requirements.txt --break-system-packages

# Copy project files
COPY . .

# Expose port (Cloud providers often ignore this, but good for documentation)
EXPOSE 8000

# Run command. 
# For production (Aliyun ECS/Container), use gunicorn with uvicorn workers.
# Workers = 2 * CPU + 1 usually. Defaulting to 2 here.
CMD ["gunicorn", "server:app", "--workers", "2", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000"]
