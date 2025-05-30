import {DynamoDB ,S3} from "aws-sdk";
import { gerarPDF } from "./gerarPDF";
import { execSync } from "node:child_process";

// Obter IP da interface eth0 dinamicamente
const getEth0IP = () => {
  try {
    const ip = execSync("ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1", { encoding: 'utf8' }).trim();
    return ip || '172.29.30.139';
  } catch (error) {
    console.warn('Erro ao obter IP da eth0, usando 172.29.30.139:', error);
    return '172.29.30.139';
  }
};

const ETH0_IP = getEth0IP();
const ENDPOINT = `http://${ETH0_IP}:4566`;

const docClient = new DynamoDB.DocumentClient({ endpoint: ENDPOINT });
const s3 = new S3({ endpoint: ENDPOINT });

interface SQSRecord {
	body: string;
	messageId: string;
	receiptHandle: string;
}

interface SQSEvent {
	Records: SQSRecord[];
}

interface PedidoMessage {
	id: string;
	timestamp?: string;
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

export const handler = async (event: SQSEvent) => {
	const processedRecords: string[] = [];
	const failedRecords: string[] = [];

	try {
		console.log('SQS Event received:', JSON.stringify(event, null, 2));

		// Validação básica do evento
		if (!event || !event.Records || !Array.isArray(event.Records)) {
			console.error('Evento SQS inválido:', event);
			return {
				statusCode: 400,
				body: JSON.stringify({ erro: 'Evento SQS inválido' })
			};
		}

		for (const record of event.Records) {
			try {
				// Validação do record
				if (!record || !record.body) {
					console.error('Record inválido:', record);
					failedRecords.push(record?.messageId || 'unknown');
					continue;
				}

				// Parse da mensagem com tratamento de erro
				let mensagem: PedidoMessage;
				try {
					mensagem = JSON.parse(record.body);
				} catch (parseError) {
					console.error('Erro ao fazer parse da mensagem SQS:', parseError, 'Body:', record.body);
					failedRecords.push(record.messageId);
					continue;
				}

				// Validação da mensagem
				if (!mensagem || !mensagem.id) {
					console.error('Mensagem inválida - ID não encontrado:', mensagem);
					failedRecords.push(record.messageId);
					continue;
				}

				const { id } = mensagem;

				// Buscar pedido no DynamoDB com tratamento de erro
				let pedido;
				try {
					const result = await docClient.get({
						TableName: "Pedidos",
						Key: { id }
					}).promise();

					if (!result.Item) {
						console.error(`Pedido não encontrado no DynamoDB: ${id}`);
						failedRecords.push(record.messageId);
						continue;
					}

					pedido = result;
				} catch (dynamoError) {
					console.error(`Erro ao buscar pedido ${id} no DynamoDB:`, dynamoError);
					failedRecords.push(record.messageId);
					continue;
				}				// Gerar PDF com tratamento de erro
				let pdfBuffer;
				try {
					if (!pedido.Item) {
						throw new Error('Dados do pedido não encontrados');
					}
					pdfBuffer = gerarPDF(pedido.Item as Pedido);
					if (!pdfBuffer) {
						throw new Error('PDF gerado está vazio');
					}
				} catch (pdfError) {
					console.error(`Erro ao gerar PDF para pedido ${id}:`, pdfError);
					failedRecords.push(record.messageId);
					continue;
				}

				// Upload para S3 com tratamento de erro
				try {
					await s3.putObject({
						Bucket: "comprovantes",
						Key: `${id}.pdf`,
						Body: pdfBuffer,
						ContentType: "application/pdf"
					}).promise();
				} catch (s3Error) {
					console.error(`Erro ao fazer upload do PDF para S3 (pedido ${id}):`, s3Error);
					failedRecords.push(record.messageId);
					continue;
				}

				// Atualizar status no DynamoDB com tratamento de erro
				try {
					await docClient.update({
						TableName: "Pedidos",
						Key: { id },
						UpdateExpression: "set #s = :status, #u = :updatedAt",
						ExpressionAttributeNames: {
							"#s": "status",
							"#u": "atualizadoEm"
						},
						ExpressionAttributeValues: {
							":status": "PROCESSADO",
							":updatedAt": new Date().toISOString()
						}
					}).promise();

					processedRecords.push(record.messageId);
					console.log(`Pedido ${id} processado com sucesso`);

				} catch (updateError) {
					console.error(`Erro ao atualizar status do pedido ${id}:`, updateError);
					failedRecords.push(record.messageId);
					continue;
				}

			} catch (recordError) {
				console.error('Erro inesperado ao processar record:', recordError, 'Record:', record);
				failedRecords.push(record?.messageId || 'unknown');
			}
		}

		// Log do resultado do processamento
		console.log(`Processamento concluído - Sucessos: ${processedRecords.length}, Falhas: ${failedRecords.length}`);

		if (failedRecords.length > 0) {
			console.warn('Records que falharam:', failedRecords);
		}

		return {
			statusCode: 200,
			body: JSON.stringify({
				processados: processedRecords.length,
				falhas: failedRecords.length,
				recordsComFalha: failedRecords
			})
		};

	} catch (error) {
		console.error('Erro inesperado no handler:', error);
		return {
			statusCode: 500,
			body: JSON.stringify({
				erro: 'Erro interno do servidor',
				mensagem: 'Falha inesperada no processamento dos pedidos'
			})
		};
	}
};
