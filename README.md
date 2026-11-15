# 🚪🌐 Repair Shop — Infra API Gateway (`infra-apigateway`)

[![CI/CD Pipeline](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-apigateway/actions/workflows/ci-cd-apigateway.yml/badge.svg)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-apigateway/actions/workflows/ci-cd-apigateway.yml)
[![Terraform](https://img.shields.io/badge/Terraform-1.8.5-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS API Gateway v2](https://img.shields.io/badge/Amazon-API%20Gateway%20(HTTP%20API%20v2)-FF4F8B?logo=amazonapigateway&logoColor=white)](https://aws.amazon.com/api-gateway/)

Repositório de **Infraestrutura como Código (Terraform)** que provisiona o **Single Entry Point** da plataforma **Repair Shop (Tech Challenge FIAP — 15SOAT)** usando **Amazon API Gateway (HTTP API v2)**. Centraliza e roteia todo o tráfego externo para o **AWS Lambda Auth** e dinamicamente para os **Network Load Balancers (NLBs)** dos 4 microsserviços no **Amazon EKS**, padronizando **CORS** e preservando a propagação de traces OpenTelemetry (`traceparent`, `tracestate`).

---

## 📋 Índice

- [Mapa de Rotas e Descoberta Dinâmica de NLBs](#mapa-de-rotas-e-descoberta-dinâmica-de-nlbs)
- [Arquitetura Atual — Motivação e Benefícios dos Componentes](#arquitetura-atual--motivação-e-benefícios-dos-componentes)
- [Por que DynamoDB em vez de Banco Relacional atrás do Gateway?](#por-que-dynamodb-em-vez-de-banco-relacional-atrás-do-gateway)
- [Como Executar e Validar Localmente (Terraform)](#como-executar-e-validar-localmente-terraform)
- [Como Executar em Produção (Esteira CI/CD GitHub Actions)](#como-executar-em-produção-esteira-cicd-github-actions)
- [Documentação Técnica e Collection do Postman](#documentação-técnica-e-collection-do-postman)

---

## Mapa de Rotas e Descoberta Dinâmica de NLBs

Conforme definido em [`main.tf`](main.tf), a API `repairshop-apigw-${var.environment}` utiliza stage **`$default`** com **`auto_deploy = true`** e CORS configurando os headers OpenTelemetry **`traceparent`** e **`tracestate`**:

### Roteamento Multi-Destino (Lambda + 4 Microsserviços EKS)

| Contexto / Destino | Tipo de Integração | Rotas Expostas no API Gateway |
| :--- | :--- | :--- |
| **`lambda-auth`** (`repairshop-lambda-auth-{env}`) | `AWS_PROXY` (Payload v2.0) | `POST /auth/login` |
| **`app-register-service`** *(NLB EKS)* | `HTTP_PROXY` | `POST /auth/register`, `ANY /customers`, `ANY /customers/{proxy+}`, `ANY /vehicles`, `ANY /vehicles/{proxy+}` |
| **`app-service-order-execution-service`** *(NLB EKS)* | `HTTP_PROXY` | `ANY /service-orders`, `ANY /service-orders/{proxy+}`, `POST /execute_task/{proxy+}`, `POST /increment_execution_task/{proxy+}` |
| **`app-payment-service`** *(NLB EKS)* | `HTTP_PROXY` | `ANY /payment/{proxy+}`, `ANY /payments`, `ANY /payments/{proxy+}` |
| **`app-notification-service`** *(NLB EKS)* | `HTTP_PROXY` | `ANY /notifications`, `ANY /notifications/{proxy+}` |

> **Zero IPs Hardcoded**: O Terraform utiliza `data "aws_lbs" "services"` buscando pela tag `"kubernetes.io/service-name" = "${var.k8s_namespace}/${each.value}"` para descobrir automaticamente os DNS dos Network Load Balancers criados pelo EKS para os 4 microsserviços.

---

## Arquitetura Atual — Motivação e Benefícios dos Componentes

| Pilar / Tecnologia | Papel no Ecossistema | Motivação Técnica e Pontos Positivos |
| :--- | :--- | :--- |
| **RDS (PostgreSQL 16)** | Persistência relacional cadastral ([`infra-db-rds`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-rds)) | Protegido atrás do `register-service` em sub-rede privada, assegurando integridade referencial (`ACID`, FK, `UNIQUE`) nas rotas `/customers`, `/vehicles` e `/auth/register`. |
| **DynamoDB (NoSQL)** | Persistência de OS e Pagamentos ([`infra-db-dynamo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-db-dynamo)) | Sustenta alta concorrência nas rotas `/service-orders`, `/execute_task`, `/payments` e webhooks externos com escala `PAY_PER_REQUEST`, Single-Table Design e GSIs rápidos. |
| **ElastiCache (Redis 7.0)** | Cache em memória ([`infra-redis`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-redis)) | Disponível em sub-rede privada (`6379`) para o `register-service`, preparando cache distribuído sub-milissegundo após o login para aliviar leituras repetitivas no RDS. |
| **Apps (Lambda Auth + EKS)** | **Destinos diretos deste Gateway** ([`lambda-auth`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-lambda-auth) + [`infra-eks`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-eks)) | Combina autenticação serverless com elasticidade instantânea (`POST /auth/login`) com microsserviços especializados rodando no **EKS 1.31** sob HPA. |
| **Amazon SQS (Mensageria + DLQ)** | Coreografia assíncrona nos bastidores ([`infra-sqs`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-infra-sqs)) | Mantém respostas HTTP do Gateway rápidas e desacopladas ao delegar aprovações, notificações e confirmações de pagamento para 5 filas + 5 DLQs em Saga Coreografada. |
| **API Gateway (HTTP API v2)** | **Camada provisionada por este repositório** | Substitui o REST API v1 entregando menor custo e menor latência de proxy, oculta a topologia interna privada (VPC), unifica políticas de CORS e preserva o contexto de trace W3C logo na borda pública. |
| **Observabilidade (Grafana)** | OpenTelemetry + Prometheus + Loki + Jaeger + Grafana | A permissão explícita de `traceparent` e `tracestate` no CORS permite correlação de traces desde o cliente HTTP passando pelo Gateway e Lambda até os pods e filas SQS, visualizados nos 11 dashboards Grafana. |

---

## Por que DynamoDB em vez de Banco Relacional atrás do Gateway?

Embora o Gateway roteie tanto para domínios relacionais (`/customers`, `/vehicles`) quanto para domínios NoSQL (`/service-orders`, `/payments`), a separação no backend é estratégica:

1. **Absorção elástica de picos vindos do Gateway sem esgotar conexões**: Webhooks do Mercado Pago (`/payments/webhook`) e chamadas de atualização de execução de OS escalam pods no EKS via HPA. Um RDS centralizado (`db.t3.micro`) sofreria exaustão de pool JDBC sob rajadas; o DynamoDB opera via HTTPS *stateless* com capacidade automática `PAY_PER_REQUEST`.
2. **Leitura consolidada de agregados em único salto**: Chamadas `GET /service-orders/{id}` e `GET /payment/{serviceOrderId}` leem toda a partição `ORDER#<id>` ou `BILLING#<id>` (metadados, histórico de 12 estados, execuções, faturas) sem `JOIN`s custosos.
3. **Evolução sem bloqueios + despacho assíncrono via GSIs**: Atributos de gateway e contingência evoluem sem *locks* de `ALTER TABLE`, enquanto `TransactWriteItems` garante atomicidade e os GSIs aceleram o despacho para SQS.

---

## Como Executar e Validar Localmente (Terraform)

> **Pré-requisitos**: **Terraform `1.8.5`**, **AWS CLI v2** autenticado e os **4 microsserviços já implantados no EKS** (pois `main.tf` consulta os NLBs existentes na AWS via `data "aws_lbs"`).

```bash
# Na raiz do repositório (main.tf fica no diretório raiz)
terraform init \
  -backend-config="bucket=SEU_BUCKET_TERRAFORM_STATE" \
  -backend-config="key=terraform-config/apigateway-tfstate/dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform fmt -check -recursive
terraform validate
terraform plan -var-file="environments/dev.tfvars"
```

Para validar sintaxe HCL localmente sem acessar a AWS:
```bash
terraform init -backend=false
terraform validate
```

---

## Como Executar em Produção (Esteira CI/CD GitHub Actions)

Definida em [`.github/workflows/ci-cd-apigateway.yml`](.github/workflows/ci-cd-apigateway.yml) e destruição controlada em [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml).

### Gatilho e Fluxo da Esteira
- **Gatilho**: `push` e `pull_request` na branch **`main`** (quando há alteração em `*.tf`, `environments/**` ou `.github/workflows/ci-cd-apigateway.yml`).
- **State Remoto S3**: `terraform-config/apigateway-tfstate/${ENV}/terraform.tfstate` no bucket `AWS_TERRAFORM_STATE_BUCKET`.
- **Etapas**: `terraform fmt -check` -> `terraform init` -> `terraform validate` -> `terraform plan` -> `terraform apply -auto-approve` (no push em `main`).

> **Posição na Ordem Oficial de Provisionamento**: Este repositório deve ser **o último a ser provisionado** (5º estágio), **após** o deploy dos 4 microsserviços no EKS e do `lambda-auth`, permitindo que o `data "aws_lbs"` localize todos os Load Balancers ativos.

---

## Documentação Técnica e Collection do Postman

- **Arquivos Terraform deste Repositório**: [`main.tf`](main.tf) | [`environments/dev.tfvars`](environments/dev.tfvars) | [`environments/hml.tfvars`](environments/hml.tfvars) | [`environments/prd.tfvars`](environments/prd.tfvars)
- **ADRs, RFCs e Diagramas**:
  - [ADRs (`ADR-001` a `ADR-013`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/ADRs/README.md)
  - [RFCs (`RFC-001` a `RFC-014`)](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/RFCs/README.md)
  - [`Diagrama de Infraestrutura Cloud`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/delivery/infrastructure/repairshop-diagrama-infra-cloud.svg)
  - [`Diagrama de Sequência — Auth e Abertura de OS`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/delivery/sequence/diagrama_sequencia_auth_abertura_os.drawio.png)
- **Postman Collections & Environments (Organização)**:
  - Collection Principal: [`Repair Shop (Tech Challenge FIAP)`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Repair%20Shop%20%28Tech%20Challenge%20FIAP%29.postman_collection.json)
  - Collection Completa: [`Tech Challenge FIAP - Completo`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Tech_Challenge_Fiap_-_Completo.postman_collection.json)
  - Environment Local: [`Local.postman_environment.json`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/Local.postman_environment.json)
  - Guia do Postman: [`docs/postman/README.md`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/blob/main/docs/postman/README.md)
- **Dashboards Grafana (11 JSONs)**: [`dashboards/`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-repairshop-app-service-order-execution-service/tree/main/local/observability/grafana/dashboards)
