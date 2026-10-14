"""Tests de l'API FastAPI (manquants dans le dépôt d'origine)."""
import pytest
from fastapi.testclient import TestClient

from app import api

VALID_PAYLOAD = {
    "agent": "test-agent",
    "event_type": "system_metrics",
    "data": {"cpu": {"percent": 12.5}},
}


@pytest.fixture(autouse=True)
def clean_state():
    """Vide le stockage en mémoire avant et après chaque test."""
    api.received_metrics.clear()
    yield
    api.received_metrics.clear()


@pytest.fixture
def client():
    return TestClient(api.app)


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_latest_without_data_returns_404(client):
    response = client.get("/metrics/latest")

    assert response.status_code == 404


def test_post_then_latest(client):
    post = client.post("/metrics", json=VALID_PAYLOAD)
    latest = client.get("/metrics/latest")

    assert post.status_code == 201
    assert post.json()["total_received"] == 1
    assert latest.status_code == 200
    assert latest.json()["agent"] == "test-agent"
    assert "received_at" in latest.json()


def test_list_metrics(client):
    client.post("/metrics", json=VALID_PAYLOAD)
    client.post("/metrics", json=VALID_PAYLOAD)

    body = client.get("/metrics").json()

    assert body["total"] == 2
    assert len(body["metrics"]) == 2


def test_post_invalid_payload_returns_422(client):
    response = client.post("/metrics", json={"agent": ""})

    assert response.status_code == 422
