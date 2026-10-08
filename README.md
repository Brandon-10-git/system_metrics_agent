# System Metrics Agent

Un agent Python modulaire capable de collecter les métriques système,
de les formater et de les transmettre en temps réel vers une API ou un
Webhook externe.

## Fonctionnalités

- Collecte du pourcentage CPU.
- Collecte de la mémoire RAM totale, utilisée et disponible.
- Utilisation de `psutil`.
- Utilisation de **`subprocess`** pour exécuter la commande système
  `uptime` et récupérer la charge système.
- Architecture modulaire :
  - `collector.py` : collecte ;
  - `formatter.py` : normalisation du payload ;
  - `sender.py` : envoi HTTP ;
  - `agent.py` : orchestration ;
  - `api.py` : API de réception avec **FastAPI**.
- Configuration externe avec `.env`.
- Gestion des erreurs réseau et des erreurs de collecte.
- Tests automatisés avec `pytest`.

## Architecture

```text
system_metrics_agent/
├── app/                      # code applicatif (agent + API)
│   ├── agent.py  api.py  collector.py  config.py  formatter.py  sender.py
├── tests/                    # tests pytest (test_api, agent, collector, config, formatter, sender)
├── .github/workflows/ci-cd.yml   # pipeline CI/CD
├── Dockerfile.api  Dockerfile.agent  .dockerignore
├── docker-compose.yml        # lancement local complet
├── docker-compose.sonarqube.yml  # (bonus) SonarQube local
├── sonar-project.properties
├── requirements-api.txt  requirements-agent.txt  requirements-dev.txt  requirements.txt
└── .env.example
```

## Installation

Créer un environnement virtuel :

```bash
python -m venv .venv
```

Linux/macOS :

```bash
source .venv/bin/activate
```

Windows :

```powershell
.venv\Scripts\Activate.ps1
```

Installer les dépendances :

```bash
pip install -r requirements-dev.txt   # API + agent + outils de test
```

Créer le fichier de configuration :

```bash
cp .env.example .env
```

Sous Windows, copier manuellement `.env.example` en `.env`.

## Démarrer l'API FastAPI

```bash
uvicorn app.api:app --reload
```

L'API est alors disponible sur :

```text
http://127.0.0.1:8000
```

Documentation interactive FastAPI :

```text
http://127.0.0.1:8000/docs
```

## Démarrer l'agent

Dans un deuxième terminal :

```bash
python -m app.agent
```

L'agent collecte les métriques selon l'intervalle défini dans `.env`
puis les envoie automatiquement vers `METRICS_ENDPOINT`.

## Exemple de configuration

```env
METRICS_ENDPOINT=http://127.0.0.1:8000/metrics
COLLECTION_INTERVAL=5
REQUEST_TIMEOUT=5
```

Pour envoyer vers un webhook externe, remplacer simplement :

```env
METRICS_ENDPOINT=https://example.com/webhook
```

## Exemple de métrique envoyée

```json
{
  "agent": "system-metrics-agent",
  "event_type": "system_metrics",
  "data": {
    "timestamp": "2026-08-27T12:00:00.000000+00:00",
    "hostname": "server-01",
    "cpu": {
      "percent": 23.4,
      "logical_cores": 8
    },
    "memory": {
      "total_bytes": 16777216000,
      "available_bytes": 8000000000,
      "used_bytes": 7777216000,
      "percent": 48.2
    },
    "system": {
      "load_1m": 0.12,
      "load_5m": 0.18,
      "load_15m": 0.20
    }
  }
}
```

## Endpoints

### Vérifier l'état de l'API

```http
GET /health
```

Réponse :

```json
{
  "status": "ok"
}
```

### Envoyer des métriques

```http
POST /metrics
```

### Récupérer la dernière métrique

```http
GET /metrics/latest
```

## Tests

Exécuter toute la suite :

```bash
pytest -q
```

Exécuter avec une couverture de code nécessite l'installation de
`pytest-cov` :

```bash
pip install pytest-cov
pytest --cov=app --cov-report=term-missing
```

## Robustesse

Le projet gère notamment :

- les erreurs d'exécution de `subprocess` ;
- les timeouts ;
- les erreurs de connexion HTTP ;
- les réponses HTTP en erreur ;
- les configurations invalides ;
- les payloads incomplets ;
- l'absence de métriques dans l'API.

## Démonstration du flux

```text
┌──────────────────┐
│ Système          │
│ CPU / RAM        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ collector.py     │
│ psutil           │
│ subprocess       │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ formatter.py     │
│ Payload JSON     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ sender.py        │
│ HTTP POST        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ FastAPI          │
│ /metrics         │
└──────────────────┘
```

---

# Rapport DevOps (TP INGC2)

**Chaîne :** fork → Dockerfiles prod → Docker Compose → pipeline (tests + SonarQube + Quality Gate → build → Trivy → push Docker Hub).

## Choix techniques
- **Base `python:3.12.13-slim-bookworm`** (tag précis, jamais `latest`) : Debian minimale. Alpine (musl) a été écartée : les wheels binaires de `psutil`/`uvloop` y sont moins disponibles, d'où compilation, builds plus longs et comportements parfois différents, pour un gain de taille faible.
- **Multi-stage + venv** : le `builder` installe les dépendances dans `/opt/venv`, copié dans l'image finale ; pas de cache pip, aucun outil de build.
- **Dépendances séparées** (`requirements-api/agent/dev.txt`) : chaque image n'embarque que ce qu'elle utilise ; `pytest` n'est plus dans l'image de production. Versions figées.
- **Cache de couches** : `requirements-*.txt` copié avant le code ; `.dockerignore` exclut `.git`, `.env`, tests, caches.
- **Sécurité** : utilisateur non-root (UID 10001), aucun secret dans l'image, Compose en `read_only` + `cap_drop: ALL` + `no-new-privileges`.
- **Prod** : `uvicorn` sans `--reload`, `--host 0.0.0.0`, `EXPOSE 8000`, `HEALTHCHECK` Python (pas de curl dans l'image).
- **`uptime`** absent de l'image `slim` : fourni par le paquet Debian **`procps`**, installé dans l'image de l'agent seulement (`--no-install-recommends`, index apt supprimés).
- **Pipeline** : actions figées par **SHA de commit** (mutable tags = risque supply-chain, cf. compromission de `trivy-action` en mars 2026) ; droits `contents: read` ; push uniquement sur `main` après scan réussi ; Trivy `HIGH,CRITICAL` + `ignore-unfixed` (ne bloque que ce qui est corrigeable).

## Conteneur vs hôte (3 lignes)
Un conteneur partage le noyau de l'hôte : `hostname` y vaut l'identifiant du conteneur, et les limites (`--memory`, `--cpus`) ne sont pas reflétées par `psutil`. **À vérifier** : `docker run --rm -m 128m system-metrics-agent:local python -c "import psutil; print(psutil.virtual_memory().total)"` (affiche en général la RAM de l'hôte, car `/proc/meminfo` n'est pas virtualisé). Pour superviser réellement une machine, il faut un agent installé sur l'hôte (ou `pid: host` + montage de `/proc`), ou lire les fichiers cgroup pour mesurer le conteneur.

## Tailles d'images (à compléter avec `docker images`)
| Image | Taille |
|---|---|
| system-metrics-api | _… Mo_ |
| system-metrics-agent | _… Mo_ |

## Preuve des contrôles (échec volontaire)
- Exécution rouge : _lien / capture_ — cause : _…_ — push bloqué : _oui_
- Exécution verte après correction : _lien / capture_

## Difficultés rencontrées
- _À compléter (ex. : tests dans `app/tests` alors que le README annonçait `tests/` ; `uptime` absent ; SonarQube local injoignable depuis GitHub → SonarQube Cloud…)_

## Liens
- Fork : _…_ · Docker Hub : `<utilisateur>/system-metrics-api`, `<utilisateur>/system-metrics-agent`
