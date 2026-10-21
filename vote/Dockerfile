# base defines a base stage that uses the official python runtime base image
FROM python:3.13-slim@sha256:cf50a4f6ac4f026458b08d5222023d700ac806410dff5e9ca8728fa44f2b850f AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Add curl for healthcheck
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Set the application directory
WORKDIR /usr/local/app

# Install our requirements.txt
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# dev defines a stage for development, where it'll watch for filesystem changes
FROM base AS dev
RUN pip install watchdog
ENV FLASK_ENV=development
CMD ["python", "app.py"]

# final defines the stage that will bundle the application for production
FROM base AS final

# Create an unprivileged user (numeric UID so Kubernetes can verify it later)
RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --no-create-home app

# Copy our code, owned by the unprivileged user
COPY --chown=app:app . .

USER 10001:10001

EXPOSE 8000

CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8000", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]