#!/bin/bash

set -e
# docker run --rm -it -p 4566:4566 -p 4510-4559:4510-4559 localstack/localstack
# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ETH0_IP" ]; then
  echo "❌ Não foi possível obter o IP da interface eth0"
  exit 1
fi

echo "🌐 Usando IP da eth0: $ETH0_IP"
LOCALSTACK_ENDPOINT="http://$ETH0_IP:4566"
echo "LocalStack Endpoint: $LOCALSTACK_ENDPOINT"

echo "🧼 Limpando artefatos anteriores..."
rm -f criarPedido.zip processarPedido.zip

echo "📦 Compilando arquivos Lambda individuais..."
tsc criar-pedido.ts processar-pedido.ts gerarPDF.ts
if [ $? -ne 0 ]; then
  echo "❌ Erro na compilação do TypeScript. Verifique os arquivos .ts."
  exit 1
fi
echo "📦 Empacotando funções Lambda..."
zip -r criarPedido.zip criar-pedido.js > /dev/null
zip -r processarPedido.zip processar-pedido.js gerarPDF.js > /dev/null
if [ $? -ne 0 ]; then
  echo "❌ Erro ao empacotar as funções Lambda. Verifique os arquivos criados."
  echo "Certifique que tenha o zip instalado."
  echo "Você pode instalar o zip com: sudo apt-get install zip"
  exit 1
fi
echo "✅ Lambdas empacotadas!"

echo "🔧 Criando recursos AWS no LocalStack..."
# Criação da tabela DynamoDB
aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
	--billing-mode PAY_PER_REQUEST \
	--region us-east-1 > /dev/null || true

# Criação da fila SQS
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue --queue-name fila-pedidos || true

# Criação do bucket S3
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://comprovantes || true

echo "🚀 Criando funções Lambda..."

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name CriarPedido \
  --runtime nodejs18.x \
  --handler criar-pedido.handler \
  --zip-file fileb://criarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name ProcessarPedido \
  --runtime nodejs18.x \
  --handler processar-pedido.handler \
  --zip-file fileb://processarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role

echo "🌐 Criando API Gateway e integrando com Lambda CriarPedido..."

# API
API_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-rest-api \
  --name "RestauranteAPI" \
  --query 'id' \
  --output text)

ROOT_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[0].id' \
  --output text)

PEDIDO_RESOURCE_ID=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part pedidos \
  --query 'id' \
  --output text)

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --authorization-type "NONE"

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:CriarPedido/invocations

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda add-permission \
  --function-name CriarPedido \
  --statement-id apigateway-test-permission \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/pedidos"

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name local > /dev/null

echo "🔗 Conectando SQS com Lambda ProcessarPedido..."

QUEUE_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-url --queue-name fila-pedidos --query 'QueueUrl' --output text)
QUEUE_ARN=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-name QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-event-source-mapping \
  --function-name ProcessarPedido \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  --enabled

echo ""
echo "🎉 DEPLOY CONCLUÍDO COM SUCESSO!"
echo "🔗 Endpoint disponível:"
echo "POST http://localhost:4566/restapis/$API_ID/local/_user_request_/pedidos"
echo "Use o arquivo 'evento-exemplo.json' com curl ou Postman para testar."
echo "exemplo: curl -X POST http://localhost:4566/restapis/$API_ID/local/_user_request_/pedidos -d @evento-exemplo.json -H 'Content-Type: application/json'"
