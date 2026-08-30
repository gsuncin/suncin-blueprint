from app.adapters.driven.providers.mock.adapter import FORCE_REJECT
from tests.conftest import greeting_payload


def test_delivers_a_greeting(client, auth_headers):
    response = client.post(
        "/internal/greetings", json=greeting_payload(), headers=auth_headers
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "DELIVERED"
    assert body["message"] == "Hello, Ada!"
    # camelCase on the wire, snake_case in Python (C-5).
    assert body["providerReference"] == "mock-ref-1"
    assert "provider_reference" not in body


def test_a_rejection_is_200_with_a_verdict(client, auth_headers):
    # 4xx would make the BFF treat a provider's answer as its own bug.
    response = client.post(
        "/internal/greetings",
        json=greeting_payload(recipient=FORCE_REJECT),
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["status"] == "REJECTED"
    assert response.json()["errorCode"] == "RECIPIENT_REJECTED"


def test_the_credential_header_is_required(client, auth_headers):
    headers = {k: v for k, v in auth_headers.items() if k != "X-Provider-Credential"}

    response = client.post("/internal/greetings", json=greeting_payload(), headers=headers)

    assert response.status_code == 422


def test_a_malformed_body_is_422_not_a_verdict(client, auth_headers):
    response = client.post(
        "/internal/greetings", json=greeting_payload(recipient=""), headers=auth_headers
    )

    assert response.status_code == 422


def test_the_locale_selects_the_greeting(client, auth_headers):
    response = client.post(
        "/internal/greetings", json=greeting_payload(locale="pt"), headers=auth_headers
    )

    assert response.json()["message"] == "Olá, Ada!"
