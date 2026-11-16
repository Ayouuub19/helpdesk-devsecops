# Stage 1: builder
FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: runtime
FROM python:3.11-slim AS runtime

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup -u 1001 appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application source with correct ownership
COPY --chown=appuser:appgroup . .

# Remove any .git dirs and .env files for security
RUN find . -name ".git" -exec rm -rf {} + 2>/dev/null || true && \
    find . -name ".env" -exec rm -f {} + 2>/dev/null || true && \
    find . -name ".env.*" -exec rm -f {} + 2>/dev/null || true

USER appuser

ENV PATH=/home/appuser/.local/bin:$PATH

EXPOSE 5000

CMD ["python", "app.py"]
