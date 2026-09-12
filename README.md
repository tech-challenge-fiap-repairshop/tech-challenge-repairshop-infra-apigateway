# 🚀 RepairShop — Infraestrutura do API Gateway (AWS HTTP API v2)

[![Terraform](https://img.shields.io/badge/Terraform-1.8.5+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS API Gateway](https://img.shields.io/badge/AWS-API%20Gateway%20v2-FF4F8B?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/api-gateway/)
[![AWS Lambda](https://img.shields.io/badge/AWS-Lambda%20Auth-FF9900?logo=awslambda&logoColor=white)](https://aws.amazon.com/lambda/)
[![Kubernetes EKS](https://img.shields.io/badge/AWS-EKS%20Backend-326CE5?logo=kubernetes&logoColor=white)](https://aws.amazon.com/eks/)
[![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)

Repositório de **Infraestrutura como Código (IaC)** responsável pelo provisionamento do **AWS API Gateway (HTTP API v2)** do ecossistema **RepairShop** (FIAP Tech Challenge — Fase 3).

O API Gateway atua como o **Ponto Único de Entrada (Single Entry Point / Edge Router)** da solução, gerenciando o tráfego externo e roteando de forma transparente entre o microsserviço de autenticação Serverless (AWS Lambda) e o backend principal executando no cluster Kubernetes (Amazon EKS).

---

## 🎯 Propósito e Estratégia Arquitetural

A infraestrutura utiliza o **AWS API Gateway v2 (HTTP API)** devido à sua altíssima vazão, suporte nativo a CORS, baixa latência e custo reduzido em relação às REST APIs clássicas:

1. **Roteamento Especializado de Autenticação (`POST /auth/login`):**
   - Rota integrada diretamente à função **AWS Lambda** (`repairshop-lambda-auth`).
   - Processa a validação de CPF e credenciais, emitindo o token JWT assinado.
2. **Roteamento de Backend via Proxy Transparente (`ANY /{proxy+}`):**
   - Rota catch-all que repassa transparentemente todo o tráfego da API de negócio (`/customers`, `/vehicles`, `/service-orders`, `/insumes`, `/invoices`, `/swagger-ui/*`) para o Load Balancer do EKS.
3. **Descoberta Dinâmica de Load Balancer (Zero Hardcoding):**
   - O Terraform utiliza um Data Source AWS (`data "aws_lb" "app_k8s"`) que busca em tempo real o DNS gerado pelo Network Load Balancer (NLB) do Kubernetes através da tag:
     ```text
     kubernetes.io/service-name = "repairshop/repairshop-service"
     ```
   - Elimina acoplamento com zonas DNS do Route 53 e evita que alterações no backend exijam modificações nos contratos do API Gateway.

---

## 🏗️ Topologia da Arquitetura do API Gateway

```mermaid
flowchart LR
    %% Definições de Estilo
    classDef clientStyle fill:#ECEFF1,stroke:#607D8B,stroke-width:2px,color:#263238
    classDef apigwStyle fill:#FCE4EC,stroke:#C2185B,stroke-width:2px,color:#880E4F
    classDef routeStyle fill:#EDE7F6,stroke:#512DA8,stroke-width:1.5px,color:#311B92
    classDef lambdaStyle fill:#FFF3E0,stroke:#E65100,stroke-width:2px,color:#BF360C
    classDef nlbStyle fill:#E1F5FE,stroke:#0288D1,stroke-width:2px,color:#01579B
    classDef eksStyle fill:#E8EAF6,stroke:#303F9F,stroke-width:2px,color:#1A237E

    Client["📱 Clientes / Web / Mobile\n(Internet Pública)"]:::clientStyle -->|"HTTPS (Porta 443)"| APIGW["🚪 AWS API Gateway HTTP v2\n(repairshop-api-gateway)"]:::apigwStyle
    
    subgraph Routes["🧭 Estratégia de Roteamento de Entrada"]
        direction TB
        AuthRoute["🔐 POST /auth/login\n(Autenticação Serverless)"]:::routeStyle
        ProxyRoute["🌐 ANY /{proxy+}\n(Catch-all Proxy Transparente)"]:::routeStyle
    end

    subgraph AWS_Compute["☁️ Camada de Computação e Execução (VPC Privada)"]
        Lambda["⚡ AWS Lambda Auth\n(Java 21 Clean Arch / JWT)"]:::lambdaStyle
        NLB["⚖️ AWS Network Load Balancer\n(Kubernetes Service / Porta 8080)"]:::nlbStyle
        EKSPods["☸️ EKS App Pods\n(Spring Boot / Swagger UI)"]:::eksStyle
    end

    APIGW --> AuthRoute -->|"AWS_PROXY Integration"| Lambda
    APIGW --> ProxyRoute -->|"HTTP_PROXY Integration"| NLB
    NLB --> EKSPods
```

---

## 🗂️ Estrutura de Arquivos

```text
.
├── .github/workflows/
│   ├── ci-cd-apigateway.yml  # Pipeline principal de CI/CD (Build, Test & Deploy)
│   └── destroy.yml           # Pipeline de destruição controlada com Safety Gate
├── main.tf                   # API Gateway v2, Rotas, Integrações e Data Source do LB
├── variables.tf              # Declaração das variáveis (ambiente, service_name, etc.)
├── outputs.tf                # Export da URL pública do API Gateway (`api_endpoint`)
├── providers.tf              # Configuração do provedor AWS
├── backend.tf                # Configuração do backend remoto S3
├── environments/
│   ├── dev.tfvars            # Parâmetros de Desenvolvimento
│   ├── hml.tfvars            # Parâmetros de Homologação
│   └── prd.tfvars            # Parâmetros de Produção
└── README.md
```

---

## 🚀 Pipeline de CI/CD (GitHub Actions)

A esteira de integração e entrega contínua do API Gateway é automatizada pelo workflow [`.github/workflows/ci-cd-apigateway.yml`](.github/workflows/ci-cd-apigateway.yml).

### Desenho da Pipeline CI/CD

```mermaid
flowchart TD
    classDef triggerStyle fill:#E1F5FE,stroke:#0288D1,stroke-width:2px,color:#01579B
    classDef stepStyle fill:#F3E5F5,stroke:#7B1FA2,stroke-width:2px,color:#4A148C
    classDef gateStyle fill:#FFF9C4,stroke:#FBC02D,stroke-width:2px,color:#F57F17
    classDef deployStyle fill:#E8F5E9,stroke:#388E3C,stroke-width:2px,color:#1B5E20
    classDef reportStyle fill:#ECEFF1,stroke:#455A64,stroke-width:2px,color:#263238

    A["🎯 Disparo / Trigger\n• Push ou PR (main, homolog, dev)\n• Workflow Dispatch Manual"]:::triggerStyle
    A --> B["⚙️ Autenticação AWS\n(Configure AWS Credentials / IAM LabRole)"]:::stepStyle
    B --> C["📦 Garantia do Bucket S3\n(Verifica/Cria fiap-repairshop2)"]:::stepStyle
    C --> D["⚡ Setup & Terraform Init\n(S3: terraform-config/apigateway-tfstate/${ENV})"]:::stepStyle
    D --> E["📝 Geração do Plano\n(terraform plan -var-file=environments/${ENV}.tfvars)"]:::stepStyle
    E --> F{"🌿 Branch é 'main' com Push\nou Dispatch Manual?"}:::gateStyle
    
    F -- "✅ Sim (Deploy Aprovado)" --> G["🚀 Terraform Apply\n(terraform apply -auto-approve)"]:::deployStyle
    F -- "🛡️ Não (PR ou Homologação)" --> H["📋 Modo Dry-Run / Plan Only\n(Validação de Rotas e Integrações)"]:::reportStyle
    
    G --> I["📊 GitHub Step Summary\n(Exporta URL Pública do API Gateway)"]:::reportStyle
    H --> I
```

### Detalhamento e Justificativa de Cada Passo da Pipeline

| Passo | Ação Executada | Justificativa Arquitetural |
| :--- | :--- | :--- |
| **1. Checkout repository** | Obtém o código na versão do commit. | Garante a integridade da versão dos manifests Terraform a serem aplicados. |
| **2. Configure AWS Credentials** | Autentica via IAM Secrets (`LabRole`). | Sessão segura com a AWS sem chaves estáticas gravadas no repositório. |
| **3. Ensure S3 Bucket State** | Valida a existência do bucket `fiap-repairshop2`. | Previne quebras durante a inicialização do backend remoto S3. |
| **4. Setup Terraform** | Configura a versão fixa `1.8.5` da CLI Terraform. | Reprodutibilidade e previsibilidade da infraestrutura como código. |
| **5. Terraform Init** | Inicializa os plugins e conecta ao state do API Gateway. | Garante o isolamento estrito de estado em relação aos clusters e bancos de dados. |
| **6. Terraform Plan** | Gera o plano de execução para o ambiente selecionado. | Valida se a integração com a Lambda e o Load Balancer descoberto estão corretos. |
| **7. Terraform Apply** | Aplica as configurações do API Gateway na AWS. | Deploy automatizado apenas para commits aprovados na branch `main` ou disparo manual. |
| **8. Generate Summary** | Publica os outputs (incluindo URL do Gateway) no `$GITHUB_STEP_SUMMARY`. | Dá visibilidade instantânea do endpoint público gerado para testes imediatos. |

### 💡 Decisão de Arquitetura: Estratégia de Único Job (Single Job)

> **Decisão Arquitetural:** Toda a pipeline do API Gateway roda em um **único JOB (`runs-on: ubuntu-latest`)**.
> 
> **Motivação Técnica:**
> 1. **Economia de Minutos de Execução:** Como o API Gateway provisiona recursos leves e rápidos (tempo médio de 1 a 2 minutos), dividir o pipeline em múltiplos jobs adicionaria tempo de fila para novos runners, consumindo desnecessariamente o limite da conta GitHub.
> 2. **Reaproveitamento de Estado e Contexto AWS:** Mantém as credenciais e conexões do Terraform inicializadas no runner, otimizando o tempo de feedback para o desenvolvedor.

---

### 🔐 Secrets do GitHub Actions (AWS Academy & Deploy)

Para que a pipeline de CI/CD execute o provisionamento do API Gateway HTTP v2 via Terraform, o repositório requer as seguintes **Actions Secrets** (*Settings > Secrets and variables > Actions*):

> [!TIP]
> Em contas da **AWS Academy**, as credenciais são temporárias (sessões de 3 a 4 horas). Por essa razão, a inclusão do `AWS_SESSION_TOKEN` é mandatória para autenticação da role `LabRole` e prevenção de falhas de `ExpiredToken`.

| Secret | Obrigatório | Descrição |
| :--- | :---: | :--- |
| `AWS_ACCESS_KEY_ID` | **Sim** | Chave de acesso temporária fornecida no console do AWS Academy. |
| `AWS_SECRET_ACCESS_KEY` | **Sim** | Chave secreta de acesso correspondente. |
| `AWS_SESSION_TOKEN` | **Sim** | Token da sessão temporária (necessário para o `LabRole`). |

💡 *Dica de Automação:* Utilize o script [`update_aws_secrets.ps1`](https://github.com/tech-challenge-fiap-repairshop/tech-challenge-wiki-docs/blob/main/update_aws_secrets.ps1) disponível no repositório `tech-challenge-wiki-docs` para atualizar essas credenciais em todos os 7 repositórios da organização simultaneamente via GitHub CLI.

---

### 🌐 Variáveis de Ambiente e Terraform Inputs

| Variável / Parâmetro | Origem / Localização | Valor Padrão | Descrição |
| :--- | :--- | :--- | :--- |
| `AWS_REGION` | Pipeline `env` / Terraform | `us-east-1` | Região da AWS para deploy do API Gateway. |
| `S3_TFSTATE_BUCKET` | Backend S3 / Workflow | `fiap-repairshop2` | Bucket S3 para o estado remoto `terraform-config/apigateway-tfstate/${ENV}`. |
| `USE_DYNAMIC_LB_LOOKUP` | `environments/*.tfvars` | `true` | Habilita busca dinâmica via tag do Load Balancer (NLB) do EKS. |
| `APP_LB_URL` | `environments/*.tfvars` | `""` | URL estática de fallback caso o lookup dinâmico esteja desabilitado. |

---

## 🔀 Governança de Branches e Ciclo de Promoção (Git Flow)

A governança do repositório segue isolamento estrito com aprovação controlada para promoção de ambientes:

```mermaid
flowchart LR
    classDef branchDev fill:#E3F2FD,stroke:#1E88E5,stroke-width:2px,color:#0D47A1
    classDef branchHml fill:#FFF3E0,stroke:#FB8C00,stroke-width:2px,color:#E65100
    classDef branchMain fill:#E8F5E9,stroke:#43A047,stroke-width:2px,color:#1B5E20
    classDef gateStyle fill:#FFEBEE,stroke:#E53935,stroke-width:2px,color:#B71C1C

    Dev["🌿 Feature / Fix / Chore\n(feat/*, fix/*, chore/*)"]:::branchDev
    PR_HML{"Pull Request\npara homolog"}:::gateStyle
    HML["🛡️ Branch homolog\n(Ambiente hml / Validação)"]:::branchHml
    PR_MAIN{"Pull Request\npara main"}:::gateStyle
    Main["🚀 Branch main\n(Deploy em Produção)"]:::branchMain

    Dev -->|"Abertura de PR"| PR_HML
    PR_HML -->|"Validação & Merge"| HML
    HML -->|"Abertura de PR de Promoção"| PR_MAIN
    PR_MAIN -->|"Aprovação Manual Obrigatória"| Main
```

> ⚠️ **Regra de Governança:** É expressamente proibido commit ou push direto na branch `main`. Toda alteração deve passar pelo pipeline de validação e aprovação formal.

---

## 💻 Execução e Deploy Local (Terraform CLI)

Caso deseje executar o provisionamento localmente:

```bash
# 1. Inicialize o Terraform com o backend remoto S3
terraform init \
  -backend-config="bucket=fiap-repairshop2" \
  -backend-config="key=terraform-config/apigateway-tfstate/dev/terraform.tfstate" \
  -backend-config="region=us-east-1"

# 2. Visualize o plano de execução
terraform plan -var-file="environments/dev.tfvars"

# 3. Aplique as modificações na AWS
terraform apply -var-file="environments/dev.tfvars"
```

---

## 🔗 Links e Integrações no Ecossistema

- **Swagger UI / OpenAPI 3.0:** Acessível via API Gateway em: `https://<api-gateway-id>.execute-api.us-east-1.amazonaws.com/swagger-ui/index.html`
- **Coleção Postman:** [`tech-challenge-repairshop-app/docs/postman/`](file:///c:/Users/Alexandre-AGAMIN/Projetos-%20FIAP/github-organizations-projects/tech-challenge-repairshop-app/docs/postman/)
- **Repositórios Integrados:**
  - [`tech-challenge-repairshop-lambda-auth`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-lambda-auth) (Destino da rota `POST /auth/login`)
  - [`tech-challenge-repairshop-app`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-app) (Destino da rota `ANY /{proxy+}`)
  - [`tech-challenge-repairshop-infra-eks`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-eks) (Cluster Kubernetes onde o Load Balancer reside)
  - [`tech-challenge-repairshop-infra-network`](https://github.com/fiap-postech-repairshop/tech-challenge-repairshop-infra-network) (Rede Base)
