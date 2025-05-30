import {DynamoDB, SQS} from 'aws-sdk';
import { v4 as uuidv4 } from 'uuid';

// Usar endpoint fixo para evitar problemas na Lambda
const ETH0_IP = process.env.ETH0_IP || '192.168.10.100';
const ENDPOINT = `http://${ETH0_IP}:4566`;

const dynamodb = new DynamoDB.DocumentClient({ endpoint: ENDPOINT });
const sqs = new SQS({ endpoint: ENDPOINT });

interface PedidoData {
  cliente: string;
  itens: Array<{ nome: string; quantidade: number; preco: number }>;
  mesa: number;
}

interface APIGatewayEvent {
  body?: string;
  headers?: { [key: string]: string };
  httpMethod?: string;
  path?: string;
  queryStringParameters?: { [key: string]: string } | null;
}

// Export nomeado para compatibilidade com Lambda
export const handler = async (event: APIGatewayEvent) => {
  try {
    console.log('Event received:', JSON.stringify(event, null, 2));

    // Validação básica do evento
    if (!event || !event.body) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          erro: 'Requisição inválida',
          mensagem: 'Corpo da requisição é obrigatório'
        }),
      };
    }

    // Parse do JSON com tratamento de erro
    let dados: PedidoData;
    try {
      dados = JSON.parse(event.body);
    } catch (parseError) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          erro: 'JSON inválido',
          mensagem: 'Formato do JSON está incorreto'
        }),
      };
    }

    // Validação dos campos obrigatórios
    if (!dados.cliente || !dados.itens || !dados.mesa) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          erro: 'Dados incompletos',
          mensagem: 'Campos obrigatórios: cliente, itens, mesa'
        }),
      };
    }

    // Validação dos itens
    if (!Array.isArray(dados.itens) || dados.itens.length === 0) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          erro: 'Itens inválidos',
          mensagem: 'É necessário pelo menos um item no pedido'
        }),
      };
    }

    const id = uuidv4();

    // Salvar no DynamoDB com tratamento de erro
    try {
      await dynamodb.put({
        TableName: 'Pedidos',
        Item: {
          id,
          cliente: dados.cliente,
          itens: dados.itens,
          mesa: dados.mesa,
          status: 'Pendente',
          criadoEm: new Date().toISOString(),
        },
      }).promise();
    } catch (dynamoError) {
      console.error('Erro ao salvar no DynamoDB:', dynamoError);
      return {
        statusCode: 500,
        body: JSON.stringify({
          erro: 'Erro interno',
          mensagem: 'Falha ao salvar pedido no banco de dados'
        }),
      };
    }    // Enviar mensagem para SQS com tratamento de erro
    try {
      await sqs.sendMessage({
        QueueUrl: `http://${ETH0_IP}:4566/000000000000/fila-pedidos`,
        MessageBody: JSON.stringify({ id, timestamp: new Date().toISOString() })
      }).promise();
    } catch (sqsError) {
      console.error('Erro ao enviar para SQS:', sqsError);
      // Aqui você pode decidir se quer reverter a operação do DynamoDB
      // ou apenas logar o erro e continuar
      return {
        statusCode: 500,
        body: JSON.stringify({
          erro: 'Erro interno',
          mensagem: 'Pedido salvo, mas falha ao processar fila'
        }),
      };
    }

    return {
      statusCode: 201,
      body: JSON.stringify({
        sucesso: true,
        mensagem: 'Pedido criado com sucesso!',
        id
      }),
    };

  } catch (error) {
    console.error('Erro inesperado:', error);    return {
      statusCode: 500,
      body: JSON.stringify({
        erro: 'Erro interno do servidor',
        mensagem: 'Ocorreu um erro inesperado ao processar o pedido'
      }),
    };
  }
};
