#!/bin/bash

set -e

echo "🚀 Deploy Simplificado do Sistema de Restaurante (sem IAM complexo)..."

# Verificar se o LocalStack está rodando
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

# Obter IP da máquina
ETH0_IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ETH0_IP" ]; then
    ETH0_IP="127.0.0.1"
fi

LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"
echo "🌐 Endpoint: $LOCALSTACK_ENDPOINT"

echo "📦 Instalando dependências..."
npm install

echo "🧼 Limpeza..."
rm -f *.js *.zip

echo "📦 Compilando TypeScript..."
tsc criar-pedido.ts processar-pedido.ts gerarPDF.ts

echo "📦 Criando ZIPs..."
zip -r criarPedido.zip criar-pedido.js node_modules/ > /dev/null
zip -r processarPedido.zip processar-pedido.js gerarPDF.js node_modules/ > /dev/null

echo "🔧 Criando recursos AWS..."

# DynamoDB
aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1 > /dev/null 2>&1 || true

# SQS
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue \
  --queue-name fila-pedidos > /dev/null 2>&1 || true

# S3
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://comprovantes > /dev/null 2>&1 || true

# SNS
aws --endpoint-url=$LOCALSTACK_ENDPOINT sns create-topic \
  --name PedidosConcluidos \
  --region us-east-1 > /dev/null 2>&1 || true

echo "🚀 Criando Lambdas..."

# Lambda CriarPedido
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name CriarPedido \
  --runtime nodejs18.x \
  --handler criar-pedido.handler \
  --zip-file fileb://criarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 30 > /dev/null 2>&1 || {
    echo "⚠️ Atualizando função existente..."
    aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda update-function-code \
      --function-name CriarPedido \
      --zip-file fileb://criarPedido.zip > /dev/null
}

# Lambda ProcessarPedido
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name ProcessarPedido \
  --runtime nodejs18.x \
  --handler processar-pedido.handler \
  --zip-file fileb://processarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --timeout 60 > /dev/null 2>&1 || {
    echo "⚠️ Atualizando função existente..."
    aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda update-function-code \
      --function-name ProcessarPedido \
      --zip-file fileb://processarPedido.zip > /dev/null
}

echo "🌐 Configurando API Gateway..."

# Criar API
API_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-rest-api \
  --name "RestauranteAPI" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-rest-apis \
  --query 'items[0].id' --output text)

ROOT_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[0].id' \
  --output text)

# Criar resource /pedidos
PEDIDO_RESOURCE_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part pedidos \
  --query 'id' \
  --output text 2>/dev/null || \
  aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[?pathPart==`pedidos`].id' --output text)

# Configurar método POST
aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --authorization-type "NONE" > /dev/null 2>&1 || true

# Integração com Lambda
aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:CriarPedido/invocations > /dev/null 2>&1

# Deploy da API
aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name local > /dev/null 2>&1

echo "🔗 Conectando SQS com Lambda..."

QUEUE_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-url \
  --queue-name fila-pedidos \
  --query 'QueueUrl' --output text)

QUEUE_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-name QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-event-source-mapping \
  --function-name ProcessarPedido \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  --enabled > /dev/null 2>&1 || echo "⚠️ Event source mapping já existe"

echo "📧 Configurando SNS (modo simples)..."

# No LocalStack, as permissões SNS geralmente funcionam automaticamente
# Adicionando subscritores de teste
aws --endpoint-url=$LOCALSTACK_ENDPOINT sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:000000000000:PedidosConcluidos \
  --protocol email \
  --notification-endpoint cliente@restaurante.com > /dev/null 2>&1 || true

aws --endpoint-url=$LOCALSTACK_ENDPOINT sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:000000000000:PedidosConcluidos \
  --protocol email \
  --notification-endpoint cozinha@restaurante.com > /dev/null 2>&1 || true

echo "✅ SNS configurado no modo simplificado"

# Limpeza
rm -f criarPedido.zip processarPedido.zip

echo ""
echo "🎉 DEPLOY SIMPLIFICADO CONCLUÍDO!"
echo "🔗 Endpoint:"
echo "POST http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos"
echo "📧 Tópico SNS: arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"
echo ""
echo "🧪 Teste rápido:"
echo 'curl -X POST http://'$ETH0_IP':4566/restapis/'$API_ID'/local/_user_request_/pedidos \'
echo '  -H "Content-Type: application/json" \'
echo '  -d "{\"cliente\":\"Test\",\"mesa\":1,\"itens\":[{\"nome\":\"Item\",\"quantidade\":1,\"preco\":10}]}"'
