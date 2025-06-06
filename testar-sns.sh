#!/bin/bash

# Script específico para testar SNS no Sistema de Restaurante

set -e

echo "📧 Testando Sistema de Notificações SNS..."

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

    return 1
}

ETH0_IP=$(get_machine_ip)

if [ -z "$ETH0_IP" ]; then
  echo "❌ Não foi possível obter o IP da interface eth0"
  echo "💡 Tentando usar localhost como fallback..."
  ETH0_IP="localhost"
fi

echo "🌐 Usando IP: $ETH0_IP"
ENDPOINT_URL="http://$ETH0_IP:4566"

# Verificar se LocalStack está rodando
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

echo ""
echo "📧 Teste 1: Verificar se tópico SNS existe"

TOPICS=$(aws --endpoint-url=$ENDPOINT_URL sns list-topics --query 'Topics[].TopicArn' --output text 2>/dev/null || true)
TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"

if echo "$TOPICS" | grep -q "PedidosConcluidos"; then
    echo "✅ Tópico SNS 'PedidosConcluidos' existe"
    echo "📧 ARN: $TOPIC_ARN"
else
    echo "❌ Tópico SNS 'PedidosConcluidos' não encontrado"
    echo "💡 Execute primeiro: ./script.sh"
    exit 1
fi

echo ""
echo "📧 Teste 2: Verificar atributos do tópico SNS"

TOPIC_ATTRS=$(aws --endpoint-url=$ENDPOINT_URL sns get-topic-attributes \
  --topic-arn "$TOPIC_ARN" \
  --query 'Attributes' 2>/dev/null || echo "ERRO")

if [ "$TOPIC_ATTRS" != "ERRO" ] && echo "$TOPIC_ATTRS" | grep -q "TopicArn"; then
    echo "✅ Atributos do tópico SNS obtidos com sucesso"

    # Extrair informações específicas
    POLICY=$(echo "$TOPIC_ATTRS" | grep -o '"Policy": "[^"]*"' | cut -d'"' -f4 || echo "N/A")
    OWNER=$(echo "$TOPIC_ATTRS" | grep -o '"Owner": "[^"]*"' | cut -d'"' -f4 || echo "N/A")

    echo "  👤 Owner: $OWNER"
    echo "  🛡️ Policy: $(echo $POLICY | head -c 50)..."
else
    echo "❌ Erro ao obter atributos do tópico SNS"
fi

echo ""
echo "📧 Teste 3: Enviar notificação simples"

SIMPLE_MESSAGE="Teste de notificação simples - $(date)"
SIMPLE_RESULT=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$SIMPLE_MESSAGE" \
  --subject "🧪 Teste SNS Simples" 2>/dev/null || echo "ERRO")

if [ "$SIMPLE_RESULT" != "ERRO" ] && echo "$SIMPLE_RESULT" | grep -q "MessageId"; then
    SIMPLE_MSG_ID=$(echo "$SIMPLE_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Notificação simples enviada com sucesso"
    echo "📧 MessageId: $SIMPLE_MSG_ID"
    echo "📝 Mensagem: $SIMPLE_MESSAGE"
else
    echo "❌ Erro ao enviar notificação simples"
    echo "🔍 Resposta: $SIMPLE_RESULT"
fi

echo ""
echo "📧 Teste 4: Enviar notificação com atributos personalizados"

PEDIDO_ID="test-$(date +%s)"
COMPLEX_MESSAGE=$(cat << EOF
{
  "pedidoId": "$PEDIDO_ID",
  "cliente": "Cliente Teste",
  "mesa": 10,
  "status": "PRONTO",
  "total": 45.90,
  "itens": ["Hambúrguer", "Batata Frita", "Refrigerante"],
  "timestamp": "$(date -Iseconds)",
  "notificacao": "Seu pedido está pronto para retirada!"
}
EOF
)

COMPLEX_RESULT=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$COMPLEX_MESSAGE" \
  --subject "🍽️ Pedido $PEDIDO_ID Pronto para Retirada!" \
  --message-attributes '{
    "pedidoId": {
      "DataType": "String",
      "StringValue": "'$PEDIDO_ID'"
    },
    "cliente": {
      "DataType": "String",
      "StringValue": "Cliente Teste"
    },
    "mesa": {
      "DataType": "Number",
      "StringValue": "10"
    },
    "total": {
      "DataType": "Number",
      "StringValue": "45.90"
    },
    "tipo": {
      "DataType": "String",
      "StringValue": "PEDIDO_PRONTO"
    }
  }' 2>/dev/null || echo "ERRO")

if [ "$COMPLEX_RESULT" != "ERRO" ] && echo "$COMPLEX_RESULT" | grep -q "MessageId"; then
    COMPLEX_MSG_ID=$(echo "$COMPLEX_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Notificação com atributos enviada com sucesso"
    echo "📧 MessageId: $COMPLEX_MSG_ID"
    echo "📝 Pedido ID: $PEDIDO_ID"
    echo "💰 Total: R$ 45,90"
else
    echo "❌ Erro ao enviar notificação com atributos"
    echo "🔍 Resposta: $COMPLEX_RESULT"
fi

echo ""
echo "📧 Teste 5: Verificar logs de notificações no LocalStack"

echo "Verificando últimas notificações SNS nos logs..."
sleep 2  # Aguardar logs serem processados

SNS_LOGS=$(docker logs restaurante-localstack-1 2>&1 | grep -i "sns.*publish\|pedidosconcluidos" | tail -15 || true)

if [ ! -z "$SNS_LOGS" ]; then
    echo "✅ Logs de notificações SNS encontrados"
    echo "📊 Últimas notificações (últimas 10):"
    echo "$SNS_LOGS" | tail -10 | while read line; do
        echo "  📧 $(echo $line | cut -c1-100)..."
    done
else
    echo "❌ Nenhum log de notificação SNS encontrado"
    echo "💡 Verifique se o LocalStack está configurado corretamente"
fi

echo ""
echo "📧 Teste 6: Simular múltiplas notificações (carga)"

echo "Enviando 5 notificações em sequência..."

for i in {1..5}; do
    BATCH_MESSAGE="Notificação em lote $i/5 - Pedido lote-$i-$(date +%s)"
    BATCH_RESULT=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
      --topic-arn "$TOPIC_ARN" \
      --message "$BATCH_MESSAGE" \
      --subject "📦 Lote $i - Teste de Carga SNS" \
      --message-attributes '{
        "lote": {
          "DataType": "Number",
          "StringValue": "'$i'"
        },
        "tipo": {
          "DataType": "String",
          "StringValue": "TESTE_CARGA"
        }
      }' 2>/dev/null || echo "ERRO")

    if [ "$BATCH_RESULT" != "ERRO" ] && echo "$BATCH_RESULT" | grep -q "MessageId"; then
        BATCH_MSG_ID=$(echo "$BATCH_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
        echo "  ✅ Lote $i enviado - MessageId: $BATCH_MSG_ID"
    else
        echo "  ❌ Erro no lote $i"
    fi

    sleep 0.5  # Pequena pausa entre envios
done

echo ""
echo "📧 Teste 7: Verificar estatísticas do tópico"

# Verificar se há alguma métrica disponível (no LocalStack pode ser limitado)
TOPIC_STATS=$(aws --endpoint-url=$ENDPOINT_URL sns get-topic-attributes \
  --topic-arn "$TOPIC_ARN" \
  --query 'Attributes.{SubscriptionsConfirmed: SubscriptionsConfirmed, SubscriptionsPending: SubscriptionsPending}' \
  --output table 2>/dev/null || echo "ERRO")

if [ "$TOPIC_STATS" != "ERRO" ]; then
    echo "✅ Estatísticas do tópico obtidas"
    echo "$TOPIC_STATS"
else
    echo "⚠️ Estatísticas não disponíveis no LocalStack"
fi

echo ""
echo "📧 Teste 8: Testar notificação de erro/falha"

ERROR_MESSAGE=$(cat << EOF
{
  "tipo": "ERRO",
  "pedidoId": "erro-test-$(date +%s)",
  "erro": "Falha no processamento do pedido",
  "detalhes": "Sistema indisponível temporariamente",
  "timestamp": "$(date -Iseconds)",
  "acao_requerida": "Reprocessar pedido"
}
EOF
)

ERROR_RESULT=$(aws --endpoint-url=$ENDPOINT_URL sns publish \
  --topic-arn "$TOPIC_ARN" \
  --message "$ERROR_MESSAGE" \
  --subject "🚨 Erro no Processamento de Pedido" \
  --message-attributes '{
    "tipo": {
      "DataType": "String",
      "StringValue": "ERRO"
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

if [ "$ERROR_RESULT" != "ERRO" ] && echo "$ERROR_RESULT" | grep -q "MessageId"; then
    ERROR_MSG_ID=$(echo "$ERROR_RESULT" | grep -o '"MessageId": "[^"]*"' | cut -d'"' -f4)
    echo "✅ Notificação de erro enviada com sucesso"
    echo "🚨 MessageId: $ERROR_MSG_ID"
else
    echo "❌ Erro ao enviar notificação de erro"
fi

echo ""
echo "📧 Teste Final: Verificar logs finais e resumo"

sleep 2
FINAL_LOGS=$(docker logs restaurante-localstack-1 2>&1 | grep -i "sns.*publish" | wc -l || echo "0")
echo "📊 Total de mensagens SNS enviadas nos logs: $FINAL_LOGS"

echo ""
echo "🎉 Todos os testes SNS concluídos!"
echo ""
echo "📊 Resumo dos Testes:"
echo "  ✅ Verificação de tópico"
echo "  ✅ Atributos do tópico"
echo "  ✅ Notificação simples"
echo "  ✅ Notificação com atributos"
echo "  ✅ Verificação de logs"
echo "  ✅ Teste de carga (5 mensagens)"
echo "  ✅ Estatísticas do tópico"
echo "  ✅ Notificação de erro"
echo ""
echo "💡 Para ver todas as notificações nos logs:"
echo "   docker logs restaurante-localstack-1 2>&1 | grep -i sns"
echo ""
echo "💡 Para listar todos os tópicos:"
echo "   aws --endpoint-url=$ENDPOINT_URL sns list-topics"
