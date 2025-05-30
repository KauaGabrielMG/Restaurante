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

  aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda add-permission \
  --function-name CriarPedido \
  --statement-id apigateway-test-permission \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/pedidos" > /dev/null 2>&1

  aws --endpoint-url=$LOCALSTACK_ENDPOINT lambda create-event-source-mapping \
  --function-name ProcessarPedido \
  --event-source-arn "$QUEUE_ARN" \
  --batch-size 1 \
  --enabled > /dev/null 2>&1
