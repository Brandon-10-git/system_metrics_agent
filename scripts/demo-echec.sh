#!/usr/bin/env bash
# Provoque volontairement un échec du pipeline, pour la preuve demandée par le TP.
# Usage :  bash scripts/demo-echec.sh trivy   |   bash scripts/demo-echec.sh test   |   bash scripts/demo-echec.sh restore
# Ensuite : git add -A && git commit -m "demo: échec volontaire" && git push  (sur une branche, puis PR vers main)
set -euo pipefail
OLD="python:3.12.13-slim-bookworm"
BAD="python:3.12.0-slim-bullseye"   # image ancienne : vulnérabilités HIGH/CRITICAL corrigées depuis

case "${1:-}" in
  trivy)
    sed -i "s#${OLD}#${BAD}#" Dockerfile.api
    echo "Dockerfile.api utilise maintenant ${BAD} -> Trivy doit échouer, le push doit être bloqué."
    echo "(Si ce tag n'existe plus, prenez n'importe quel ancien tag 3.12.x-slim.)" ;;
  test)
    sed -i 's/assert response.json() == {"status": "ok"}/assert response.json() == {"status": "KO"}/' tests/test_api.py
    echo "tests/test_api.py cassé -> le job 'test' doit échouer, le job 2 ne doit pas démarrer." ;;
  restore)
    sed -i "s#${BAD}#${OLD}#" Dockerfile.api
    sed -i 's/{"status": "KO"}/{"status": "ok"}/' tests/test_api.py
    echo "Fichiers remis dans leur état correct." ;;
  *) echo "Usage : $0 trivy|test|restore"; exit 1 ;;
esac
