#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-togglemaster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
API_KEY="${API_KEY:-tm_key_dev_service}"
SQS_QUEUE_URL="${SQS_QUEUE_URL:-https://sqs.us-east-1.amazonaws.com/325662539204/togglemaster-events}"
DYNAMODB_TABLE="${DYNAMODB_TABLE:-ToggleMasterAnalytics}"

RUN_ID="${RUN_ID:-$(date +%Y%m%d%H%M%S)}"
FLAG_NAME="${FLAG_NAME:-eks-auto-proof-${RUN_ID}}"
MANUAL_SQS_FLAG_NAME="${MANUAL_SQS_FLAG_NAME:-eks-manual-sqs-${RUN_ID}}"
USER_ID="${USER_ID:-user-eks-auto-${RUN_ID}}"

LOAD_REQUESTS="${LOAD_REQUESTS:-300}"
LOAD_CONCURRENCY="${LOAD_CONCURRENCY:-20}"
SQS_MESSAGES="${SQS_MESSAGES:-50}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-10}"
DDB_WAIT_ATTEMPTS="${DDB_WAIT_ATTEMPTS:-18}"
DDB_WAIT_SECONDS="${DDB_WAIT_SECONDS:-5}"
AWS_CHECKS_MODE="${AWS_CHECKS_MODE:-cluster}"
AWS_HELPER_IMAGE="${AWS_HELPER_IMAGE:-325662539204.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest}"

if [ -z "${LB_URL:-}" ]; then
  LB_HOST="$(kubectl get svc evaluation-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  LB_URL="http://${LB_HOST}"
fi

section() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '$ %s\n' "$*"
  "$@"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERRO: comando obrigatorio nao encontrado: %s\n' "$1" >&2
    exit 1
  fi
}

curl_in_cluster() {
  local pod_name="$1"
  shift
  kubectl run "$pod_name" -n "$NAMESPACE" --rm -i --restart=Never --image=curlimages/curl -- "$@"
}

aws_python_in_cluster() {
  local pod_name="$1"
  local script="$2"
  local aws_access_key_id
  local aws_secret_access_key
  local aws_session_token

  aws_access_key_id="$(kubectl get secret togglemaster-secrets -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)"
  aws_secret_access_key="$(kubectl get secret togglemaster-secrets -n "$NAMESPACE" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)"
  aws_session_token="$(kubectl get secret togglemaster-secrets -n "$NAMESPACE" -o jsonpath='{.data.AWS_SESSION_TOKEN}' | base64 -d)"

  kubectl run "$pod_name" -n "$NAMESPACE" --rm -i --restart=Never \
    --image="$AWS_HELPER_IMAGE" \
    --env="AWS_REGION=${AWS_REGION}" \
    --env="AWS_SQS_URL=${SQS_QUEUE_URL}" \
    --env="AWS_DYNAMODB_TABLE=${DYNAMODB_TABLE}" \
    --env="AWS_ACCESS_KEY_ID=${aws_access_key_id}" \
    --env="AWS_SECRET_ACCESS_KEY=${aws_secret_access_key}" \
    --env="AWS_SESSION_TOKEN=${aws_session_token}" \
    --command -- python -c "$script"
}

generate_evaluation_load() {
  local active=0
  local i

  for i in $(seq 1 "$LOAD_REQUESTS"); do
    curl -fsS -o /dev/null \
      "${LB_URL}/evaluate?flag_name=${FLAG_NAME}&user_id=load-user-${RUN_ID}-${i}" &

    active=$((active + 1))
    if [ "$active" -ge "$LOAD_CONCURRENCY" ]; then
      wait -n || true
      active=$((active - 1))
    fi
  done

  wait || true
}

watch_hpa_while_loading() {
  local load_pid="$1"

  while kill -0 "$load_pid" >/dev/null 2>&1; do
    printf '\n--- HPA durante carga (%s) ---\n' "$(date '+%H:%M:%S')"
    kubectl get hpa -n "$NAMESPACE" || true
    kubectl get pods -n "$NAMESPACE" -o wide || true
    sleep "$WATCH_INTERVAL_SECONDS"
  done

  wait "$load_pid" || true

  printf '\n--- HPA apos carga (%s) ---\n' "$(date '+%H:%M:%S')"
  kubectl get hpa -n "$NAMESPACE" || true
  kubectl get pods -n "$NAMESPACE" -o wide || true
}

send_manual_sqs_messages() {
  if [ "$AWS_CHECKS_MODE" = "cluster" ]; then
    aws_python_in_cluster sqs-send-manual "
import boto3
import json
import os
from datetime import datetime, timezone

region = os.environ.get('AWS_REGION', '${AWS_REGION}')
queue_url = os.environ.get('AWS_SQS_URL', '${SQS_QUEUE_URL}')
sqs = boto3.client('sqs', region_name=region)

for i in range(1, int('${SQS_MESSAGES}') + 1):
    timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    body = {
        'user_id': f'manual-sqs-user-${RUN_ID}-{i}',
        'flag_name': '${MANUAL_SQS_FLAG_NAME}',
        'result': True,
        'timestamp': timestamp,
    }
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(body))

print('Mensagens enviadas para SQS via pod temporario:', '${SQS_MESSAGES}')
"
    return
  fi

  local i
  for i in $(seq 1 "$SQS_MESSAGES"); do
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    aws sqs send-message \
      --region "$AWS_REGION" \
      --queue-url "$SQS_QUEUE_URL" \
      --message-body "{\"user_id\":\"manual-sqs-user-${RUN_ID}-${i}\",\"flag_name\":\"${MANUAL_SQS_FLAG_NAME}\",\"result\":true,\"timestamp\":\"${timestamp}\"}" \
      >/dev/null
  done
}

show_sqs_attributes() {
  if [ "$AWS_CHECKS_MODE" = "cluster" ]; then
    aws_python_in_cluster sqs-attrs "
import boto3
import os

region = os.environ.get('AWS_REGION', '${AWS_REGION}')
queue_url = os.environ.get('AWS_SQS_URL', '${SQS_QUEUE_URL}')
sqs = boto3.client('sqs', region_name=region)
attrs = sqs.get_queue_attributes(
    QueueUrl=queue_url,
    AttributeNames=['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible'],
)['Attributes']
print('ApproximateNumberOfMessages=' + attrs.get('ApproximateNumberOfMessages', '0'))
print('ApproximateNumberOfMessagesNotVisible=' + attrs.get('ApproximateNumberOfMessagesNotVisible', '0'))
"
    return
  fi

  aws sqs get-queue-attributes \
    --region "$AWS_REGION" \
    --queue-url "$SQS_QUEUE_URL" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --output table
}

wait_for_dynamodb_flag() {
  local flag_name="$1"
  local found=0
  local attempt

  for attempt in $(seq 1 "$DDB_WAIT_ATTEMPTS"); do
    local count
    if [ "$AWS_CHECKS_MODE" = "cluster" ]; then
      count="$(aws_python_in_cluster "ddb-count-${attempt}" "
import boto3
import os

region = os.environ.get('AWS_REGION', '${AWS_REGION}')
table = os.environ.get('AWS_DYNAMODB_TABLE', '${DYNAMODB_TABLE}')
db = boto3.client('dynamodb', region_name=region)
response = db.scan(
    TableName=table,
    FilterExpression='flag_name = :flag',
    ExpressionAttributeValues={':flag': {'S': '${flag_name}'}},
    Select='COUNT',
)
print('COUNT=' + str(response.get('Count', 0)))
" | awk -F= '/^COUNT=/{print $2}' | tail -n 1)"
    else
      count="$(aws dynamodb scan \
        --region "$AWS_REGION" \
        --table-name "$DYNAMODB_TABLE" \
        --filter-expression "flag_name = :flag" \
        --expression-attribute-values "{\":flag\":{\"S\":\"${flag_name}\"}}" \
        --select COUNT \
        --query Count \
        --output text)"
    fi

    printf 'Tentativa %s/%s: DynamoDB flag_name=%s count=%s\n' "$attempt" "$DDB_WAIT_ATTEMPTS" "$flag_name" "$count"

    if [ "$count" != "0" ]; then
      found=1
      break
    fi

    sleep "$DDB_WAIT_SECONDS"
  done

  if [ "$found" -ne 1 ]; then
    printf 'ERRO: nenhum item encontrado no DynamoDB para flag_name=%s\n' "$flag_name" >&2
    exit 1
  fi
}

show_dynamodb_items() {
  local flag_name="$1"
  if [ "$AWS_CHECKS_MODE" = "cluster" ]; then
    aws_python_in_cluster "ddb-items-${flag_name:0:20}" "
import boto3
import json
import os

region = os.environ.get('AWS_REGION', '${AWS_REGION}')
table = os.environ.get('AWS_DYNAMODB_TABLE', '${DYNAMODB_TABLE}')
db = boto3.client('dynamodb', region_name=region)
response = db.scan(
    TableName=table,
    FilterExpression='flag_name = :flag',
    ExpressionAttributeValues={':flag': {'S': '${flag_name}'}},
)
print(json.dumps({
    'Count': response.get('Count', 0),
    'ScannedCount': response.get('ScannedCount', 0),
    'ItemsPreview': response.get('Items', [])[:10],
}, indent=2, default=str))
"
    return
  fi

  aws dynamodb scan \
    --region "$AWS_REGION" \
    --table-name "$DYNAMODB_TABLE" \
    --filter-expression "flag_name = :flag" \
    --expression-attribute-values "{\":flag\":{\"S\":\"${flag_name}\"}}" \
    --output table
}

section "0. Checando dependencias"
require_command kubectl
require_command aws
require_command curl
run aws sts get-caller-identity

section "1. Estado inicial do Kubernetes"
run kubectl get nodes -o wide
run kubectl get pods -n "$NAMESPACE" -o wide
run kubectl get svc -n "$NAMESPACE"
run kubectl get hpa -n "$NAMESPACE"

section "2. Configuracao do teste"
cat <<EOF
LB_URL=${LB_URL}
FLAG_NAME=${FLAG_NAME}
MANUAL_SQS_FLAG_NAME=${MANUAL_SQS_FLAG_NAME}
USER_ID=${USER_ID}
LOAD_REQUESTS=${LOAD_REQUESTS}
LOAD_CONCURRENCY=${LOAD_CONCURRENCY}
SQS_MESSAGES=${SQS_MESSAGES}
SQS_QUEUE_URL=${SQS_QUEUE_URL}
DYNAMODB_TABLE=${DYNAMODB_TABLE}
AWS_CHECKS_MODE=${AWS_CHECKS_MODE}
EOF

section "3. Health publico do evaluation-service"
run curl -fsS "${LB_URL}/health"
printf '\n'

section "4. Health interno dos demais microsservicos"
curl_in_cluster curl-health \
  sh -c 'curl -fsS http://auth-service:8001/health && echo && curl -fsS http://flag-service:8002/health && echo && curl -fsS http://targeting-service:8003/health && echo && curl -fsS http://analytics-service:8005/health && echo'

section "5. Criando flag e regra para teste E2E"
curl_in_cluster curl-create-flag \
  curl -fsS -X POST http://flag-service:8002/flags \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${FLAG_NAME}\",\"description\":\"Comprovacao AWS automatizada\",\"is_enabled\":true}"
printf '\n'

curl_in_cluster curl-create-rule \
  curl -fsS -X POST http://targeting-service:8003/rules \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"flag_name\":\"${FLAG_NAME}\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":100}}"
printf '\n'

section "6. Avaliando uma chamada E2E pelo Load Balancer"
run curl -fsS "${LB_URL}/evaluate?flag_name=${FLAG_NAME}&user_id=${USER_ID}"
printf '\n'

section "7. Gerando carga no evaluation-service e acompanhando HPA"
generate_evaluation_load &
LOAD_PID="$!"
watch_hpa_while_loading "$LOAD_PID"

section "8. Enviando mensagens manuais para SQS"
send_manual_sqs_messages
printf 'Mensagens enviadas manualmente para SQS: %s\n' "$SQS_MESSAGES"

section "9. Acompanhando analytics-service, HPA e consumo da fila"
for attempt in 1 2 3 4 5 6; do
  printf '\n--- Observacao %s/6 (%s) ---\n' "$attempt" "$(date '+%H:%M:%S')"
  kubectl get hpa -n "$NAMESPACE" || true
  kubectl get pods -n "$NAMESPACE" -o wide || true
  show_sqs_attributes || true
  sleep "$WATCH_INTERVAL_SECONDS"
done

section "10. Logs recentes comprovando SQS e DynamoDB"
run kubectl logs -n "$NAMESPACE" deploy/evaluation-service --tail=80
run kubectl logs -n "$NAMESPACE" deploy/analytics-service --tail=120

section "11. Validando dados no DynamoDB"
wait_for_dynamodb_flag "$FLAG_NAME"
wait_for_dynamodb_flag "$MANUAL_SQS_FLAG_NAME"

section "12. Itens no DynamoDB gerados via evaluation-service"
show_dynamodb_items "$FLAG_NAME"

section "13. Itens no DynamoDB gerados por mensagens manuais na SQS"
show_dynamodb_items "$MANUAL_SQS_FLAG_NAME"

section "14. Estado final"
run kubectl get deployments -n "$NAMESPACE"
run kubectl get hpa -n "$NAMESPACE"
run kubectl get pods -n "$NAMESPACE" -o wide

if kubectl get hpa -n "$NAMESPACE" | grep -q '<unknown>'; then
  cat <<'EOF'

AVISO:
O HPA foi criado, mas a CPU apareceu como <unknown>.
Isso indica ausencia/indisponibilidade do metrics-server no cluster, nao erro do manifesto HPA.
Para HPA escalar por CPU, valide:
  kubectl top pods -n togglemaster
  kubectl get apiservice v1beta1.metrics.k8s.io
EOF
fi

section "Comprovacao AWS concluida"
cat <<EOF
Flag E2E: ${FLAG_NAME}
Flag manual SQS: ${MANUAL_SQS_FLAG_NAME}
LoadBalancer: ${LB_URL}
EOF
