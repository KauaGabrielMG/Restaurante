#!/bin/bash

# Script para diagnosticar problemas específicos da Lambda

set -e

echo "🔍 Diagnóstico Detalhado da Lambda"

# Obter IP da interface eth0
ETH0_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
if [ -z "$ETH0_IP" ]; then
  ETH0_IP="localhost"
fi

ENDPOINT_BASE="http://$ETH0_IP:4566"
echo "🌐 Endpoint: $ENDPOINT_BASE"

echo ""
echo "🔍 1. Verificando arquivos compilados..."

if [ ! -f criar-pedido.js ]; then
    echo "❌ criar-pedido.js não existe. Compilando..."
    tsc criar-pedido.ts
fi

if [ -f criar-pedido.js ]; then
    echo "✅ criar-pedido.js existe"
    echo "Verificando sintaxe JavaScript..."
    node -c criar-pedido.js && echo "✅ Sintaxe OK" || echo "❌ Erro de sintaxe"

    echo "Verificando export..."
    if grep -q "exports.handler" criar-pedido.js; then
        echo "✅ Export handler encontrado"
    else
        echo "❌ Export handler não encontrado"
    fi
else
    echo "❌ Falha ao criar criar-pedido.js"
    exit 1
fi

echo ""
echo "🔍 2. Verificando dependências no package.json..."
if grep -q '"aws-sdk"' package.json; then
    echo "✅ aws-sdk está no package.json"
else
    echo "❌ aws-sdk não encontrado no package.json"
fi

if grep -q '"uuid"' package.json; then
    echo "✅ uuid está no package.json"
else
    echo "❌ uuid não encontrado no package.json"
fi

echo ""
echo "🔍 3. Verificando estrutura do ZIP..."
if [ -f criarPedido.zip ]; then
    echo ""
    echo "Verificando se node_modules está incluído..."
    if (unzip -l criarPedido.zip | grep -q node_modules) > /dev/null 2>&1; then
        echo "✅ node_modules incluído no ZIP"
    else
        echo "❌ node_modules não incluído no ZIP"
        echo "Recriando ZIP com dependências..."

        # Recriar ZIP incluindo dependências
        rm -f criarPedido.zip
        zip -r criarPedido.zip criar-pedido.js node_modules/ > /dev/null
        echo "✅ ZIP recriado com node_modules"
    fi
else
    echo "❌ criarPedido.zip não existe"
    exit 1
fi

echo ""
echo "🔍 4. Testando configuração da Lambda..."

# Verificar configuração atual
echo "Configuração atual da Lambda:"
aws --endpoint-url=$ENDPOINT_BASE lambda get-function-configuration \
  --function-name CriarPedido \
  --query '{Runtime:Runtime,Handler:Handler,Timeout:Timeout,MemorySize:MemorySize}' \
  --output table

echo ""
echo "🔍 5. Atualizando código da Lambda..."

# Atualizar função com o ZIP corrigido
aws --endpoint-url=$ENDPOINT_BASE lambda update-function-code \
  --function-name CriarPedido \
  --zip-file fileb://criarPedido.zip > /dev/null

echo "✅ Código da Lambda atualizado"

# Aguardar a atualização ser concluída
echo "Aguardando atualização ser concluída..."
sleep 5

# Aumentar timeout da Lambda
echo "Aumentando timeout da Lambda para 30 segundos..."
aws --endpoint-url=$ENDPOINT_BASE lambda update-function-configuration \
  --function-name CriarPedido \
  --timeout 30 > /dev/null 2>&1 || echo "⚠️ Configuração de timeout pode estar em conflito"

echo "✅ Configuração da Lambda atualizada"

echo ""
echo "🔍 6. Testando Lambda diretamente com payload simples..."

# Criar payload mínimo usando formato correto
echo '{"body":"{\"cliente\":\"Test\",\"mesa\":1,\"itens\":[{\"nome\":\"Item\",\"quantidade\":1,\"preco\":10}]}","httpMethod":"POST"}' > test-simple.json

# Testar invocação sem flag problemática
echo "Invocando Lambda..."
aws --endpoint-url=$ENDPOINT_BASE lambda invoke \
  --function-name CriarPedido \
  --payload file://test-simple.json \
  response-test.json

echo ""
echo "Resposta:"
cat response-test.json
echo ""

# Verificar logs da Lambda
echo ""
echo "🔍 7. Verificando logs da Lambda..."
echo "Logs do LocalStack (últimas 20 linhas):"
CONTAINER_ID=$(docker ps -q --filter "name=localstack")
if [ ! -z "$CONTAINER_ID" ]; then
    docker logs --tail 20 "$CONTAINER_ID" | grep -i lambda || echo "Nenhum log de Lambda encontrado"
fi

# Limpeza
rm -f test-simple.json response-test.json

echo ""
echo "🔧 Sugestões de correção:"
echo "1. Se ainda houver erro, verifique se o IP $ETH0_IP está correto"
echo "2. Verifique se todas as dependências estão instaladas: npm install"
echo "3. Recompile tudo: tsc *.ts"
echo "4. Redeploy completo: ./remover-recursos-aws.sh && ./script.sh"
