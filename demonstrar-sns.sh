#!/bin/bash

# Script para demonstrar notificações SNS no Sistema de Restaurante

set -e

echo "📧 Demonstração das Notificações SNS do Sistema de Restaurante"
echo "=============================================================="

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

    # Fallback para localhost
    echo "localhost"
}

ETH0_IP=$(get_machine_ip)
ENDPOINT_URL="http://$ETH0_IP:4566"
TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"

echo "🌐 Endpoint LocalStack: $ENDPOINT_URL"
echo "📧 Tópico SNS: $TOPIC_ARN"
echo ""

# Verificar se LocalStack está rodando
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

# Verificar se o tópico SNS existe
if ! aws --endpoint-url=$ENDPOINT_URL sns get-topic-attributes --topic-arn $TOPIC_ARN > /dev/null 2>&1; then
    echo "❌ Tópico SNS não encontrado!"
    echo "💡 Execute primeiro: ./script.sh"
    exit 1
fi

echo "✅ LocalStack e tópico SNS estão funcionando!"
echo ""

echo "📧 Demonstração 1: Notificação de Pedido Pronto (como o sistema envia)"
echo "--------------------------------------------------------------------"

PEDIDO_ID="demo-$(date +%s)"
CLIENTE="Maria Silva"
MESA=7
TOTAL=52.50

# Simular notificação como o sistema ProcessarPedido envia
MENSAGEM_PEDIDO_PRONTO=$(cat << EOF
{
  "pedidoId": "$PEDIDO_ID",
  "cliente": "$CLIENTE",
  "mesa": $MESA,
  "status": "PRONTO",
  "total": "$TOTAL",
  "itens": [
    {"nome": "Pizza Margherita", "quantidade": 1, "preco": 28.90},
    {"nome": "Coca-Cola 2L", "quantidade": 1, "preco": 8.50},
    {"nome": "Sobremesa Pudim", "quantidade": 1, "preco": 15.10}
  ],
  "timestamp": "$(date -Iseconds)",
  "comprovanteS3": "$PEDIDO_ID.pdf",
  "mensagem": "Seu pedido está pronto para retirada na mesa $MESA!"
}
EOF
)

echo "📝 Enviando notificação de pedido pronto..."
echo "📧 Cliente: $CLIENTE"
echo "🍽️ Mesa: $MESA"
echo "💰 Total: R$ $TOTAL"

RESULT_PEDIDO=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$MENSAGEM_PEDIDO_PRONTO" \
  --subject "🍽️ Pedido Pronto para Retirada!" \
  --message-attributes '{
    "pedidoId": {
      "DataType": "String",
      "StringValue": "'$PEDIDO_ID'"
    },
    "cliente": {
      "DataType": "String",
      "StringValue": "'$CLIENTE'"
    },
    "mesa": {
      "DataType": "Number",
      "StringValue": "'$MESA'"
    },
    "total": {
      "DataType": "Number",
      "StringValue": "'$TOTAL'"
    },
    "status": {
      "DataType": "String",
      "StringValue": "PRONTO"
    },
    "tipo": {
      "DataType": "String",
      "StringValue": "PEDIDO_PRONTO"
    }
  }' 2>/dev/null || echo "ERRO")

if echo "$RESULT_PEDIDO" | grep -q "MessageId"; then
    MSG_ID=$(echo "$RESULT_PEDIDO" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Notificação enviada com sucesso!"
    echo "📧 MessageId: $MSG_ID"
    echo ""
    echo "📋 Exemplo de saída da notificação:"
    echo "{"
    echo "  \"TopicArn\": \"$TOPIC_ARN\","
    echo "  \"Message\": \"<JSON com detalhes do pedido>\","
    echo "  \"Subject\": \"🍽️ Pedido Pronto para Retirada!\","
    echo "  \"MessageId\": \"$MSG_ID\""
    echo "}"
else
    echo "❌ Erro ao enviar notificação"
fi

echo ""
echo ""

echo "📧 Demonstração 2: Notificação de Alerta para Cozinha"
echo "----------------------------------------------------"

MENSAGEM_COZINHA=$(cat << EOF
{
  "tipo": "ALERTA_COZINHA",
  "pedidoId": "$PEDIDO_ID",
  "mesa": $MESA,
  "cliente": "$CLIENTE",
  "quantidadeItens": 3,
  "tempoProcessamento": "$(date -Iseconds)",
  "acao": "Pedido processado e comprovante gerado"
}
EOF
)

echo "📝 Enviando alerta para cozinha..."

RESULT_COZINHA=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$MENSAGEM_COZINHA" \
  --subject "👨‍🍳 Pedido Processado - Alerta Cozinha" \
  --message-attributes '{
    "pedidoId": {
      "DataType": "String",
      "StringValue": "'$PEDIDO_ID'"
    },
    "tipo": {
      "DataType": "String",
      "StringValue": "ALERTA_COZINHA"
    },
    "mesa": {
      "DataType": "Number",
      "StringValue": "'$MESA'"
    },
    "prioridade": {
      "DataType": "String",
      "StringValue": "NORMAL"
    }
  }' 2>/dev/null || echo "ERRO")

if echo "$RESULT_COZINHA" | grep -q "MessageId"; then
    MSG_ID_COZINHA=$(echo "$RESULT_COZINHA" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Alerta para cozinha enviado com sucesso!"
    echo "📧 MessageId: $MSG_ID_COZINHA"
else
    echo "❌ Erro ao enviar alerta para cozinha"
fi

echo ""
echo ""

echo "📧 Demonstração 3: Notificação de Erro/Problema"
echo "-----------------------------------------------"

ERRO_PEDIDO_ID="erro-$(date +%s)"
MENSAGEM_ERRO=$(cat << EOF
{
  "tipo": "ERRO_PROCESSAMENTO",
  "pedidoId": "$ERRO_PEDIDO_ID",
  "erro": "Falha ao gerar comprovante PDF",
  "detalhes": "Erro interno do servidor S3",
  "timestamp": "$(date -Iseconds)",
  "acao_requerida": "Reprocessar pedido ou notificar suporte técnico",
  "prioridade": "ALTA"
}
EOF
)

echo "🚨 Enviando notificação de erro..."

RESULT_ERRO=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$MENSAGEM_ERRO" \
  --subject "🚨 Erro no Processamento de Pedido" \
  --message-attributes '{
    "pedidoId": {
      "DataType": "String",
      "StringValue": "'$ERRO_PEDIDO_ID'"
    },
    "tipo": {
      "DataType": "String",
      "StringValue": "ERRO_PROCESSAMENTO"
    },
    "prioridade": {
      "DataType": "String",
      "StringValue": "ALTA"
    },
    "categoria": {
      "DataType": "String",
      "StringValue": "SISTEMA"
    }
  }' 2>/dev/null || echo "ERRO")

if echo "$RESULT_ERRO" | grep -q "MessageId"; then
    MSG_ID_ERRO=$(echo "$RESULT_ERRO" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Notificação de erro enviada com sucesso!"
    echo "📧 MessageId: $MSG_ID_ERRO"
else
    echo "❌ Erro ao enviar notificação de erro"
fi

echo ""
echo ""

echo "📧 Demonstração 4: Criar e enviar pedido real via API (com notificação automática)"
echo "---------------------------------------------------------------------------------"

# Encontrar API Gateway
API_ID=$(aws --endpoint-url=$ENDPOINT_URL apigateway get-rest-apis --query 'items[0].id' --output text 2>/dev/null)
if [ "$API_ID" != "None" ] && [ ! -z "$API_ID" ]; then
    API_ENDPOINT="$ENDPOINT_URL/restapis/$API_ID/local/_user_request_/pedidos"
    echo "🔗 API Endpoint: $API_ENDPOINT"

    # Criar pedido via API
    PEDIDO_REAL=$(cat << EOF
{
  "cliente": "João Santos",
  "mesa": 12,
  "itens": [
    {"nome": "Hambúrguer Bacon", "quantidade": 1, "preco": 32.90},
    {"nome": "Batata Frita G", "quantidade": 1, "preco": 14.50},
    {"nome": "Milk Shake", "quantidade": 1, "preco": 18.00}
  ]
}
EOF
)

    echo "📝 Criando pedido real via API..."
    echo "🍔 Cliente: João Santos"
    echo "🍽️ Mesa: 12"
    echo "💰 Total estimado: R$ 65,40"

    API_RESPONSE=$(curl -s -X POST "$API_ENDPOINT" \
      -H "Content-Type: application/json" \
      -d "$PEDIDO_REAL")

    echo "📋 Resposta da API:"
    echo "$API_RESPONSE"

    if echo "$API_RESPONSE" | grep -q "sucesso"; then
        REAL_PEDIDO_ID=$(echo "$API_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        echo ""
        echo "✅ Pedido criado com sucesso!"
        echo "📝 ID do pedido: $REAL_PEDIDO_ID"
        echo "⏳ Aguardando processamento e notificação automática..."
        echo "💡 A Lambda ProcessarPedido irá enviar notificações SNS automaticamente"
    else
        echo "❌ Erro ao criar pedido"
    fi
else
    echo "⚠️ API Gateway não encontrada. Execute './script.sh' primeiro."
fi

echo ""
echo ""

echo "📊 Verificando Logs de Notificações SNS"
echo "========================================"

echo "🔍 Verificando logs das últimas notificações enviadas..."
sleep 3  # Aguardar logs serem processados

# Verificar logs do LocalStack
CONTAINER_ID=$(docker ps -q --filter "name=localstack" 2>/dev/null | head -1)
if [ ! -z "$CONTAINER_ID" ]; then
    echo "📋 Últimas 10 notificações SNS nos logs:"
    docker logs --tail=50 "$CONTAINER_ID" 2>&1 | grep -i "sns.*publish\|pedidosconcluidos" | tail -10 | while read line; do
        echo "  📧 $(echo $line | cut -c1-120)..."
    done

    echo ""
    TOTAL_SNS=$(docker logs "$CONTAINER_ID" 2>&1 | grep -i "sns.*publish" | wc -l || echo "0")
    echo "📊 Total de notificações SNS enviadas: $TOTAL_SNS"
else
    echo "⚠️ Container LocalStack não encontrado"
fi

echo ""
echo ""

echo "🎯 Resumo das Demonstrações"
echo "============================"
echo "✅ 1. Notificação de Pedido Pronto - Enviada"
echo "✅ 2. Alerta para Cozinha - Enviado"
echo "✅ 3. Notificação de Erro - Enviada"
if [ ! -z "$REAL_PEDIDO_ID" ]; then
    echo "✅ 4. Pedido Real via API - Criado (ID: $REAL_PEDIDO_ID)"
else
    echo "⚠️ 4. Pedido Real via API - Não testado"
fi

echo ""
echo "📧 Formato Padrão das Notificações SNS:"
echo "{"
echo "  \"TopicArn\": \"arn:aws:sns:us-east-1:000000000000:PedidosConcluidos\","
echo "  \"Message\": \"<JSON com detalhes do pedido ou evento>\","
echo "  \"Subject\": \"<Assunto da notificação>\","
echo "  \"MessageAttributes\": {"
echo "    \"pedidoId\": { \"DataType\": \"String\", \"StringValue\": \"<ID>\" },"
echo "    \"tipo\": { \"DataType\": \"String\", \"StringValue\": \"<TIPO>\" },"
echo "    \"cliente\": { \"DataType\": \"String\", \"StringValue\": \"<NOME>\" }"
echo "  }"
echo "}"

echo ""
echo "💡 Comandos úteis:"
echo "  - Ver logs SNS: docker logs \$(docker ps -q --filter 'name=localstack') 2>&1 | grep -i sns"
echo "  - Testar sistema: ./testar-sistema.sh"
echo "  - Listar tópicos: aws --endpoint-url=$ENDPOINT_URL sns list-topics"

echo ""
echo "🎉 Demonstração das Notificações SNS concluída!"
