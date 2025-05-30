#!/bin/bash

# Script para mostrar status completo do sistema

set -e

echo "📊 Status Completo do Sistema de Restaurante"

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ETH0_IP" ]; then
  ETH0_IP="localhost"
fi

ENDPOINT_BASE="http://$ETH0_IP:4566"

echo "🌐 Endpoint LocalStack: $ENDPOINT_BASE"

# Encontrar API Gateway
API_ID=$(aws --endpoint-url=$ENDPOINT_BASE apigateway get-rest-apis --query 'items[0].id' --output text 2>/dev/null)
if [ "$API_ID" != "None" ] && [ ! -z "$API_ID" ]; then
    FULL_ENDPOINT="$ENDPOINT_BASE/restapis/$API_ID/local/_user_request_/pedidos"
    echo "🔗 API Endpoint: $FULL_ENDPOINT"
fi

echo ""
echo "📋 Dados no DynamoDB:"
echo "Pedidos armazenados:"
aws --endpoint-url=$ENDPOINT_BASE dynamodb scan --table-name Pedidos --query 'Items[].{ID:id.S,Cliente:cliente.S,Mesa:mesa.N,Status:status.S,CriadoEm:criadoEm.S}' --output table 2>/dev/null || echo "Nenhum pedido encontrado"

echo ""
echo "📬 Mensagens na fila SQS:"
QUEUE_URL=$(aws --endpoint-url=$ENDPOINT_BASE sqs get-queue-url --queue-name fila-pedidos --query 'QueueUrl' --output text 2>/dev/null)
if [ "$QUEUE_URL" != "None" ] && [ ! -z "$QUEUE_URL" ]; then
    MESSAGES=$(aws --endpoint-url=$ENDPOINT_BASE sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)
    echo "Mensagens pendentes: $MESSAGES"
else
    echo "Fila não encontrada"
fi

echo ""
echo "🗃️ Arquivos no S3:"
aws --endpoint-url=$ENDPOINT_BASE s3 ls s3://comprovantes/ 2>/dev/null || echo "Bucket vazio ou não acessível"

echo ""
echo "⚡ Status das Lambdas:"
echo "CriarPedido:"
aws --endpoint-url=$ENDPOINT_BASE lambda get-function --function-name CriarPedido --query 'Configuration.{Estado:State,UltimaModificacao:LastModified,Timeout:Timeout}' --output table 2>/dev/null

echo ""
echo "ProcessarPedido:"
aws --endpoint-url=$ENDPOINT_BASE lambda get-function --function-name ProcessarPedido --query 'Configuration.{Estado:State,UltimaModificacao:LastModified,Timeout:Timeout}' --output table 2>/dev/null

echo ""
echo "🔄 Mapeamentos de Eventos:"
aws --endpoint-url=$ENDPOINT_BASE lambda list-event-source-mappings --query 'EventSourceMappings[].{FuncaoLambda:FunctionArn,Estado:State,FonteEvento:EventSourceArn}' --output table 2>/dev/null

echo ""
echo "📈 Estatísticas do Sistema:"
TOTAL_PEDIDOS=$(aws --endpoint-url=$ENDPOINT_BASE dynamodb scan --table-name Pedidos --select COUNT --query 'Count' --output text 2>/dev/null || echo "0")
PEDIDOS_PROCESSADOS=$(aws --endpoint-url=$ENDPOINT_BASE dynamodb scan --table-name Pedidos --filter-expression "#s = :status" --expression-attribute-names '{"#s":"status"}' --expression-attribute-values '{":status":{"S":"PROCESSADO"}}' --select COUNT --query 'Count' --output text 2>/dev/null || echo "0")
ARQUIVOS_PDF=$(aws --endpoint-url=$ENDPOINT_BASE s3 ls s3://comprovantes/ 2>/dev/null | wc -l || echo "0")

echo "Total de pedidos criados: $TOTAL_PEDIDOS"
echo "Pedidos processados: $PEDIDOS_PROCESSADOS"
echo "Arquivos PDF gerados: $ARQUIVOS_PDF"

echo ""
echo "✅ Sistema funcionando corretamente!"
echo ""
echo "🧪 Comandos úteis:"
echo "- Testar sistema: ./testar-sistema.sh"
echo "- Ver logs: docker logs \$(docker ps -q --filter 'name=localstack')"
echo "- Limpar recursos: ./remover-recursos-aws.sh"
echo ""
echo "📝 Exemplo de uso com curl:"
echo "curl -X POST '$FULL_ENDPOINT' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"cliente\":\"João Silva\",\"mesa\":5,\"itens\":[{\"nome\":\"Hambúrguer\",\"quantidade\":1,\"preco\":25.50}]}'"
