#!/bin/bash

# Script de teste para o Sistema de Restaurante

set -e

echo "🧪 Iniciando testes do Sistema de Restaurante..."


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

# Verificar se arquivo de exemplo existe, senão criar um
if [ ! -f "evento-exemplo.json" ]; then
    cat > evento-exemplo.json << EOF
{
  "cliente": "João Silva",
  "mesa": 5,
  "itens": [
    {
      "nome": "Hambúrguer Artesanal",
      "quantidade": 1,
      "preco": 28.90
    },
    {
      "nome": "Batata Frita",
      "quantidade": 1,
      "preco": 12.50
    },
    {
      "nome": "Refrigerante",
      "quantidade": 1,
      "preco": 6.00
    }
  ]
}
EOF
fi

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

# Verificar SNS
TOPICS=$(aws --endpoint-url=http://$ETH0_IP:4566 sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null || true)
if echo "$TOPICS" | grep -q "PedidosConcluidos"; then
    echo "✅ SNS - Tópico PedidosConcluidos existe"
else
    echo "❌ SNS - Tópico PedidosConcluidos não encontrado"
fi

echo ""
echo "🧪 Teste 5: Verificar processamento de pedidos e notificações SNS"

if [ ! -z "$PEDIDO_ID" ]; then
    echo "Aguardando processamento do pedido (10 segundos)..."
    sleep 10

    # Verificar se pedido foi processado (status atualizado)
    PEDIDO_STATUS=$(aws --endpoint-url=http://$ETH0_IP:4566 dynamodb get-item \
      --table-name Pedidos \
      --key "{\"id\":{\"S\":\"$PEDIDO_ID\"}}" \
      --query 'Item.status.S' --output text 2>/dev/null || true)

    if [ "$PEDIDO_STATUS" = "PROCESSADO" ]; then
        echo "✅ Teste 5a PASSOU - Pedido foi processado (status: PROCESSADO)"
    elif [ "$PEDIDO_STATUS" = "Pendente" ]; then
        echo "⚠️ Teste 5a PARCIAL - Pedido ainda está pendente (pode estar processando)"
    else
        echo "❌ Teste 5a FALHOU - Status do pedido: $PEDIDO_STATUS"
    fi

    # Verificar se PDF foi gerado no S3
    S3_FILES=$(aws --endpoint-url=http://$ETH0_IP:4566 s3 ls s3://comprovantes/ 2>/dev/null | grep "$PEDIDO_ID" || true)
    if [ ! -z "$S3_FILES" ]; then
        echo "✅ Teste 5b PASSOU - PDF do comprovante foi gerado no S3"
    else
        echo "❌ Teste 5b FALHOU - PDF não encontrado no S3"
    fi

    # Verificar logs do SNS (notificações enviadas)
    echo "Verificando notificações SNS enviadas..."
    SNS_LOGS=$(docker logs restaurante-localstack-1 2>&1 | grep -i "pedidosconcluidos\|sns.*publish" | tail -5 || true)
    if [ ! -z "$SNS_LOGS" ]; then
        echo "✅ Teste 5c PASSOU - Notificações SNS foram enviadas"
        echo "📧 Últimas notificações:"
        echo "$SNS_LOGS" | head -3
    else
        echo "❌ Teste 5c FALHOU - Nenhuma notificação SNS encontrada nos logs"
    fi

else
    echo "⚠️ Teste 5 PULADO - Sem ID de pedido para verificar processamento"
fi

echo ""
echo "🧪 Teste 6: Testar notificação SNS manual"

# Publicar mensagem de teste no SNS
TEST_MESSAGE="Teste do sistema de notificações - $(date)"
SNS_RESULT=$(aws --endpoint-url=http://$ETH0_IP:4566 sns publish \
  --topic-arn "arn:aws:sns:us-east-1:000000000000:PedidosConcluidos" \
  --message "$TEST_MESSAGE" \
  --subject "🧪 Teste SNS" 2>/dev/null || echo "ERRO")

if [ "$SNS_RESULT" != "ERRO" ] && echo "$SNS_RESULT" | grep -q "MessageId"; then
    MESSAGE_ID=$(echo "$SNS_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Teste 6 PASSOU - Notificação SNS manual enviada (MessageId: $MESSAGE_ID)"
else
    echo "❌ Teste 6 FALHOU - Erro ao enviar notificação SNS manual"
fi

echo ""
echo "🧪 Teste 7: Verificar atributos do tópico SNS"

# Verificar detalhes do tópico SNS
TOPIC_ATTRS=$(aws --endpoint-url=http://$ETH0_IP:4566 sns get-topic-attributes \
  --topic-arn "arn:aws:sns:us-east-1:000000000000:PedidosConcluidos" \
  --query 'Attributes' 2>/dev/null || echo "ERRO")

if [ "$TOPIC_ATTRS" != "ERRO" ] && echo "$TOPIC_ATTRS" | grep -q "TopicArn"; then
    echo "✅ Teste 7 PASSOU - Tópico SNS configurado corretamente"
    # Mostrar alguns atributos importantes
    DISPLAY_NAME=$(echo "$TOPIC_ATTRS" | grep -o '"DisplayName": "[^"]*"' | cut -d'"' -f4 || echo "N/A")
    TOPIC_ARN=$(echo "$TOPIC_ATTRS" | grep -o '"TopicArn": "[^"]*"' | cut -d'"' -f4 || echo "N/A")
    echo "  📧 TopicArn: $TOPIC_ARN"
    echo "  📝 DisplayName: $DISPLAY_NAME"
else
    echo "❌ Teste 7 FALHOU - Erro ao obter atributos do tópico SNS"
fi

echo ""
echo "🧪 Teste 8: Simular notificação de pedido completo"

if [ ! -z "$PEDIDO_ID" ]; then
    # Simular notificação completa com todos os atributos
    PEDIDO_MESSAGE=$(cat << EOF
{
  "pedidoId": "$PEDIDO_ID",
  "cliente": "João",
  "mesa": 5,
  "status": "PRONTO",
  "total": 25.99,
  "itens": ["Pizza"],
  "timestamp": "$(date -Iseconds)"
}
EOF
)

    SNS_COMPLETE_RESULT=$(aws --endpoint-url=http://$ETH0_IP:4566 sns publish \
      --topic-arn "arn:aws:sns:us-east-1:000000000000:PedidosConcluidos" \
      --message "$PEDIDO_MESSAGE" \
      --subject "🍽️ Pedido $PEDIDO_ID Pronto para Retirada!" \
      --message-attributes '{
        "pedidoId": {
          "DataType": "String",
          "StringValue": "'$PEDIDO_ID'"
        },
        "cliente": {
          "DataType": "String",
          "StringValue": "João"
        },
        "mesa": {
          "DataType": "Number",
          "StringValue": "5"
        },
        "total": {
          "DataType": "Number",
          "StringValue": "25.99"
        }
      }' 2>/dev/null || echo "ERRO")

    if [ "$SNS_COMPLETE_RESULT" != "ERRO" ] && echo "$SNS_COMPLETE_RESULT" | grep -q "MessageId"; then
        COMPLETE_MSG_ID=$(echo "$SNS_COMPLETE_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
        echo "✅ Teste 8 PASSOU - Notificação completa enviada (MessageId: $COMPLETE_MSG_ID)"
        echo "📧 Mensagem com atributos personalizados enviada ao SNS"
    else
        echo "❌ Teste 8 FALHOU - Erro ao enviar notificação completa"
    fi
else
    echo "⚠️ Teste 8 PULADO - Sem ID de pedido para simular notificação completa"
fi

echo ""
echo "🧪 Teste 9: Verificar histórico de mensagens SNS nos logs"

echo "Verificando últimas 10 mensagens SNS nos logs do LocalStack..."
SNS_HISTORY=$(docker logs restaurante-localstack-1 2>&1 | grep -i "sns.*publish\|pedidosconcluidos" | tail -10 || true)

if [ ! -z "$SNS_HISTORY" ]; then
    echo "✅ Teste 9 PASSOU - Histórico de mensagens SNS encontrado"
    echo "📊 Últimas mensagens SNS:"
    echo "$SNS_HISTORY" | head -5 | while read line; do
        echo "  📧 $line"
    done
else
    echo "❌ Teste 9 FALHOU - Nenhum histórico de mensagens SNS encontrado"
fi

echo ""
echo "🎉 Todos os testes concluídos!"
echo ""
echo "💡 Para ver mais detalhes dos recursos:"
echo "   aws --endpoint-url=http://$ETH0_IP:4566 dynamodb scan --table-name Pedidos"
echo "   aws --endpoint-url=http://$ETH0_IP:4566 s3 ls s3://comprovantes/"
echo ""
echo "💡 Para limpar recursos:"
echo "   ./remover-recursos-aws.sh"
