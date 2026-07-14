# Kubernetes Manifests

Estes manifests implantam apenas os cinco microsservicos no EKS.

Os recursos gerenciados da AWS ficam fora do Kubernetes:

- RDS PostgreSQL para auth-service, flag-service e targeting-service
- ElastiCache Redis para evaluation-service
- SQS para evaluation-service e analytics-service
- DynamoDB para analytics-service

## Preparar secrets

Copie o exemplo e preencha os placeholders:

```bash
cp k8s/secrets.example.yaml k8s/secrets.yaml
```

Edite `k8s/secrets.yaml` antes de aplicar:

- troque `<SENHA_RDS>` pela senha do usuario `togglemaster`
- troque `<MASTER_KEY_ADMIN>` pela chave administrativa do auth-service
- troque as credenciais AWS temporarias pelos valores atuais do AWS Academy

O arquivo `k8s/secrets.yaml` nao deve ser commitado com valores reais.

## Aplicar no cluster

Depois que as cinco imagens estiverem publicadas no ECR:

```bash
kubectl apply -k k8s
kubectl get pods -n togglemaster
kubectl get svc -n togglemaster
kubectl get hpa -n togglemaster
```

## Servico publico

Somente o `evaluation-service` esta como `LoadBalancer`, pois ele e o ponto de entrada para avaliar flags.

Os demais servicos estao como `ClusterIP`, acessiveis apenas dentro do cluster.

## Horizontal Pod Autoscaler

Foram criados dois HPAs:

- `evaluation-service-hpa`
- `analytics-service-hpa`

Ambos usam CPU media alvo de 70%:

```bash
kubectl get hpa -n togglemaster
kubectl describe hpa evaluation-service-hpa -n togglemaster
kubectl describe hpa analytics-service-hpa -n togglemaster
```

Se a coluna de CPU aparecer como `<unknown>`, instale/valide o metrics-server no cluster.
