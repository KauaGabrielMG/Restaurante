#!/bin/bash

set -e

# Função para tratamento de erros
handle_error() {
    echo "❌ Erro na linha $1: $2"
    exit 1
}

# Configurar trap para capturar erros
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "🗑️ Iniciando remoção de recursos AWS do LocalStack..."

# Obter IP da interface eth0
echo "🌐 Obtendo IP da interface eth0..."
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ETH0_IP" ]; then
  echo "❌ Não foi possível obter o IP da interface eth0"
  echo "💡 Tentando usar localhost como fallback..."
  ETH0_IP="localhost"
fi

echo "🌐 Usando IP da eth0: $ETH0_IP"
LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"
echo "LocalStack Endpoint: $LOCALSTACK_ENDPOINT"

# Verificar se o LocalStack está rodando
echo "🔍 Verificando se o LocalStack está rodando..."
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

echo "🧼 Removendo artefatos locais..."
rm -f criarPedido.zip processarPedido.zip
rm -f criar-pedido.js processar-pedido.js gerarPDF.js

echo "🗑️ Removendo recursos AWS..."

# Listar e remover funções Lambda
echo "🚀 Removendo funções Lambda..."
LAMBDA_FUNCTIONS=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda list-functions --query 'Functions[].FunctionName' --output text 2>/dev/null || true)

if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
    for func in $LAMBDA_FUNCTIONS; do
        if [[ "$func" == "CriarPedido" ]] || [[ "$func" == "ProcessarPedido" ]]; then
            echo "  🗑️ Removendo função Lambda: $func"
            aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda delete-function --function-name "$func" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhuma função Lambda encontrada"
fi

# Remover APIs do API Gateway
echo "🌐 Removendo APIs do API Gateway..."
API_IDS=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-rest-apis --query 'items[?name==`RestauranteAPI`].id' --output text 2>/dev/null || true)

if [ ! -z "$API_IDS" ]; then
    for api_id in $API_IDS; do
        if [ "$api_id" != "None" ] && [ ! -z "$api_id" ]; then
            echo "  🗑️ Removendo API Gateway: $api_id"
            aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway delete-rest-api --rest-api-id "$api_id" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhuma API do API Gateway encontrada"
fi

# Remover tabelas DynamoDB
echo "🗂️ Removendo tabelas DynamoDB..."
TABLES=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb list-tables --query 'TableNames' --output text 2>/dev/null || true)

if [ ! -z "$TABLES" ]; then
    for table in $TABLES; do
        if [[ "$table" == "Pedidos" ]]; then
            echo "  🗑️ Removendo tabela DynamoDB: $table"
            aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb delete-table --table-name "$table" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhuma tabela DynamoDB encontrada"
fi

# Remover filas SQS
echo "📬 Removendo filas SQS..."
QUEUES=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs list-queues --query 'QueueUrls' --output text 2>/dev/null || true)

if [ ! -z "$QUEUES" ]; then
    for queue_url in $QUEUES; do
        if [[ "$queue_url" == *"fila-pedidos"* ]]; then
            echo "  🗑️ Removendo fila SQS: fila-pedidos"
            aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs delete-queue --queue-url "$queue_url" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhuma fila SQS encontrada"
fi

# Remover buckets S3
echo "🗃️ Removendo buckets S3..."
BUCKETS=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 ls --output text 2>/dev/null | awk '{print $3}' || true)

if [ ! -z "$BUCKETS" ]; then
    for bucket in $BUCKETS; do
        if [[ "$bucket" == "comprovantes" ]]; then
            echo "  🗑️ Removendo bucket S3: $bucket"
            # Primeiro remover todos os objetos do bucket
            aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 rm s3://"$bucket" --recursive > /dev/null 2>&1 || true
            # Depois remover o bucket
            aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 rb s3://"$bucket" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhum bucket S3 encontrado"
fi

# Remover event source mappings
echo "🔗 Removendo mapeamentos de origem de eventos Lambda..."
EVENT_MAPPINGS=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda list-event-source-mappings --query 'EventSourceMappings[].UUID' --output text 2>/dev/null || true)

if [ ! -z "$EVENT_MAPPINGS" ]; then
    for mapping_uuid in $EVENT_MAPPINGS; do
        if [ "$mapping_uuid" != "None" ] && [ ! -z "$mapping_uuid" ]; then
            echo "  🗑️ Removendo mapeamento: $mapping_uuid"
            aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda delete-event-source-mapping --uuid "$mapping_uuid" > /dev/null 2>&1 || true
        fi
    done
else
    echo "  ✅ Nenhum mapeamento de origem de eventos encontrado"
fi

echo ""
echo "🎉 REMOÇÃO CONCLUÍDA COM SUCESSO!"
echo "✅ Todos os recursos do Sistema de Restaurante foram removidos do LocalStack"
echo "💡 Para parar completamente o LocalStack, execute: docker compose down"
