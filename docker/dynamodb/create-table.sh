#!/bin/sh
set -eu

until aws dynamodb list-tables --endpoint-url "$AWS_DYNAMODB_ENDPOINT_URL" >/dev/null 2>&1; do
  echo "Aguardando DynamoDB Local..."
  sleep 2
done

aws dynamodb create-table \
  --endpoint-url "$AWS_DYNAMODB_ENDPOINT_URL" \
  --table-name "$AWS_DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
  >/dev/null 2>&1 || true

echo "Tabela DynamoDB pronta: $AWS_DYNAMODB_TABLE"
