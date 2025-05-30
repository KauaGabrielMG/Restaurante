#!/bin/bash

# Script de teste para o Sistema de Restaurante

set -e

echo "🧪 Iniciando testes do Sistema de Restaurante..."

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ETH0_IP" ]; then
  echo "❌ Não foi possível obter o IP da interface eth0"
  echo "💡 Tentando usar localhost como fallback..."
  ETH0_IP="localhost"
fi

echo "🌐 Usando IP da eth0: $ETH0_IP"

# Verificar se LocalStack está rodando
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

# Verificar se existe alguma API Gateway
API_IDS=$(aws --endpoint-url=http://$ETH0_IP:4566 apigateway get-rest-apis --query 'items[].id' --output text 2>/dev/null || true)

if [ -z "$API_IDS" ]; then
    echo "❌ Nenhuma API encontrada!"
    echo "💡 Execute primeiro: ./script.sh"
    exit 1
fi

# Pegar o primeiro API ID
API_ID=$(echo $API_IDS | awk '{print $1}')
ENDPOINT="http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos"

echo "🔗 Endpoint encontrado: $ENDPOINT"

echo ""
echo "🧪 Teste 1: Pedido válido"
echo "Enviando pedido de exemplo..."

RESPONSE=$(curl -s -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d @evento-exemplo.json)

echo "Resposta: $RESPONSE"

if echo "$RESPONSE" | grep -q "sucesso"; then
    echo "✅ Teste 1 PASSOU - Pedido criado com sucesso"
    PEDIDO_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    echo "📝 ID do pedido: $PEDIDO_ID"
else
    echo "❌ Teste 1 FALHOU - Pedido não foi criado"
fi

echo ""
echo "🧪 Teste 2: Pedido inválido (sem cliente)"
echo "Enviando pedido sem cliente..."

RESPONSE2=$(curl -s -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{"mesa": 5, "itens": []}')

echo "Resposta: $RESPONSE2"

if echo "$RESPONSE2" | grep -q "erro"; then
    echo "✅ Teste 2 PASSOU - Erro detectado corretamente"
else
    echo "❌ Teste 2 FALHOU - Erro não foi detectado"
fi

echo ""
echo "🧪 Teste 3: Verificar se pedido foi salvo no DynamoDB"

if [ ! -z "$PEDIDO_ID" ]; then
    DYNAMO_RESULT=$(aws --endpoint-url=http://$ETH0_IP:4566 dynamodb get-item \
      --table-name Pedidos \
      --key "{\"id\":{\"S\":\"$PEDIDO_ID\"}}" \
      --query 'Item' 2>/dev/null || true)

    if [ ! -z "$DYNAMO_RESULT" ] && [ "$DYNAMO_RESULT" != "null" ]; then
        echo "✅ Teste 3 PASSOU - Pedido encontrado no DynamoDB"
    else
        echo "❌ Teste 3 FALHOU - Pedido não encontrado no DynamoDB"
    fi
else
    echo "⚠️ Teste 3 PULADO - Sem ID de pedido para verificar"
fi

echo ""
echo "🧪 Teste 4: Verificar recursos AWS"

# Verificar DynamoDB
TABLES=$(aws --endpoint-url=http://$ETH0_IP:4566 dynamodb list-tables --query 'TableNames' --output text 2>/dev/null || true)
if echo "$TABLES" | grep -q "Pedidos"; then
    echo "✅ DynamoDB - Tabela Pedidos existe"
else
    echo "❌ DynamoDB - Tabela Pedidos não encontrada"
fi

# Verificar SQS
QUEUES=$(aws --endpoint-url=http://$ETH0_IP:4566 sqs list-queues --query 'QueueUrls' --output text 2>/dev/null || true)
if echo "$QUEUES" | grep -q "fila-pedidos"; then
    echo "✅ SQS - Fila fila-pedidos existe"
else
    echo "❌ SQS - Fila fila-pedidos não encontrada"
fi

# Verificar S3
BUCKETS=$(aws --endpoint-url=http://$ETH0_IP:4566 s3 ls 2>/dev/null | awk '{print $3}' || true)
if echo "$BUCKETS" | grep -q "comprovantes"; then
    echo "✅ S3 - Bucket comprovantes existe"
else
    echo "❌ S3 - Bucket comprovantes não encontrado"
fi

# Verificar Lambda
FUNCTIONS=$(aws --endpoint-url=http://$ETH0_IP:4566 lambda list-functions --query 'Functions[].FunctionName' --output text 2>/dev/null || true)
if echo "$FUNCTIONS" | grep -q "CriarPedido"; then
    echo "✅ Lambda - Função CriarPedido existe"
else
    echo "❌ Lambda - Função CriarPedido não encontrada"
fi

if echo "$FUNCTIONS" | grep -q "ProcessarPedido"; then
    echo "✅ Lambda - Função ProcessarPedido existe"
else
    echo "❌ Lambda - Função ProcessarPedido não encontrada"
fi

echo ""
echo "🎉 Testes concluídos!"
echo ""
echo "💡 Para ver mais detalhes dos recursos:"
echo "   aws --endpoint-url=http://$ETH0_IP:4566 dynamodb scan --table-name Pedidos"
echo "   aws --endpoint-url=http://$ETH0_IP:4566 s3 ls s3://comprovantes/"
echo ""
echo "💡 Para limpar recursos:"
echo "   ./remover-recursos-aws.sh"
