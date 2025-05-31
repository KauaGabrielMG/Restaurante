#!/bin/bash

# Script para testar permissões SNS especificamente

set -e

echo "🔐 Testando Permissões SNS..."

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ETH0_IP" ]; then
  ETH0_IP="localhost"
fi

ENDPOINT_BASE="http://$ETH0_IP:4566"
echo "🌐 Endpoint: $ENDPOINT_BASE"

echo ""
echo "🔍 1. Verificando tópico SNS..."

TOPIC_ARN="arn:aws:sns:us-east-1:000000000000:PedidosConcluidos"

# Verificar se o tópico existe
if aws --endpoint-url=$ENDPOINT_BASE sns get-topic-attributes --topic-arn $TOPIC_ARN > /dev/null 2>&1; then
    echo "✅ Tópico SNS encontrado: $TOPIC_ARN"
else
    echo "❌ Tópico SNS não encontrado!"
    echo "Execute './script.sh' primeiro para criar os recursos"
    exit 1
fi

echo ""
echo "🔍 2. Verificando função Lambda ProcessarPedido..."

if aws --endpoint-url=$ENDPOINT_BASE lambda get-function --function-name ProcessarPedido > /dev/null 2>&1; then
    echo "✅ Função Lambda ProcessarPedido encontrada"

    # Verificar configuração da função
    LAMBDA_ROLE=$(aws --endpoint-url=$ENDPOINT_BASE lambda get-function-configuration \
        --function-name ProcessarPedido \
        --query 'Role' --output text)
    echo "🔧 Role da Lambda: $LAMBDA_ROLE"
else
    echo "❌ Função Lambda ProcessarPedido não encontrada!"
    exit 1
fi

echo ""
echo "🔍 3. Verificando role IAM da Lambda..."

if aws --endpoint-url=$ENDPOINT_BASE iam get-role --role-name ProcessarPedidoRole > /dev/null 2>&1; then
    echo "✅ Role ProcessarPedidoRole encontrada"

    # Listar policies anexadas à role
    echo "📋 Policies anexadas à role:"
    aws --endpoint-url=$ENDPOINT_BASE iam list-attached-role-policies \
        --role-name ProcessarPedidoRole \
        --query 'AttachedPolicies[].PolicyName' --output table
else
    echo "⚠️ Role ProcessarPedidoRole não encontrada (usando role padrão)"
fi

echo ""
echo "🔍 4. Testando publicação manual no SNS..."

# Teste de publicação direta
echo "Publicando mensagem de teste no SNS..."

TEST_MESSAGE="Teste de permissão: Sistema funcionando corretamente!"

PUBLISH_RESULT=$(aws --endpoint-url=$ENDPOINT_BASE sns publish \
    --topic-arn $TOPIC_ARN \
    --message "$TEST_MESSAGE" \
    --subject "🧪 Teste de Permissão SNS" \
    --query 'MessageId' --output text 2>&1)

if [[ $PUBLISH_RESULT == *"error"* ]] || [[ $PUBLISH_RESULT == *"denied"* ]]; then
    echo "❌ Erro ao publicar no SNS: $PUBLISH_RESULT"
    echo "Verificando permissões..."

    # Verificar política do tópico
    echo ""
    echo "📋 Política do tópico SNS:"
    aws --endpoint-url=$ENDPOINT_BASE sns get-topic-attributes \
        --topic-arn $TOPIC_ARN \
        --query 'Attributes.Policy' --output text || echo "Nenhuma política encontrada"
else
    echo "✅ Publicação no SNS bem-sucedida!"
    echo "📧 MessageId: $PUBLISH_RESULT"
fi

echo ""
echo "🔍 5. Testando integração Lambda + SNS via SQS..."

# Criar mensagem de teste para simular SQS
cat > test-sqs-message.json << EOF
{
  "Records": [
    {
      "body": "{\"id\":\"test-$(date +%s)\",\"cliente\":\"Cliente Teste\",\"mesa\":99,\"itens\":[{\"nome\":\"Item Teste\",\"quantidade\":1,\"preco\":10.00}],\"status\":\"CRIADO\",\"criadoEm\":\"$(date -Iseconds)\"}",
      "messageId": "test-message-id"
    }
  ]
}
EOF

echo "Invocando Lambda ProcessarPedido com mensagem de teste..."

# Invocar Lambda diretamente para testar SNS
aws --endpoint-url=$ENDPOINT_BASE lambda invoke \
    --function-name ProcessarPedido \
    --payload file://test-sqs-message.json \
    response-sns-test.json > /dev/null 2>&1

if [ -f response-sns-test.json ]; then
    echo "📋 Resposta da Lambda:"
    cat response-sns-test.json
    echo ""

    # Verificar se houve erro
    if grep -q "errorMessage" response-sns-test.json; then
        echo "❌ Lambda retornou erro:"
        grep "errorMessage" response-sns-test.json
    else
        echo "✅ Lambda executou sem erros"
    fi
else
    echo "❌ Falha ao invocar Lambda"
fi

echo ""
echo "🔍 6. Verificando logs recentes do LocalStack..."

# Verificar logs para SNS
CONTAINER_ID=$(docker ps -q --filter "name=localstack" 2>/dev/null)
if [ ! -z "$CONTAINER_ID" ]; then
    echo "📋 Logs relacionados ao SNS (últimos 20):"
    docker logs --tail=20 "$CONTAINER_ID" 2>&1 | grep -i "sns\|publish\|topic" || echo "Nenhum log de SNS encontrado"
else
    echo "⚠️ Container LocalStack não encontrado"
fi

echo ""
echo "🔍 7. Resumo das verificações:"

# Verificar todos os componentes necessários
echo "📊 Status dos componentes:"

# Tópico SNS
if aws --endpoint-url=$ENDPOINT_BASE sns get-topic-attributes --topic-arn $TOPIC_ARN > /dev/null 2>&1; then
    echo "✅ Tópico SNS: OK"
else
    echo "❌ Tópico SNS: FALHA"
fi

# Lambda ProcessarPedido
if aws --endpoint-url=$ENDPOINT_BASE lambda get-function --function-name ProcessarPedido > /dev/null 2>&1; then
    echo "✅ Lambda ProcessarPedido: OK"
else
    echo "❌ Lambda ProcessarPedido: FALHA"
fi

# Role IAM
if aws --endpoint-url=$ENDPOINT_BASE iam get-role --role-name ProcessarPedidoRole > /dev/null 2>&1; then
    echo "✅ Role IAM: OK"
else
    echo "⚠️ Role IAM: Usando padrão do LocalStack"
fi

# Limpeza
rm -f test-sqs-message.json response-sns-test.json

echo ""
echo "💡 Dicas para resolver problemas de permissão:"
echo "1. Execute './script.sh' novamente para recriar as permissões"
echo "2. Verifique se o LocalStack está rodando: docker ps | grep localstack"
echo "3. Reinicie o LocalStack se necessário: docker compose restart"
echo "4. No LocalStack, muitas permissões são simuladas e podem funcionar mesmo sem configuração explícita"

echo ""
echo "✅ Teste de permissões SNS concluído!"
