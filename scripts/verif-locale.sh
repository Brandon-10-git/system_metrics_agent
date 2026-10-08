#!/usr/bin/env bash
# Vérifie en local tout ce que le pipeline vérifiera en ligne.
# Usage (depuis la racine du projet) :  bash scripts/verif-locale.sh
set -euo pipefail

echo "== 1/5 Tests + couverture"
python -m pytest -q --cov=app --cov-report=term-missing

echo "== 2/5 Build des deux images"
docker build -f Dockerfile.api   -t system-metrics-api:local .
docker build -f Dockerfile.agent -t system-metrics-agent:local .
echo "--> Tailles (à copier dans le rapport) :"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep -E 'REPOSITORY|system-metrics'

echo "== 3/5 docker run de l'API + /health + utilisateur non-root"
docker rm -f api-test >/dev/null 2>&1 || true
docker run -d --rm --name api-test -p 8000:8000 system-metrics-api:local >/dev/null
for i in $(seq 1 20); do
  curl -fs http://localhost:8000/health && break || sleep 1
done
echo
echo -n "Utilisateur dans le conteneur : "; docker exec api-test id -un
docker stop api-test >/dev/null

echo "== 4/5 uptime présent dans l'image de l'agent ?"
docker run --rm system-metrics-agent:local uptime

echo "== 5/5 Scan Trivy (HIGH/CRITICAL corrigeables) -- facultatif en local"
for img in system-metrics-api:local system-metrics-agent:local; do
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    ghcr.io/aquasecurity/trivy:0.69.3 image \
    --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$img" \
    || echo "!! Trivy a signalé des vulnérabilités sur $img"
done

echo "Terminé. Pour tester Compose :  docker compose up --build   puis   curl http://localhost:8000/metrics/latest"
