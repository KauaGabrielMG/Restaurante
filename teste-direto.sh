#!/bin/bash

# Script de teste direto para Lambda sem problemas de codificação

set -e

echo "🧪 Teste Direto da Lambda - Sistema de Restaurante"

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

ENDPOINT_BASE="http://$ETH0_IP:4566"

echo "🌐 Usando endpoint: $ENDPOINT_BASE"

# Verificar se LocalStack está rodando
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    exit 1
fi

echo ""
echo "🔍 1. Verificando função Lambda CriarPedido..."

# Verificar se a função existe
if ! aws --endpoint-url=$ENDPOINT_BASE lambda get-function --function-name CriarPedido > /dev/null 2>&1; then
    echo "❌ Função CriarPedido não encontrada. Execute ./script.sh primeiro."
    exit 1
fi

echo "✅ Função CriarPedido encontrada"

echo ""
echo "🔍 2. Testando com payload JSON básico..."

# Criar payload usando echo para evitar problemas de codificação
echo '{
  "body": "{\"cliente\":\"Joao\",\"mesa\":5,\"itens\":[{\"nome\":\"Teste\",\"quantidade\":1,\"preco\":10.5}]}",
  "headers": {"Content-Type": "application/json"},
  "httpMethod": "POST",
  "path": "/pedidos"
}' > lambda-test.json

echo "Invocando Lambda diretamente..."

# Testar com timeout maior e encoding correto
aws --endpoint-url=$ENDPOINT_BASE lambda invoke \
  --function-name CriarPedido \
  --cli-binary-format raw-in-base64-out \
  --payload file://lambda-test.json \
  --cli-read-timeout 30 \
  lambda-output.json

echo ""
echo "📊 Resultado da Lambda:"
if [ -f lambda-output.json ]; then
    cat lambda-output.json
    echo ""

    # Verificar se foi sucesso
    if grep -q "sucesso" lambda-output.json; then
        echo "✅ Lambda executou com sucesso!"

        # Extrair ID do pedido se houver
        PEDIDO_ID=$(grep -o '"id":"[^"]*"' lambda-output.json | cut -d'"' -f4 2>/dev/null || echo "")
        if [ ! -z "$PEDIDO_ID" ]; then
            echo "📝 ID do pedido: $PEDIDO_ID"

            # Verificar no DynamoDB
            echo ""
            echo "🔍 3. Verificando no DynamoDB..."
            if aws --endpoint-url=$ENDPOINT_BASE dynamodb get-item \
                --table-name Pedidos \
                --key "{\"id\":{\"S\":\"$PEDIDO_ID\"}}" > /dev/null 2>&1; then
                echo "✅ Pedido encontrado no DynamoDB"
            else
                echo "❌ Pedido não encontrado no DynamoDB"
            fi
        fi
    else
        echo "❌ Lambda retornou erro"
    fi
else
    echo "❌ Arquivo de saída não criado"
fi

# Limpeza
rm -f lambda-test.json lambda-output.json

echo ""
echo "🔍 4. Testando via API Gateway..."

# Encontrar API ID
API_ID=$(aws --endpoint-url=$ENDPOINT_BASE apigateway get-rest-apis --query 'items[0].id' --output text 2>/dev/null)

if [ "$API_ID" != "None" ] && [ ! -z "$API_ID" ]; then
    FULL_ENDPOINT="$ENDPOINT_BASE/restapis/$API_ID/local/_user_request_/pedidos"
    echo "🌐 Endpoint: $FULL_ENDPOINT"

    # Criar payload simples para API Gateway
    echo '{
      "cliente": "Maria Silva",
      "mesa": 3,
      "itens": [
        {"nome": "Hamburguer", "quantidade": 1, "preco": 25.50}
      ]
    }' > api-test.json

    echo "Testando via curl..."
    CURL_RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$FULL_ENDPOINT" \
      -H "Content-Type: application/json" \
      -d @api-test.json)

    echo "Resposta:"
    echo "$CURL_RESULT"

    rm -f api-test.json
else
    echo "❌ API Gateway não encontrada"
fi

echo ""
echo "✅ Teste direto concluído!"
