#!/bin/bash

# Script para debugar problemas do sistema

set -e

echo "🔍 Iniciando debug do Sistema de Restaurante..."

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ETH0_IP" ]; then
  ETH0_IP="localhost"
fi

echo "🌐 Usando IP da eth0: $ETH0_IP"
LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"

echo ""
echo "🔍 1. Verificando status dos recursos AWS..."

# Verificar Lambda
echo "📋 Funções Lambda:"
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda list-functions --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Handler:Handler}' --output table

# Verificar DynamoDB
echo ""
echo "📋 Tabelas DynamoDB:"
aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb list-tables --output table

# Verificar SQS
echo ""
echo "📋 Filas SQS:"
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs list-queues --output table

# Verificar S3
echo ""
echo "📋 Buckets S3:"
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 ls

echo ""
echo "🔍 2. Verificando logs do LocalStack..."
echo "Últimas 20 linhas dos logs:"

# Verificar se docker compose está disponível
if command -v docker-compose &> /dev/null; then
    docker-compose logs --tail=20 localstack 2>/dev/null || echo "❌ Erro ao acessar logs"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose logs --tail=20 localstack 2>/dev/null || echo "❌ Erro ao acessar logs"
else
    # Fallback para docker logs direto
    CONTAINER_ID=$(docker ps -q --filter "name=localstack" 2>/dev/null)
    if [ ! -z "$CONTAINER_ID" ]; then
        docker logs --tail 20 "$CONTAINER_ID" 2>/dev/null || echo "❌ Erro ao acessar logs"
    else
        echo "❌ Container LocalStack não encontrado"
    fi
fi

echo ""
echo "🔍 3. Verificando arquivos compilados..."
if [ -f criar-pedido.js ]; then
  echo "✅ criar-pedido.js existe"
else
  echo "❌ criar-pedido.js não encontrado"
fi

if [ -f processar-pedido.js ]; then
  echo "✅ processar-pedido.js existe"
else
  echo "❌ processar-pedido.js não encontrado"
fi

if [ -f gerarPDF.js ]; then
  echo "✅ gerarPDF.js existe"
else
  echo "❌ gerarPDF.js não encontrado"
fi

echo ""
echo "🔍 4. Verificando estrutura dos zips..."
if [ -f criarPedido.zip ]; then
  echo "criarPedido.zip existe"
else
  echo "❌ criarPedido.zip não encontrado"
fi
if [ -f processarPedido.zip ]; then
  echo "processarPedido.zip existe"
else
  echo "❌ processarPedido.zip não encontrado"
fi

echo ""
echo "🔍 5. Verificando configuração da API Gateway..."
API_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-rest-apis --query 'items[0].id' --output text)
if [ "$API_ID" != "None" ] && [ ! -z "$API_ID" ]; then
  echo "API ID: $API_ID"
  echo "Recursos da API:"
  aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-resources --rest-api-id $API_ID --output table
else
  echo "❌ API Gateway não encontrada"
fi

echo ""
echo "🔧 Sugestões para resolver o problema:"
echo "1. Verificar se os arquivos TypeScript compilaram corretamente"
echo "2. Verificar se as dependências estão no package.json"
echo "3. Recompilar e fazer novo deploy:"
echo "   ./remover-recursos-aws.sh"
echo "   ./script.sh"
echo "4. Verificar logs detalhados: docker compose logs localstack | grep -i error"
