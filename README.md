# 🚀 RepairShop - Infraestrutura do API Gateway

Este repositório contém a infraestrutura como código (IaC) utilizando **Terraform** para o provisionamento do **AWS API Gateway** do projeto RepairShop.

O API Gateway atua como a porta de entrada (Ponto Único de Contato) para os clientes da aplicação, roteando o tráfego de forma inteligente e segura entre a Lambda de Autenticação e o Backend Principal.

---

## 🏗️ Arquitetura e Estratégia de Roteamento

A infraestrutura utiliza o **AWS API Gateway V2 (HTTP API)**, que oferece alta performance e menor custo. Ele está configurado com uma arquitetura híbrida de **Proxy Transparente**:

1. **Autenticação (Lambda)**: 
   - Rota: `POST /auth/login`
   - Integração: Roteada diretamente para o AWS Lambda (`repairshop-lambda-auth`).
2. **Backend Principal (EKS / Spring Boot)**:
   - Rota: `ANY /{proxy+}` (Proxy Catch-all)
   - Integração: Repassa de forma transparente qualquer outra requisição HTTP para o Load Balancer do cluster EKS.

---

## 🔍 Busca Dinâmica do Load Balancer (Data Source AWS)

Alinhado às melhores práticas de mercado, o Terraform descobre o DNS do Load Balancer na AWS em tempo de execução **sem depender do Route 53 e sem hardcode**:

- Quando o Kubernetes aplica o manifesto [`k8s/service.yaml`](file:///c:/Users/Alexandre-AGAMIN/Projetos-%20FIAP/github-organizations-projects/tech-challenge-repairshop-app/k8s/service.yaml) (do repositório `tech-challenge-repairshop-app`), a AWS injeta a tag:
  ```text
  kubernetes.io/service-name = "repairshop/repairshop-service"
  ```
- O Terraform localiza o Load Balancer por essa tag (`data "aws_lb" "app_k8s"`) e extrai dinamicamente o DNS gerado pela AWS.

### 🌟 Vantagem: Roteamento Dinâmico (Pass-Through Proxy)
Como o API Gateway utiliza a rota coringa (`/{proxy+}`), **os contratos (Swagger/OpenAPI) e endpoints são gerenciados exclusivamente pela aplicação Spring Boot**. 

Isso significa que:
- **Você NÃO precisa** alterar ou fazer deploy neste projeto Terraform sempre que um novo endpoint for criado no backend.
- A validação de payloads e a documentação (`/v3/api-docs`) continuam centralizadas e servidas nativamente pela aplicação.

---

## 📂 Estrutura do Projeto

Os arquivos Terraform estão na **raiz** do repositório para facilitar a integração com a esteira de CI/CD:

```text
/
├── main.tf                 # API Gateway, Integrações, Rotas e Data Source do LB
├── providers.tf            # Configuração do provedor AWS
├── variables.tf            # Declaração das variáveis (namespace, service_name, etc.)
├── outputs.tf              # Saídas como a URL final do API Gateway
├── backend.tf              # Configuração do estado remoto no S3 (injetado via CI/CD)
├── environments/           # Arquivos de variáveis específicos por ambiente
│   ├── dev.tfvars
│   ├── hml.tfvars
│   └── prd.tfvars
└── .github/workflows/      # Pipeline de CI/CD via GitHub Actions
```

---

## ⚙️ Pipeline CI/CD (GitHub Actions)

O deploy é totalmente automatizado através do GitHub Actions (`ci-cd-apigateway.yml`).

- **Gatilhos**: 
  - Automático ao fazer `push` ou `pull_request` na branch `main`.
  - Manual via **Workflow Dispatch** (permitindo selecionar o ambiente desejado).
- **Processo**:
  1. Configura as credenciais da AWS.
  2. Garante a existência do Bucket S3 (`fiap-repairshop2`) para armazenar o estado do Terraform de forma segura.
  3. Executa o `terraform init` parametrizando dinamicamente a chave do estado (ex: `terraform-config/apigateway-tfstate/prd/terraform.tfstate`).
  4. Roda o `terraform plan` para exibir as alterações planejadas.
  5. Roda o `terraform apply` (apenas em `push` na `main` ou disparo manual).

---

## 🛠️ Como testar localmente (Terraform CLI)

Caso precise rodar o projeto localmente para validações:

```bash
# 1. Inicializar o Terraform
terraform init -backend-config="bucket=fiap-repairshop2" -backend-config="key=terraform-config/apigateway-tfstate/dev/terraform.tfstate" -backend-config="region=us-east-1"

# 2. Visualizar o plano de execução
terraform plan -var-file="environments/dev.tfvars"

# 3. Aplicar as mudanças na AWS
terraform apply -var-file="environments/dev.tfvars"
```
