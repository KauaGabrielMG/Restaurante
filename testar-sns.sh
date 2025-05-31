#!/bin/bash

# Script para testar notificações SNS do sistema de restaurante

set -e

echo "📧 Testando Sistema de Notificações SNS..."

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ETH0_IP" ]; then
  ETH0_IP="localhost"
fi

ENDPOINT_BASE="http://$ETH0_IP:4566"
echo "🌐 Endpoint: $ENDPOINT_BASE"

echo ""
echo "🔍 1. Verificando tópico SNS..."

# Verificar se o tópico existe
TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"
aws --endpoint-url=$ENDPOINT_BASE sns get-topic-attributes \
  --topic-arn $TOPIC_ARN > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Tópico SNS encontrado: $TOPIC_ARN"
else
    echo "❌ Tópico SNS não encontrado! Execute ./script.sh primeiro"
    exit 1
fi

echo ""
echo "🔍 2. Verificando subscritores..."

# Listar subscritores do tópico
echo "Subscritores do tópico:"
aws --endpoint-url=$ENDPOINT_BASE sns list-subscriptions-by-topic \
  --topic-arn $TOPIC_ARN \
  --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint}' \
  --output table

echo ""
echo "🔍 3. Testando publicação manual no SNS..."

# Publicar uma mensagem de teste
TEST_MESSAGE="Teste de notificação: Pedido teste-12345 está pronto! Cliente: João Test, Mesa: 99, Total: R$ 50,00"

PUBLISH_RESULT=$(aws --endpoint-url=$ENDPOINT_BASE sns publish \
  --topic-arn $TOPIC_ARN \
  --message "$TEST_MESSAGE" \
  --subject "🧪 Teste - Pedido Pronto!" \
  --message-attributes \
    'pedidoId={"DataType":"String","StringValue":"teste-12345"}' \
    'cliente={"DataType":"String","StringValue":"João Test"}' \
    'mesa={"DataType":"Number","StringValue":"99"}' \
    'total={"DataType":"Number","StringValue":"50.00"}' \
  --query 'MessageId' --output text)

echo "✅ Mensagem de teste publicada!"
echo "📧 MessageId: $PUBLISH_RESULT"

echo ""
echo "🔍 4. Testando fluxo completo com pedido real..."

# Encontrar o endpoint da API
API_ID=$(aws --endpoint-url=$ENDPOINT_BASE apigateway get-rest-apis \
  --query 'items[0].id' --output text)

if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
    echo "❌ API Gateway não encontrado! Execute ./script.sh primeiro"
    exit 1
fi

API_ENDPOINT="$ENDPOINT_BASE/restapis/$API_ID/local/_user_request_/pedidos"
echo "🔗 Endpoint da API: $API_ENDPOINT"

# Criar pedido de teste
cat > pedido-sns-teste.json << EOF
{
  "cliente": "Maria SNS Test",
  "mesa": 15,
  "itens": [
    {"nome": "Pizza SNS", "quantidade": 1, "preco": 30.00},
    {"nome": "Refrigerante", "quantidade": 2, "preco": 6.00}
  ]
}
EOF

echo ""
echo "📤 Enviando pedido para testar notificação..."

# Enviar pedido
RESPONSE=$(curl -s -X POST "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d @pedido-sns-teste.json)

echo "Resposta da API: $RESPONSE"

# Extrair ID do pedido
PEDIDO_ID=$(echo $RESPONSE | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ ! -z "$PEDIDO_ID" ]; then
    echo "✅ Pedido criado: $PEDIDO_ID"

    echo ""
    echo "⏳ Aguardando processamento (15 segundos)..."
    sleep 15

    echo ""
    echo "🔍 5. Verificando se notificação SNS foi enviada..."

    # Verificar logs do LocalStack para SNS
    echo "Procurando por notificações nos logs do LocalStack..."
    CONTAINER_ID=$(docker ps -q --filter "name=localstack" 2>/dev/null)

    if [ ! -z "$CONTAINER_ID" ]; then
        # Procurar por logs relacionados ao SNS e ao pedido
        echo ""
        echo "📋 Logs de SNS encontrados:"
        docker logs --since=30s "$CONTAINER_ID" 2>&1 | grep -i "sns\|PedidosConcluidos\|$PEDIDO_ID" || echo "Nenhum log específico encontrado"

        echo ""
        echo "📋 Logs de notificação (últimos 10):"
        docker logs --tail=10 "$CONTAINER_ID" 2>&1 | grep -A3 -B3 "publish\|sns" || echo "Nenhuma publicação encontrada"
    fi

    echo ""
    echo "🔍 6. Verificando status do pedido no DynamoDB..."

    # Verificar se o pedido foi processado
    aws --endpoint-url=$ENDPOINT_BASE dynamodb get-item \
      --table-name Pedidos \
      --key '{"id":{"S":"'$PEDIDO_ID'"}}' \
      --query 'Item.{ID:id.S,Cliente:cliente.S,Status:status.S,Mesa:mesa.N}' \
      --output table

else
    echo "❌ Falha ao criar pedido de teste"
fi

# Limpeza
rm -f pedido-sns-teste.json

echo ""
echo "🔍 7. Exemplo de saída esperada da notificação:"
echo ""
echo "{"
echo '  "TopicArn": "arn:aws:sns:us-east-1:000000000000:PedidosConcluidos",'
echo '  "Message": "Pedido teste-12345 foi processado e está pronto! Cliente: João Test, Mesa: 99, Total: R$ 50,00",'
echo '  "Subject": "🍽️ Pedido Pronto para Retirada!"'
echo "}"

echo ""
echo "📊 Para monitorar notificações em tempo real:"
echo "docker compose logs -f localstack | grep -i sns"

echo ""
echo "✅ Teste de SNS concluído!"
