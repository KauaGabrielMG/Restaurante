import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { SNSClient, PublishCommand } from '@aws-sdk/client-sns';
import { gerarPDF } from './gerarPDF';

interface SQSEvent {
  Records: Array<{
    body: string;
    messageId: string;
  }>;
}

interface Pedido {
  id: string;
  cliente: string;
  itens: Array<{ nome: string; quantidade: number; preco: number }>;
  mesa: number;
  status: string;
  criadoEm: string;
  atualizadoEm?: string;
}

// Configuração dos clientes AWS para LocalStack
const dynamoClient = new DynamoDBClient({
  region: 'us-east-1',
  endpoint: process.env.LOCALSTACK_HOSTNAME
    ? `http://${process.env.LOCALSTACK_HOSTNAME}:4566`
    : 'http://172.18.0.2:4566',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test',
  },
});

const s3Client = new S3Client({
  region: 'us-east-1',
  endpoint: process.env.LOCALSTACK_HOSTNAME
    ? `http://${process.env.LOCALSTACK_HOSTNAME}:4566`
    : 'http://172.18.0.2:4566',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test',
  },
  forcePathStyle: true,
});

const snsClient = new SNSClient({
  region: 'us-east-1',
  endpoint: process.env.LOCALSTACK_HOSTNAME
    ? `http://${process.env.LOCALSTACK_HOSTNAME}:4566`
    : 'http://172.18.0.2:4566',
  credentials: {
    accessKeyId: 'test',
    secretAccessKey: 'test',
  },
});

const TOPIC_ARN = 'arn:aws:sns:us-east-1:000000000000:PedidosConcluidos';

export const handler = async (event: SQSEvent) => {
  console.log(
    '📨 Processando mensagens da fila SQS:',
    JSON.stringify(event, null, 2),
  );

  // Processar cada mensagem da fila
  for (const record of event.Records) {
    try {
      const pedido: Pedido = JSON.parse(record.body);
      console.log(`🔄 Processando pedido: ${pedido.id}`);

      // 1. Gerar PDF do comprovante
      console.log('📄 Gerando PDF do comprovante...');
      const pdfBuffer = gerarPDF(pedido);

      // 2. Salvar PDF no S3
      const s3Key = `${pedido.id}.pdf`;
      console.log(`📤 Salvando PDF no S3: ${s3Key}`);

      await s3Client.send(
        new PutObjectCommand({
          Bucket: 'comprovantes',
          Key: s3Key,
          Body: pdfBuffer,
          ContentType: 'application/pdf',
        }),
      );

      console.log(`✅ PDF salvo no S3: s3://comprovantes/${s3Key}`);

      // 3. Calcular total do pedido
      const total = pedido.itens.reduce(
        (sum, item) => sum + item.quantidade * item.preco,
        0,
      );

      // 4. Enviar notificações via SNS
      console.log('📧 Enviando notificações via SNS...');

      // Notificação adicional para cozinha/staff
      const mensagemCozinha = JSON.stringify({
        tipo: 'ALERTA_COZINHA',
        pedidoId: pedido.id,
        mesa: pedido.mesa,
        cliente: pedido.cliente,
        quantidadeItens: pedido.itens.length,
        tempoProcessamento: new Date().toISOString(),
        acao: 'Pedido processado e comprovante gerado',
      });

      const snsParamsCozinha = {
        TopicArn: TOPIC_ARN,
        Message: mensagemCozinha,
        Subject: '👨‍🍳 Pedido Processado - Alerta Cozinha',
        MessageAttributes: {
          pedidoId: {
            DataType: 'String',
            StringValue: pedido.id,
          },
          tipo: {
            DataType: 'String',
            StringValue: 'ALERTA_COZINHA',
          },
          mesa: {
            DataType: 'Number',
            StringValue: pedido.mesa.toString(),
          },
          prioridade: {
            DataType: 'String',
            StringValue: 'NORMAL',
          },
        },
      };
      const snsResultCozinha = await snsClient.send(
        new PublishCommand(snsParamsCozinha),
      );
      console.log(
        '✅ Notificação SNS para cozinha enviada:',
        JSON.stringify(
          {
            MessageId: snsResultCozinha.MessageId,
            TopicArn: TOPIC_ARN,
            Subject: '👨‍🍳 Pedido Processado - Alerta Cozinha',
            Tipo: 'ALERTA_COZINHA',
            PedidoId: pedido.id,
            Mesa: pedido.mesa,
          },
          null,
          2,
        ),
      );

      // Notificação principal - Pedido Pronto
      const mensagemPrincipal = JSON.stringify({
        pedidoId: pedido.id,
        cliente: pedido.cliente,
        mesa: pedido.mesa,
        status: 'PRONTO',
        total: total.toFixed(2),
        itens: pedido.itens.map((item) => ({
          nome: item.nome,
          quantidade: item.quantidade,
          preco: item.preco,
        })),
        timestamp: new Date().toISOString(),
        comprovanteS3: s3Key,
        mensagem: `Seu pedido está pronto para retirada na mesa ${pedido.mesa}!`,
      });

      const snsParamsPrincipal = {
        TopicArn: TOPIC_ARN,
        Message: mensagemPrincipal,
        Subject: '🍽️ Pedido Pronto para Retirada!',
        MessageAttributes: {
          pedidoId: {
            DataType: 'String',
            StringValue: pedido.id,
          },
          cliente: {
            DataType: 'String',
            StringValue: pedido.cliente,
          },
          mesa: {
            DataType: 'Number',
            StringValue: pedido.mesa.toString(),
          },
          total: {
            DataType: 'Number',
            StringValue: total.toFixed(2),
          },
          status: {
            DataType: 'String',
            StringValue: 'PRONTO',
          },
          tipo: {
            DataType: 'String',
            StringValue: 'PEDIDO_PRONTO',
          },
        },
      };
      const snsResult = await snsClient.send(
        new PublishCommand(snsParamsPrincipal),
      );
      console.log(
        '✅ Notificação SNS principal enviada:',
        JSON.stringify(
          {
            MessageId: snsResult.MessageId,
            TopicArn: TOPIC_ARN,
            Subject: '🍽️ Pedido Pronto para Retirada!',
            PedidoId: pedido.id,
            Cliente: pedido.cliente,
            Mesa: pedido.mesa,
            Total: total.toFixed(2),
          },
          null,
          2,
        ),
      );

      // 5. Atualizar status no DynamoDB
      console.log('🔄 Atualizando status no DynamoDB...');

      await dynamoClient.send(
        new UpdateItemCommand({
          TableName: 'Pedidos',
          Key: {
            id: { S: pedido.id },
          },
          UpdateExpression:
            'SET #status = :status, atualizadoEm = :atualizadoEm, comprovanteS3 = :s3Key',
          ExpressionAttributeNames: {
            '#status': 'status',
          },
          ExpressionAttributeValues: {
            ':status': { S: 'PROCESSADO' },
            ':atualizadoEm': { S: new Date().toISOString() },
            ':s3Key': { S: s3Key },
          },
        }),
      );

      console.log(`✅ Pedido ${pedido.id} processado com sucesso!`);
    } catch (error) {
      console.error(
        `❌ Erro ao processar mensagem ${record.messageId}:`,
        error,
      );

      // Em um ambiente real, você poderia enviar para uma Dead Letter Queue (DLQ)
      // Por enquanto, apenas logamos o erro e continuamos com outras mensagens
      continue;
    }
  }

  return {
    statusCode: 200,
    body: JSON.stringify({
      sucesso: true,
      mensagem: `${event.Records.length} pedidos processados com sucesso!`,
    }),
  };
};
