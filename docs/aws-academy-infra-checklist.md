# Passo a Passo - Infraestrutura AWS Academy

Este guia cobre a **Opcao A (AWS Academy)** do Tech Challenge.

Objetivo desta etapa:

```text
Provisionar manualmente, via Console da AWS, todos os recursos de nuvem que os microsservicos precisam antes do deploy em Kubernetes.
```

Importante:

```text
Na Opcao A, NAO use eksctl create cluster.
O cluster EKS e o Managed Node Group devem ser criados pelo Console da AWS.
Quando o console pedir IAM Role, selecione LabRole.
```

## 0. Arquitetura Que Vamos Criar

No Docker Compose local, nos subimos tudo na maquina:

```text
5 microsservicos
PostgreSQL local
Redis local
DynamoDB Local
ElasticMQ/SQS local
```

Na AWS, a separacao correta e:

```text
EKS/Kubernetes:
  auth-service
  flag-service
  targeting-service
  evaluation-service
  analytics-service

AWS gerenciado, fora do Kubernetes:
  3 RDS PostgreSQL
  1 ElastiCache Redis
  1 DynamoDB
  1 SQS
  5 repositorios ECR
```

Ou seja: **nao recriamos banco, fila e cache dentro do Kubernetes**. O Kubernetes roda os containers dos microsservicos, e eles apontam para os endpoints AWS.

## 1. Padroes do Projeto

Use uma unica regiao para tudo.

Sugestao:

```text
us-east-1
```

Nomes sugeridos:

```text
EKS cluster: togglemaster-cluster
Node group: togglemaster-node-group
SQS queue: togglemaster-events
DynamoDB table: ToggleMasterAnalytics
RDS auth: togglemaster-auth-db
RDS flag: togglemaster-flag-db
RDS targeting: togglemaster-targeting-db
ElastiCache Redis: togglemaster-redis
```

Variaveis importantes para anotar durante a criacao:

```text
AWS_REGION=
AWS_ACCOUNT_ID=
EKS_CLUSTER_NAME=
EKS_CLUSTER_SECURITY_GROUP=
NODE_SECURITY_GROUP=
AUTH_RDS_ENDPOINT=
FLAG_RDS_ENDPOINT=
TARGETING_RDS_ENDPOINT=
REDIS_ENDPOINT=
SQS_QUEUE_URL=
SQS_QUEUE_ARN=
DYNAMODB_TABLE=
ECR_AUTH_URI=
ECR_FLAG_URI=
ECR_TARGETING_URI=
ECR_EVALUATION_URI=
ECR_ANALYTICS_URI=
```

## 2. Criar o Cluster EKS Pelo Console

Checklist do enunciado:

```text
[ ] Criar 1 cluster AWS EKS usando o Console da AWS
[ ] Nao usar eksctl create cluster
[ ] Cluster Role: selecionar LabRole
```

### 2.1 Abrir o EKS

1. Entre no Console AWS do Academy.
2. Confirme a regiao no canto superior direito:

```text
us-east-1
```

3. Acesse:

```text
Elastic Kubernetes Service -> Clusters
```

4. Clique:

```text
Add cluster -> Create
```

Se aparecer a escolha entre modo automatico e customizado, escolha configuracao customizada.

Se aparecer `EKS Auto Mode`, deixe desativado. O enunciado pede Managed Node Group tradicional.

### 2.2 Configurar o Cluster

Preencha:

```text
Name: togglemaster-cluster
Kubernetes version: usar a versao padrao/recomendada pelo Console
Cluster IAM role: LabRole
```

Se aparecer opcao de acesso administrativo:

```text
Bootstrap cluster administrator access: enabled/allow
```

Se aparecer modo de autenticacao:

```text
Cluster authentication mode: API and ConfigMap
```

Se o console nao mostrar essa opcao, siga com o padrao.

### 2.3 Networking do Cluster

Selecione:

```text
VPC: a VPC disponivel do laboratorio
Subnets: pelo menos 2 subnets
Security groups: deixe o console criar/selecionar o padrao, se nao houver exigencia do lab
Cluster endpoint access: Public ou Public and private
```

Para laboratorio com pouco tempo, `Public` ou `Public and private` facilita o uso do `kubectl` da sua maquina ou CloudShell.

### 2.4 Add-ons

Mantenha os add-ons padrao:

```text
Amazon VPC CNI
kube-proxy
CoreDNS
```

Nao remova esses add-ons. Eles sao necessarios para rede e DNS do cluster.

### 2.5 Criar e Aguardar

1. Revise.
2. Clique em criar.
3. Aguarde:

```text
Status: Active
```

Isso pode levar varios minutos.

Anote:

```text
EKS_CLUSTER_NAME=togglemaster-cluster
EKS_CLUSTER_REGION=us-east-1
EKS_CLUSTER_ENDPOINT=<endpoint exibido no console>
EKS_CLUSTER_SECURITY_GROUP=<security group do cluster>
```

Evidencia para entrega:

```text
Print do cluster com Status = Active
```

## 3. Criar Managed Node Group Pelo Console

Checklist do enunciado:

```text
[ ] Criar 1 Managed Node Group pelo Console
[ ] Node IAM Role: selecionar LabRole
[ ] Auto Scaling: Minimo=1, Desejado=2, Maximo=4
```

### 3.1 Abrir Compute do Cluster

1. Acesse:

```text
EKS -> Clusters -> togglemaster-cluster
```

2. Va em:

```text
Compute -> Add node group
```

### 3.2 Configurar Node Group

Preencha:

```text
Name: togglemaster-node-group
Node IAM role: LabRole
```

Tipo de AMI:

```text
Amazon Linux 2 ou Amazon Linux 2023, conforme padrao do console
```

Capacity type:

```text
On-Demand
```

Instance types:

```text
t3.small
```

Se `t3.small` nao estiver disponivel, use:

```text
t3.medium
```

Disk size:

```text
20 GiB
```

### 3.3 Auto Scaling

Configure exatamente como pedido:

```text
Minimum size: 1
Desired size: 2
Maximum size: 4
```

### 3.4 Subnets do Node Group

Selecione subnets da mesma VPC do cluster.

Preferencialmente use as mesmas subnets selecionadas no cluster.

### 3.5 Criar e Aguardar

1. Revise.
2. Crie o node group.
3. Aguarde:

```text
Status: Active
```

Anote:

```text
NODE_GROUP_NAME=togglemaster-node-group
NODE_IAM_ROLE=LabRole
NODE_MIN=1
NODE_DESIRED=2
NODE_MAX=4
NODE_SECURITY_GROUP=<security group usado pelos nodes>
```

Evidencia para entrega:

```text
Print do Managed Node Group com Status = Active
```

## 4. Configurar kubectl

Depois que o cluster e o node group estiverem ativos, configure seu terminal.

Na sua maquina ou no AWS CloudShell:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name togglemaster-cluster
```

Valide:

```bash
kubectl get nodes
```

Resultado esperado:

```text
NAME        STATUS   ROLES    AGE   VERSION
...         Ready    <none>   ...   ...
...         Ready    <none>   ...   ...
```

Valide tambem os pods do sistema:

```bash
kubectl get pods -A
```

Resultado esperado:

```text
kube-system pods Running
```

Evidencia para entrega:

```text
Output de kubectl get nodes
Output de kubectl get pods -A
```

## 5. Criar Repositorios ECR

Checklist do enunciado:

```text
[ ] Criar 5 repositorios ECR, um para cada microsservico
[ ] Publicar as imagens Docker criadas na etapa 1
```

Crie os repositorios:

```text
auth-service
flag-service
targeting-service
evaluation-service
analytics-service
```

No Console:

```text
Elastic Container Registry -> Repositories -> Create repository
```

Configuracao sugerida:

```text
Visibility: Private
Repository name: <nome-do-servico>
Image tag mutability: Mutable
Scan on push: Enabled se estiver disponivel
Encryption: AES-256 padrao
```

Anote o URI de cada repositorio:

```text
ECR_AUTH_URI=<account-id>.dkr.ecr.us-east-1.amazonaws.com/auth-service
ECR_FLAG_URI=<account-id>.dkr.ecr.us-east-1.amazonaws.com/flag-service
ECR_TARGETING_URI=<account-id>.dkr.ecr.us-east-1.amazonaws.com/targeting-service
ECR_EVALUATION_URI=<account-id>.dkr.ecr.us-east-1.amazonaws.com/evaluation-service
ECR_ANALYTICS_URI=<account-id>.dkr.ecr.us-east-1.amazonaws.com/analytics-service
```

Evidencia para entrega:

```text
Print dos 5 repositorios ECR criados
```

## 6. Criar Bancos RDS PostgreSQL

Checklist do enunciado:

```text
[ ] Criar 3 instancias AWS RDS for PostgreSQL independentes
[ ] RDS 1 para auth-service
[ ] RDS 2 para flag-service
[ ] RDS 3 para targeting-service
```

### 6.1 Configuracao Geral Recomendada

Use configuracoes pequenas para laboratorio:

```text
Engine: PostgreSQL
Template: Free tier, Dev/Test ou equivalente disponivel no Academy
DB instance class: db.t3.micro, db.t4g.micro ou a menor disponivel
Storage: minimo permitido
Public access: depende do teste
```

Sobre `Public access`:

```text
Para deploy no EKS:
  Pode ser privado, desde que esteja na mesma VPC do EKS.

Para testar da sua maquina local:
  Precisa ser publico ou voce precisa usar CloudShell/bastion/tunel.
```

Com pouco tempo, se o laboratorio permitir, use `Public access: Yes` temporariamente e restrinja o Security Group ao seu IP. Depois, para o deploy no EKS, libere tambem o Security Group dos nodes.

### 6.2 RDS do auth-service

Crie:

```text
DB identifier: togglemaster-auth-db
Initial database name: auth_db
Master username: togglemaster
Master password: <senha-segura>
Port: 5432
```

Script de schema:

```text
auth-service/db/init.sql
```

Connection string:

```text
postgres://togglemaster:<senha>@<AUTH_RDS_ENDPOINT>:5432/auth_db?sslmode=require
```

Anote:

```text
AUTH_RDS_ENDPOINT=
AUTH_DATABASE_URL=
```

### 6.3 RDS do flag-service

Crie:

```text
DB identifier: togglemaster-flag-db
Initial database name: flags_db
Master username: togglemaster
Master password: <senha-segura>
Port: 5432
```

Script de schema:

```text
flag-service/db/init.sql
```

Connection string:

```text
postgres://togglemaster:<senha>@<FLAG_RDS_ENDPOINT>:5432/flags_db?sslmode=require
```

Anote:

```text
FLAG_RDS_ENDPOINT=
FLAG_DATABASE_URL=
```

### 6.4 RDS do targeting-service

Crie:

```text
DB identifier: togglemaster-targeting-db
Initial database name: targeting_db
Master username: togglemaster
Master password: <senha-segura>
Port: 5432
```

Script de schema:

```text
targeting-service/db/init.sql
```

Connection string:

```text
postgres://togglemaster:<senha>@<TARGETING_RDS_ENDPOINT>:5432/targeting_db?sslmode=require
```

Anote:

```text
TARGETING_RDS_ENDPOINT=
TARGETING_DATABASE_URL=
```

### 6.5 Security Groups dos RDS

Cada RDS precisa aceitar conexao na porta 5432.

Para os pods no EKS acessarem:

```text
Type: PostgreSQL
Port: 5432
Source: NODE_SECURITY_GROUP
```

Para voce rodar scripts SQL da sua maquina:

```text
Type: PostgreSQL
Port: 5432
Source: <seu-ip-publico>/32
```

Evite deixar:

```text
0.0.0.0/0
```

### 6.6 Rodar Scripts SQL nos RDS

Depois que cada RDS estiver disponivel, execute os scripts.

Exemplo:

```bash
psql "postgres://togglemaster:<senha>@<AUTH_RDS_ENDPOINT>:5432/auth_db?sslmode=require" \
  -f auth-service/db/init.sql
```

```bash
psql "postgres://togglemaster:<senha>@<FLAG_RDS_ENDPOINT>:5432/flags_db?sslmode=require" \
  -f flag-service/db/init.sql
```

```bash
psql "postgres://togglemaster:<senha>@<TARGETING_RDS_ENDPOINT>:5432/targeting_db?sslmode=require" \
  -f targeting-service/db/init.sql
```

Evidencia para entrega:

```text
Print dos 3 RDS disponiveis
Output dos scripts SQL executados com sucesso
```

## 7. Criar ElastiCache Redis

Checklist do enunciado:

```text
[ ] Criar 1 cluster AWS ElastiCache for Redis
[ ] Usar no evaluation-service
```

No Console:

```text
ElastiCache -> Redis caches -> Create
```

Configuracao sugerida:

```text
Name: togglemaster-redis
Engine: Redis ou Valkey/Redis OSS conforme console
Node type: menor disponivel no lab
Number of replicas: 0 se permitido
Port: 6379
VPC: mesma VPC do EKS
Subnets: mesmas subnets/VPC do EKS
```

Security Group:

```text
Type: Redis
Port: 6379
Source: NODE_SECURITY_GROUP
```

Anote:

```text
REDIS_ENDPOINT=<primary endpoint do redis>
REDIS_URL=redis://<REDIS_ENDPOINT>:6379
```

Observacao importante:

```text
ElastiCache normalmente nao e acessivel diretamente da sua maquina local.
Ele foi feito para ser acessado de dentro da VPC.
No deploy final, os pods do EKS acessarao o Redis se estiverem na mesma VPC e com Security Group correto.
```

Evidencia para entrega:

```text
Print do ElastiCache criado
Endpoint anotado
```

## 8. Criar DynamoDB

Checklist do enunciado:

```text
[ ] Criar 1 tabela AWS DynamoDB
[ ] Usar no analytics-service
```

O codigo do `analytics-service` espera:

```text
Table name: ToggleMasterAnalytics
Partition key: event_id
Partition key type: String
```

No Console:

```text
DynamoDB -> Tables -> Create table
```

Configure:

```text
Table name: ToggleMasterAnalytics
Partition key: event_id
Partition key type: String
Sort key: vazio
Table settings: Default settings ou On-demand
```

Anote:

```text
AWS_DYNAMODB_TABLE=ToggleMasterAnalytics
```

Evidencia para entrega:

```text
Print da tabela DynamoDB criada
```

## 9. Criar SQS

Checklist do enunciado:

```text
[ ] Criar 1 fila AWS SQS Standard
[ ] Usar no evaluation-service e analytics-service
```

No Console:

```text
SQS -> Queues -> Create queue
```

Configure:

```text
Type: Standard
Name: togglemaster-events
Visibility timeout: padrao ou 30 segundos
Delivery delay: 0
Receive message wait time: pode deixar 0 ou usar long polling
```

Depois de criar, abra a fila e anote:

```text
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/<account-id>/togglemaster-events
SQS_QUEUE_ARN=arn:aws:sqs:us-east-1:<account-id>:togglemaster-events
```

Variavel usada pelo codigo:

```text
AWS_SQS_URL=<SQS_QUEUE_URL>
```

Evidencia para entrega:

```text
Print da fila SQS criada
Queue URL e ARN anotados
```

## 10. Permissoes AWS Para SQS e DynamoDB

No AWS Academy, a `LabRole` normalmente ja tem permissoes amplas para o laboratorio.

Como o enunciado diz que os nodes devem usar `LabRole`, os pods rodando nos nodes herdam acesso via role do node quando usam o SDK AWS.

O `evaluation-service` precisa:

```text
sqs:SendMessage
```

O `analytics-service` precisa:

```text
sqs:ReceiveMessage
sqs:DeleteMessage
dynamodb:PutItem
```

Se ocorrer erro de permissao, verificar:

```text
Node IAM Role = LabRole
LabRole contem permissoes para SQS e DynamoDB
```

## 11. Variaveis de Ambiente Para Kubernetes

Essas variaveis vao entrar nos manifests Kubernetes como `ConfigMap` e `Secret`.

### auth-service

```text
PORT=8001
DATABASE_URL=postgres://togglemaster:<SENHA_RDS>@togglemaster-auth-db.cknqp4egvwvw.us-east-1.rds.amazonaws.com:5432/auth_db?sslmode=require
MASTER_KEY=<MASTER_KEY_ADMIN>
```

### flag-service

```text
PORT=8002
DATABASE_URL=postgres://togglemaster:<SENHA_RDS>@togglemaster-flag-db.cknqp4egvwvw.us-east-1.rds.amazonaws.com:5432/flags_db?sslmode=require
AUTH_SERVICE_URL=http://auth-service:8001
```

### targeting-service

```text
PORT=8003
DATABASE_URL=postgres://togglemaster:<SENHA_RDS>@togglemaster-targeting-db.cknqp4egvwvw.us-east-1.rds.amazonaws.com:5432/targeting_db?sslmode=require
AUTH_SERVICE_URL=http://auth-service:8001
```

### evaluation-service

```text
PORT=8004
REDIS_URL=redis://togglemaster-redis.8cwwyh.ng.0001.use1.cache.amazonaws.com:6379
FLAG_SERVICE_URL=http://flag-service:8002
TARGETING_SERVICE_URL=http://targeting-service:8003
SERVICE_API_KEY=tm_key_dev_service
AWS_REGION=us-east-1
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/325662539204/togglemaster-events
```

### analytics-service

```text
PORT=8005
AWS_REGION=us-east-1
AWS_SQS_URL=https://sqs.us-east-1.amazonaws.com/325662539204/togglemaster-events
AWS_DYNAMODB_TABLE=ToggleMasterAnalytics
```

Observacoes:

```text
<SENHA_RDS> deve ser a senha criada para o usuario togglemaster no RDS.
<MASTER_KEY_ADMIN> deve ser uma chave administrativa escolhida para proteger /admin/keys no auth-service.
tm_key_dev_service ja foi semeada em auth-service/db/init.sql e pode ser usada pelos servicos internos.
```

Nao usar em AWS real:

```text
AWS_SQS_ENDPOINT_URL
AWS_DYNAMODB_ENDPOINT_URL
```

Essas variaveis sao apenas para ElasticMQ e DynamoDB Local.

## 12. Publicar Imagens Docker no ECR

Depois de criar os repositorios ECR, faca login:

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

Build, tag e push de cada imagem:

```bash
docker build -t auth-service ./auth-service
docker tag auth-service:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
```

```bash
docker build -t flag-service ./flag-service
docker tag flag-service:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/flag-service:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/flag-service:latest
```

```bash
docker build -t targeting-service ./targeting-service
docker tag targeting-service:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/targeting-service:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/targeting-service:latest
```

```bash
docker build -t evaluation-service ./evaluation-service
docker tag evaluation-service:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/evaluation-service:latest
```

```bash
docker build -t analytics-service ./analytics-service
docker tag analytics-service:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/analytics-service:latest
```

Evidencia para entrega:

```text
Print dos repositorios ECR com imagens publicadas
```

## 13. Manifests Kubernetes e HPA

Manifests criados:

```text
k8s/namespace.yaml
k8s/configmap.yaml
k8s/secrets.yaml
k8s/auth-service.yaml
k8s/flag-service.yaml
k8s/targeting-service.yaml
k8s/evaluation-service.yaml
k8s/analytics-service.yaml
k8s/evaluation-hpa.yaml
k8s/analytics-hpa.yaml
k8s/kustomization.yaml
```

HPA exigido no enunciado:

```text
[x] HorizontalPodAutoscaler para evaluation-service
[x] HorizontalPodAutoscaler para analytics-service
[x] Baseado em utilizacao media de CPU
[x] target averageUtilization: 70
```

Workaround para AWS Academy:

```text
O analytics-service consome mensagens da SQS.
Quando a fila encher, o processamento aumenta, a CPU sobe e o HPA escala mais pods.
No Academy, usamos CPU como proxy em vez de escalar diretamente por metrica de fila SQS.
```

Comandos de validacao:

```bash
kubectl apply -k k8s
kubectl get hpa -n togglemaster
kubectl describe hpa evaluation-service-hpa -n togglemaster
kubectl describe hpa analytics-service-hpa -n togglemaster
```

## 14. Checklist Final de Evidencias

Salve prints ou outputs de:

```text
[ ] EKS cluster togglemaster-cluster com Status Active
[ ] Managed Node Group togglemaster-node-group com Status Active
[ ] kubectl get nodes mostrando nodes Ready
[ ] 5 repositorios ECR criados
[ ] 5 imagens publicadas no ECR
[ ] 3 RDS PostgreSQL criados
[ ] Scripts SQL executados nos 3 RDS
[ ] ElastiCache Redis criado
[ ] DynamoDB table ToggleMasterAnalytics criada
[ ] SQS queue togglemaster-events criada
[ ] HPA evaluation-service criado
[ ] HPA analytics-service criado
[ ] Endpoints/URLs anotados
```

## 15. Ordem Recomendada Para Executar

Siga exatamente esta ordem para evitar retrabalho:

```text
1. Escolher regiao us-east-1
2. Criar EKS pelo Console com LabRole
3. Criar Managed Node Group pelo Console com LabRole
4. Validar kubectl get nodes
5. Criar 5 repositorios ECR
6. Criar DynamoDB
7. Criar SQS
8. Criar 3 RDS PostgreSQL
9. Ajustar Security Groups dos RDS
10. Rodar scripts SQL nos RDS
11. Criar ElastiCache Redis
12. Ajustar Security Group do Redis
13. Build/tag/push das 5 imagens para ECR
14. Criar manifests Kubernetes
15. Fazer deploy no EKS
16. Testar health checks e fluxo ponta a ponta
```
