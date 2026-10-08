from unittest.mock import patch

import pytest

from app import agent
from app.collector import MetricsCollectionError
from app.config import Settings

SETTINGS = Settings(
    metrics_endpoint="http://api:8000/metrics",
    collection_interval=0.01,
    request_timeout=1,
)

METRICS = {
    "timestamp": "2026-01-01T00:00:00+00:00",
    "hostname": "h",
    "cpu": {},
    "memory": {},
    "system": {},
}


@patch("app.agent.send_metrics")
@patch("app.agent.collect_system_metrics")
def test_run_once_collects_formats_and_sends(mock_collect, mock_send):
    mock_collect.return_value = METRICS
    mock_send.return_value = {"status_code": 201}

    result = agent.run_once(SETTINGS)

    assert result == {"status_code": 201}
    sent = mock_send.call_args.kwargs
    assert sent["endpoint"] == "http://api:8000/metrics"
    assert sent["payload"]["event_type"] == "system_metrics"


@patch("app.agent.time.sleep", side_effect=KeyboardInterrupt)
@patch("app.agent.run_once", return_value={"status_code": 201})
@patch("app.agent.Settings.from_env", return_value=SETTINGS)
def test_run_forever_stops_on_keyboard_interrupt(_env, mock_once, _sleep):
    with pytest.raises(KeyboardInterrupt):
        agent.run_forever()

    mock_once.assert_called_once()


@patch("app.agent.time.sleep", side_effect=StopIteration)
@patch("app.agent.run_once", side_effect=MetricsCollectionError("boom"))
@patch("app.agent.Settings.from_env", return_value=SETTINGS)
def test_run_forever_survives_a_failed_cycle(_env, mock_once, _sleep):
    # Une erreur de cycle est journalisée, la boucle continue jusqu'au sleep.
    with pytest.raises(StopIteration):
        agent.run_forever()

    mock_once.assert_called_once()
