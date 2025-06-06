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

      // 4. Enviar notificação via SNS
      console.log('📧 Enviando notificação via SNS...');

      const mensagem = `Pedido ${
        pedido.id
      } foi processado e está pronto! Cliente: ${pedido.cliente}, Mesa: ${
        pedido.mesa
      }, Total: R$ ${total.toFixed(2)}`;

      const snsParams = {
        TopicArn: TOPIC_ARN,
        Message: mensagem,
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
        },
      };

      const snsResult = await snsClient.send(new PublishCommand(snsParams));
      console.log('✅ Notificação SNS enviada:', {
        MessageId: snsResult.MessageId,
        TopicArn: TOPIC_ARN,
        Subject: '🍽️ Pedido Pronto para Retirada!',
        Message: mensagem,
      });

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
