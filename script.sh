#!/bin/bash

set -e

# Função para tratamento de erros
handle_error() {
    echo "❌ Erro na linha $1: $2"
    echo "🧹 Limpando recursos criados parcialmente..."
    # cleanup_on_error
    exit 1
}

# # Função para limpeza em caso de erro
# cleanup_on_error() {
#     echo "🧼 Removendo artefatos criados..."
#     rm -f criarPedido.zip processarPedido.zip
#     rm -f criar-pedido.js processar-pedido.js gerarPDF.js

#     if [ ! -z "$LOCALSTACK_ENDPOINT" ]; then
#         echo "🗑️ Tentando remover recursos AWS criados..."
#         aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb delete-table --table-name Pedidos 2>/dev/null || true
#         aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs delete-queue --queue-url "http://$ETH0_IP:4566/000000000000/fila-pedidos" 2>/dev/null || true
#         aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 rb s3://comprovantes --force 2>/dev/null || true
#         aws --endpoint-url=$LOCALSTACK_ENDPOINT sns delete-topic --topic-arn "arn:aws:sns:us-east-1:000000000000:PedidosConcluidos" 2>/dev/null || true
#         if [ ! -z "$API_ID" ]; then
#             aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null || true
#         fi
#     fi
# }

# # Configurar trap para capturar erros
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "🚀 Iniciando deploy do Sistema de Restaurante..."

# Verificar se o LocalStack está rodando
echo "🔍 Verificando se o LocalStack está rodando..."
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

echo "📦 Instalando dependências..."
if ! npm install; then
    echo "❌ Falha ao instalar dependências npm"
    exit 1
fi

# Obter IP da interface eth0
echo "🌐 Obtendo IP da interface de rede..."

# Função para obter IP da máquina
get_machine_ip() {
    local ip=""

    # Tentar eth0 primeiro
    ip=$(ip addr show eth0 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
    if [ ! -z "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
        return 0
    fi

    # Tentar outras interfaces comuns
    for interface in eth0 eth1 enp0s3 enp0s8 wlan0 wlp2s0; do
        ip=$(ip addr show $interface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
        if [ ! -z "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    # Tentar usando hostname -I
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ ! -z "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
        return 0
    fi

    # Tentar usando route para encontrar IP da interface padrão
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)
    if [ ! -z "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
        return 0
    fi

    return 1
}

ETH0_IP=$(get_machine_ip)

if [ -z "$ETH0_IP" ]; then
    echo "❌ Não foi possível obter o IP da máquina"
    echo "💡 Usando localhost como fallback..."
    ETH0_IP="127.0.0.1"
    echo "⚠️  Aviso: Usando localhost pode causar problemas de conectividade"
else
    echo "✅ IP da máquina encontrado: $ETH0_IP"
fi

echo "🌐 Usando IP da eth0: $ETH0_IP"
LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"
echo "LocalStack Endpoint: $LOCALSTACK_ENDPOINT"

echo "🧼 Limpando artefatos anteriores..."
rm -f criarPedido.zip processarPedido.zip

echo "📦 Compilando arquivos Lambda individuais..."
tsc criar-pedido.ts processar-pedido.ts gerarPDF.ts
if [ $? -ne 0 ]; then
  echo "❌ Erro na compilação do TypeScript. Verifique os arquivos .ts."
  exit 1
fi

echo "📦 Empacotando funções Lambda..."

# Criar diretório temporário para bundle otimizado
echo "  📦 Criando bundle otimizado (apenas dependências de runtime)..."
mkdir -p lambda-bundle/node_modules

# Instalar apenas dependências de produção no diretório temporário
cd lambda-bundle
npm init -y > /dev/null 2>&1

# Copiar configuração otimizada
cp ../.npmrc-lambda .npmrc

# Instalar dependências otimizadas (apenas runtime, sem dev dependencies)
npm install --production --no-optional --no-audit --no-fund \
  @aws-sdk/client-dynamodb@^3.600.0 \
  @aws-sdk/lib-dynamodb@^3.600.0 \
  @aws-sdk/client-sqs@^3.600.0 \
  @aws-sdk/client-s3@^3.600.0 \
  @aws-sdk/client-sns@^3.600.0 \
  jspdf@^3.0.1 \
  uuid@^9.0.0 > /dev/null 2>&1

# Remover arquivos desnecessários para reduzir ainda mais o tamanho
echo "    🧹 Removendo arquivos desnecessários..."
find node_modules -name "*.d.ts" -delete
find node_modules -name "*.ts" -delete
find node_modules -name "*.md" -delete
find node_modules -name "LICENSE*" -delete
find node_modules -name "CHANGELOG*" -delete
find node_modules -name "*.map" -delete
find node_modules -name "test" -type d -exec rm -rf {} + 2>/dev/null || true
find node_modules -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true
find node_modules -name "docs" -type d -exec rm -rf {} + 2>/dev/null || true
find node_modules -name "examples" -type d -exec rm -rf {} + 2>/dev/null || true

cd ..

# Copiar arquivos JS compilados para o bundle
cp criar-pedido.js lambda-bundle/
cp processar-pedido.js lambda-bundle/
cp gerarPDF.js lambda-bundle/

# Criar ZIPs otimizados
echo "  🗜️ Compactando Lambda CriarPedido (otimizado)..."
cd lambda-bundle
zip -r ../criarPedido.zip criar-pedido.js node_modules/ > /dev/null
cd ..

echo "  🗜️ Compactando Lambda ProcessarPedido (otimizado)..."
cd lambda-bundle
zip -r ../processarPedido.zip processar-pedido.js gerarPDF.js node_modules/ > /dev/null
cd ..

# Limpar diretório temporário | Vou comentar essa linha para manter os bundles
#** rm -rf lambda-bundle

# Verificar tamanho dos ZIPs
CRIAR_SIZE=$(du -h criarPedido.zip | cut -f1)
PROCESSAR_SIZE=$(du -h processarPedido.zip | cut -f1)

echo "  ✅ CriarPedido.zip: $CRIAR_SIZE"
echo "  ✅ ProcessarPedido.zip: $PROCESSAR_SIZE"
echo "✅ Lambdas empacotadas com dependências otimizadas!"

echo "🔧 Criando recursos AWS no LocalStack..."

# Criar role IAM para Lambda primeiro
echo "  👤 Criando role IAM para Lambda..."

# Trust policy para Lambda
TRUST_POLICY=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)

aws --endpoint-url=$LOCALSTACK_ENDPOINT iam create-role \
  --role-name lambda-role \
  --assume-role-policy-document "$TRUST_POLICY" > /dev/null 2>&1 || true

# Policy para SNS e DynamoDB
LAMBDA_POLICY=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "sns:GetTopicAttributes",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)

aws --endpoint-url=$LOCALSTACK_ENDPOINT iam create-policy \
  --policy-name lambda-execution-policy \
  --policy-document "$LAMBDA_POLICY" > /dev/null 2>&1 || true

aws --endpoint-url=$LOCALSTACK_ENDPOINT iam attach-role-policy \
  --role-name lambda-role \
  --policy-arn arn:aws:iam::000000000000:policy/lambda-execution-policy > /dev/null 2>&1 || true

# Aguardar role estar disponível
sleep 2
# Criação da tabela DynamoDB
echo "  📋 Criando tabela DynamoDB: Pedidos"
aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
	--billing-mode PAY_PER_REQUEST \
	--region us-east-1 > /dev/null 2>&1 || true

# Criação da fila SQS
echo "  📬 Criando fila SQS: fila-pedidos"
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue --queue-name fila-pedidos > /dev/null 2>&1 || true

# Criação do bucket S3
echo "  🗃️ Criando bucket S3: comprovantes"
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://comprovantes > /dev/null 2>&1 || true

# Criação do tópico SNS
echo "  📧 Criando tópico SNS: PedidosConcluidos"
aws --endpoint-url=$LOCALSTACK_ENDPOINT sns create-topic \
  --name PedidosConcluidos \
  --region us-east-1 > /dev/null 2>&1 || true

echo "🚀 Criando funções Lambda..."
echo "  🔧 Criando função CriarPedido"
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name CriarPedido \
  --runtime nodejs18.x \
  --handler criar-pedido.handler \
  --timeout 10 \
  --zip-file fileb://criarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role > /dev/null 2>&1 || true

echo "  🔧 Criando função ProcessarPedido"
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name ProcessarPedido \
  --runtime nodejs18.x \
  --handler processar-pedido.handler \
  --timeout 10 \
  --zip-file fileb://processarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role > /dev/null 2>&1 || true

echo "🌐 Criando API Gateway e integrando com Lambda CriarPedido..."

# API
API_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-rest-api \
  --name "RestauranteAPI" \
  --query 'id' \
  --output text)

ROOT_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[0].id' \
  --output text)

PEDIDO_RESOURCE_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part pedidos \
  --query 'id' \
  --output text)

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --authorization-type "NONE" > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:CriarPedido/invocations > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda add-permission \
  --function-name CriarPedido \
  --statement-id apigateway-test-permission \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/pedidos" > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name local > /dev/null 2>&1

echo "🔗 Conectando SQS com Lambda ProcessarPedido..."

QUEUE_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-url --queue-name fila-pedidos --query 'QueueUrl' --output text)
QUEUE_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-name QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-event-source-mapping \
  --function-name ProcessarPedido \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  --enabled > /dev/null 2>&1 || true

echo "✅ Deploy concluído com sucesso!"
echo ""
echo "🌐 Endpoints disponíveis:"
echo "  📝 API Gateway: http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos"
echo "  📊 DynamoDB: Tabela 'Pedidos' criada"
echo "  📬 SQS: Fila 'fila-pedidos' criada"
echo "  🗃️ S3: Bucket 'comprovantes' criado"
echo "  📧 SNS: Tópico 'PedidosConcluidos' criado"
echo ""
echo "🧪 Para testar, execute:"
echo 'curl -X POST http://'$ETH0_IP':4566/restapis/'$API_ID'/local/_user_request_/pedidos \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{\"cliente\":\"João\",\"itens\":[{\"nome\":\"Pizza\",\"quantidade\":1,\"preco\":25.99}],\"mesa\":5}"'
