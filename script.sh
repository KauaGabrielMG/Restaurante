#!/bin/bash

set -e

# Função para tratamento de erros
handle_error() {
    echo "❌ Erro na linha $1: $2"
    echo "🧹 Limpando recursos criados parcialmente..."
    cleanup_on_error
    exit 1
}

# Função para limpeza em caso de erro
cleanup_on_error() {
    echo "🧼 Removendo artefatos criados..."
    rm -f criarPedido.zip processarPedido.zip
    rm -f criar-pedido.js processar-pedido.js gerarPDF.js

    if [ ! -z "$LOCALSTACK_ENDPOINT" ]; then
        echo "🗑️ Tentando remover recursos AWS criados..."
        aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb delete-table --table-name Pedidos 2>/dev/null || true
        aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs delete-queue --queue-url "http://$ETH0_IP:4566/000000000000/fila-pedidos" 2>/dev/null || true
        aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 rb s3://comprovantes --force 2>/dev/null || true
        if [ ! -z "$API_ID" ]; then
            aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null || true
        fi
    fi
}

# Configurar trap para capturar erros
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "🚀 Iniciando deploy do Sistema de Restaurante..."

# Verificar se o LocalStack está rodando
echo "🔍 Verificando se o LocalStack está rodando..."
if ! docker ps | grep -q localstack; then
    echo "❌ LocalStack não está rodando!"
    echo "💡 Execute primeiro: docker compose up -d"
    exit 1
fi

echo "📦 Instalando dependências..."
if ! npm install; then
    echo "❌ Falha ao instalar dependências npm"
    exit 1
fi

# Obter IP da interface eth0
echo "🌐 Obtendo IP da interface de rede..."

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
    echo "❌ Não foi possível obter o IP da máquina"
    echo "💡 Usando localhost como fallback..."
    ETH0_IP="127.0.0.1"
    echo "⚠️  Aviso: Usando localhost pode causar problemas de conectividade"
else
    echo "✅ IP da máquina encontrado: $ETH0_IP"
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
# Incluir node_modules no ZIP para resolver dependências
zip -r criarPedido.zip criar-pedido.js node_modules/ > /dev/null
zip -r processarPedido.zip processar-pedido.js gerarPDF.js node_modules/ > /dev/null
if [ $? -ne 0 ]; then
  echo "❌ Erro ao empacotar as funções Lambda. Verifique os arquivos criados."
  echo "Certifique que tenha o zip instalado."
  echo "Você pode instalar o zip com: sudo apt-get install zip"
  exit 1
fi
echo "✅ Lambdas empacotadas!"

echo "🔧 Criando recursos AWS no LocalStack..."
# Criação da tabela DynamoDB
echo "  📋 Criando tabela DynamoDB: Pedidos"
aws --endpoint-url=$LOCALSTACK_ENDPOINT dynamodb create-table \
  --table-name Pedidos \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
	--billing-mode PAY_PER_REQUEST \
	--region us-east-1 > /dev/null 2>&1 || true

# Criação da fila SQS
echo "  📬 Criando fila SQS: fila-pedidos"
aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs create-queue --queue-name fila-pedidos > /dev/null 2>&1 || true

# Criação do bucket S3
echo "  🗃️ Criando bucket S3: comprovantes"
aws --endpoint-url=$LOCALSTACK_ENDPOINT s3 mb s3://comprovantes > /dev/null 2>&1 || true

echo "🚀 Criando funções Lambda..."
echo "  🔧 Criando função CriarPedido"
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name CriarPedido \
  --runtime nodejs18.x \
  --handler criar-pedido.handler \
  --zip-file fileb://criarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role > /dev/null 2>&1

echo "  🔧 Criando função ProcessarPedido"
aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-function \
  --function-name ProcessarPedido \
  --runtime nodejs18.x \
  --handler processar-pedido.handler \
  --zip-file fileb://processarPedido.zip \
  --role arn:aws:iam::000000000000:role/lambda-role > /dev/null 2>&1

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
  --authorization-type "NONE" > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$PEDIDO_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:CriarPedido/invocations > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda add-permission \
  --function-name CriarPedido \
  --statement-id apigateway-test-permission \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/pedidos" > /dev/null 2>&1

aws --endpoint-url=$LOCALSTACK_ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name local > /dev/null 2>&1

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
  --enabled > /dev/null 2>&1

echo ""
echo "🎉 DEPLOY CONCLUÍDO COM SUCESSO!"
echo "🔗 Endpoint disponível:"
echo "POST http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos"
echo "exemplo: curl -X POST http://$ETH0_IP:4566/restapis/$API_ID/local/_user_request_/pedidos -d @evento-exemplo.json -H 'Content-Type: application/json'"
echo "Use o arquivo 'evento-exemplo.json' com curl ou Postman para testar"
