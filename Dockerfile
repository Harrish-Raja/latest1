# BreachWatch AI - API service (Swagger at :8081/docs) and Streamlit dashboard (:8501)
# in one container. The dashboard reaches the API at http://localhost:8081, which is
# fixed in config/config.py, so both processes have to share a network namespace.
#
#   docker build -t breachwatch .        (run from the repo root)
#   docker run --init --env-file Project/.env -p 8081:8081 -p 8501:8501 breachwatch

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HOME=/opt/hf-cache

WORKDIR /app

# Dependencies first so code changes don't reinstall torch.
# requirements.txt already points pip at the CPU-only torch wheels.
COPY Project/requirements.txt .
RUN pip install -r requirements.txt

COPY Project/ .

# Build everything the services need at runtime (these outputs are gitignored):
# database + seeded accounts, cleaned data, trained models, and the vector index.
# Indexing downloads the sentence-transformers model into HF_HOME, so the
# running container needs no network access for embeddings.
RUN python run_database_setup.py \
 && python run_data_pipeline.py \
 && python run_model_training.py \
 && python run_knowledge_indexing.py

ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

EXPOSE 8081 8501

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8081/docs'); urllib.request.urlopen('http://localhost:8501/_stcore/health')"

# Start the API and the dashboard side by side; if either one exits, the container stops.
CMD ["bash", "-c", "python run_api_service.py & python -m streamlit run run_dashboard.py --server.address=0.0.0.0 --server.port=8501 --server.headless=true --browser.gatherUsageStats=false & wait -n"]
