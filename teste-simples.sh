#!/bin/bash

# Script de teste simples para o Sistema de Restaurante

set -e

echo "Teste Simples do Sistema de Restaurante"

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
    for interface in eth1 enp0s3 enp0s8 wlan0 wlp2s0; do
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
  ETH0_IP="localhost"
fi

echo "Usando endpoint: http://$ETH0_IP:4566"
LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"

echo ""
echo "1. Verificando recursos basicos..."

# Verificar DynamoDB
TABLES=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb list-tables --query 'TableNames' --output text 2>/dev/null || echo "erro")
echo "Tabelas DynamoDB: $TABLES"

# Verificar Lambda
FUNCTIONS=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda list-functions --query 'Functions[].FunctionName' --output text 2>/dev/null || echo "erro")
echo "Funcoes Lambda: $FUNCTIONS"

# Verificar API Gateway
API_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-rest-apis --query 'items[0].id' --output text 2>/dev/null || echo "erro")
echo "API Gateway: $API_ID"

echo ""
echo "2. Testando endpoint HTTP..."

if [ "$API_ID" != "erro" ] && [ "$API_ID" != "None" ]; then
  ENDPOINT="http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos"
  echo "Endpoint: $ENDPOINT"

  echo "Enviando pedido via curl..."
  RESPONSE=$(curl -s -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d '{"cliente":"Test","mesa":1,"itens":[{"nome":"Item","quantidade":1,"preco":10}]}' 2>/dev/null || echo "Erro no curl")

  echo "Resposta HTTP: $RESPONSE"
else
  echo "API Gateway nao encontrada - pulando teste HTTP"
fi

echo ""
echo "Teste concluido!"
