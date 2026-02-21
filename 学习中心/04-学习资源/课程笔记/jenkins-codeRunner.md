c184bf342d8e4c7a9377fef461d20606

cd /workspace/server/codeRunner-siwu && \
docker compose down --rmi local  && \
docker compose up -d && \
docker image prune -f