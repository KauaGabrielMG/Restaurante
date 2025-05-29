# 🍽️ Sistema de Restaurante - AWS Serverless

Um sistema completo de gerenciamento de pedidos para restaurantes, desenvolvido com arquitetura serverless usando AWS Lambda, DynamoDB, SQS e S3, executando localmente com LocalStack.

## 🏗️ Arquitetura

```
API Gateway → Lambda (CriarPedido) → DynamoDB + SQS
                                         ↓
                              Lambda (ProcessarPedido) → S3
```

### Componentes:

- **API Gateway**: Endpoint REST para receber pedidos
- **Lambda CriarPedido**: Valida e salva pedidos no DynamoDB, envia para fila SQS
- **DynamoDB**: Armazena dados dos pedidos
- **SQS**: Fila para processamento assíncrono de pedidos
- **Lambda ProcessarPedido**: Processa pedidos, gera PDF e salva no S3
- **S3**: Armazena comprovantes em PDF dos pedidos processados

## 🚀 Pré-requisitos

- **Docker** e **Docker Compose**
- **Node.js** (versão 18+)
- **TypeScript** (`npm install -g typescript`)
- **AWS CLI Local** (`pip install awscli-local`)

## ⚙️ Configuração e Execução

### 1. Clone e navegue para o projeto

```bash
cd /mnt/c/Users/kaua/Desktop/faculdade/Restaurante
```

### 2. Execute o script de setup

```bash
chmod +x script.sh
./script.sh
```

O script irá:

- ✅ Iniciar LocalStack
- ✅ Instalar dependências TypeScript
- ✅ Compilar código TypeScript
- ✅ Criar recursos AWS (DynamoDB, SQS, S3)
- ✅ Fazer deploy das funções Lambda
- ✅ Configurar API Gateway
- ✅ Conectar SQS com Lambda

### 3. Teste o sistema

Após o deploy, você verá a URL do endpoint. Use curl ou Postman:

```bash
curl -X POST http://localhost:4566/restapis/{API_ID}/local/_user_request_/pedidos \
  -H "Content-Type: application/json" \
  -d '{
    "cliente": "João Silva",
    "mesa": 5,
    "itens": [
      {"nome": "Hambúrguer", "quantidade": 2, "preco": 25.90},
      {"nome": "Batata Frita", "quantidade": 1, "preco": 12.50}
    ]
  }'
```

## 📁 Estrutura do Projeto

```
Restaurante/
├── docker-compose.yml      # Configuração LocalStack
├── script.sh              # Script de deploy automatizado
├── criar-pedido.ts         # Lambda para criar pedidos
├── processar-pedido.ts     # Lambda para processar pedidos
├── gerarPDF.ts            # Função para gerar PDFs
├── package.json           # Dependências Node.js
├── tsconfig.json          # Configuração TypeScript
└── README.md              # Este arquivo
```

## 🔧 Funcionalidades

### ✨ Criação de Pedidos

- Validação completa de entrada
- Geração de ID único (UUID)
- Salvamento no DynamoDB
- Envio para fila de processamento
- Tratamento robusto de erros

### ⚡ Processamento Assíncrono

- Consumo automático da fila SQS
- Geração de comprovantes em PDF
- Upload para S3
- Atualização de status no DynamoDB
- Processamento em lote com controle de falhas

### 🛡️ Tratamento de Erros

- Validação de tipos TypeScript
- Try-catch em múltiplas camadas
- Logs detalhados para debugging
- Códigos de status HTTP apropriados
- Continuidade do processamento em caso de falhas parciais

## 📊 Monitoramento

### Verificar recursos criados:

```bash
# Listar tabelas DynamoDB
awslocal dynamodb list-tables

# Verificar filas SQS
awslocal sqs list-queues

# Listar buckets S3
awslocal s3 ls

# Verificar funções Lambda
awslocal lambda list-functions
```

### Verificar pedidos salvos:

```bash
awslocal dynamodb scan --table-name Pedidos
```

### Verificar arquivos no S3:

```bash
awslocal s3 ls s3://comprovantes/
```

## 🧪 Exemplo de Payload

```json
{
  "cliente": "Maria Santos",
  "mesa": 12,
  "itens": [
    {
      "nome": "Pizza Margherita",
      "quantidade": 1,
      "preco": 35.0
    },
    {
      "nome": "Refrigerante",
      "quantidade": 2,
      "preco": 5.5
    },
    {
      "nome": "Sobremesa",
      "quantidade": 1,
      "preco": 15.0
    }
  ]
}
```

## 🎯 Resposta de Sucesso

```json
{
  "sucesso": true,
  "mensagem": "Pedido criado com sucesso!",
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

## ❌ Tratamento de Erros

O sistema trata diversos tipos de erro:

- **400 Bad Request**: Dados inválidos ou incompletos
- **500 Internal Server Error**: Falhas de infraestrutura
- Logs detalhados para cada tipo de erro
- Mensagens de erro informativas para o cliente

## 🔄 Fluxo Completo

1. **Cliente** faz POST para `/pedidos`
2. **CriarPedido** valida dados e salva no DynamoDB
3. Pedido é enviado para **fila SQS**
4. **ProcessarPedido** consome a fila automaticamente
5. PDF é gerado e salvo no **S3**
6. Status é atualizado para "PROCESSADO" no **DynamoDB**

## 🛠️ Desenvolvimento

### Comandos úteis:

```bash
# Recompilar TypeScript
tsc

# Recriar e fazer deploy das Lambdas
./script.sh

# Parar LocalStack
docker compose down

# Ver logs do LocalStack
docker compose logs -f
```

## 📋 Próximas Melhorias

- [ ] Implementar autenticação JWT
- [ ] Adicionar testes unitários e de integração
- [ ] Implementar Dead Letter Queue (DLQ)
- [ ] Adicionar métricas e alertas
- [ ] Interface web para visualizar pedidos
- [ ] Integração com sistema de pagamento

## 📞 Suporte

Para dúvidas ou problemas:

1. Verifique se o Docker está rodando
2. Confirme se o LocalStack iniciou corretamente
3. Verifique os logs com `docker compose logs`
4. Certifique-se de que todas as dependências estão instaladas

---

_Projeto desenvolvido para fins acadêmicos - Faculdade_
