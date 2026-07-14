#!/bin/sh
set -eu

BASE_AUTH="http://127.0.0.1:8001"
BASE_FLAG="http://127.0.0.1:8002"
BASE_TARGETING="http://127.0.0.1:8003"
BASE_EVALUATION="http://127.0.0.1:8004"
BASE_ANALYTICS="http://127.0.0.1:8005"
API_KEY="tm_key_dev_service"
FLAG_NAME="proof-$(date +%Y%m%d%H%M%S)"
USER_ID="user-proof-123"

section() {
  printf '\n== %s ==\n' "$1"
}

request() {
  printf '$ %s\n' "$*"
  "$@"
  printf '\n'
}

section "1. Subindo ambiente local"
request docker compose up -d --build

section "2. Health checks dos 5 microsservicos"
request curl -fsS "$BASE_AUTH/health"
request curl -fsS "$BASE_FLAG/health"
request curl -fsS "$BASE_TARGETING/health"
request curl -fsS "$BASE_EVALUATION/health"
request curl -fsS "$BASE_ANALYTICS/health"

section "3. Auth-service validando chave real no banco"
request curl -fsS "$BASE_AUTH/validate" \
  -H "Authorization: Bearer $API_KEY"

section "4. Flag-service criando uma feature flag"
request curl -fsS -X POST "$BASE_FLAG/flags" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"name\":\"$FLAG_NAME\",\"description\":\"Comprovacao E2E local\",\"is_enabled\":true}"

section "5. Targeting-service criando regra de segmentacao"
request curl -fsS -X POST "$BASE_TARGETING/rules" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"flag_name\":\"$FLAG_NAME\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":100}}"

section "6. Evaluation-service avaliando a flag criada"
request curl -fsS "$BASE_EVALUATION/evaluate?user_id=$USER_ID&flag_name=$FLAG_NAME"

section "7. Aguardando analytics-service consumir SQS e gravar no DynamoDB Local"
FOUND_EVENT=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if docker compose logs --tail=200 analytics-service | grep -q "$FLAG_NAME"; then
    FOUND_EVENT=1
    break
  fi
  printf 'Tentativa %s/12: evento ainda nao apareceu nos logs, aguardando...\n' "$attempt"
  sleep 5
done

if [ "$FOUND_EVENT" -ne 1 ]; then
  printf 'ERRO: analytics-service nao registrou o evento da flag %s nos logs.\n' "$FLAG_NAME" >&2
  exit 1
fi

section "8. Evidencia nos logs do analytics-service"
docker compose logs --tail=200 analytics-service | grep "$FLAG_NAME"

section "9. Evidencia no DynamoDB Local"
SCAN_OUTPUT="$(docker compose run --rm --entrypoint aws dynamodb-init \
  dynamodb scan \
  --endpoint-url http://dynamodb:8000 \
  --table-name ToggleMasterAnalytics \
  --output json)"

printf '%s\n' "$SCAN_OUTPUT" | grep "$FLAG_NAME"

section "10. Estado final dos containers"
request docker compose ps

section "Comprovacao concluida"
printf 'Flag usada no teste: %s\n' "$FLAG_NAME"
printf 'Usuario usado no teste: %s\n' "$USER_ID"
