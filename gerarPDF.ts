interface Pedido {
  id: string;
  cliente: string;
  itens: Array<{ nome: string; quantidade: number; preco: number }>;
  mesa: number;
  status: string;
  criadoEm: string;
  atualizadoEm?: string;
}

export function gerarPDF(pedido: Pedido): Buffer {
  try {
    // Validação dos dados do pedido
    if (!pedido || !pedido.id || !pedido.cliente || !pedido.itens) {
      throw new Error('Dados do pedido inválidos ou incompletos');
    }

    if (!Array.isArray(pedido.itens) || pedido.itens.length === 0) {
      throw new Error('Pedido deve conter pelo menos um item');
    }

    // Simulação da geração de PDF
    // Em um cenário real, você usaria uma biblioteca como PDFKit ou jsPDF
    const pdfContent = `
COMPROVANTE DE PEDIDO
====================

ID do Pedido: ${pedido.id}
Cliente: ${pedido.cliente}
Mesa: ${pedido.mesa}
Status: ${pedido.status}
Data de Criação: ${new Date(pedido.criadoEm).toLocaleString('pt-BR')}

ITENS:
${pedido.itens
  .map(
    (item) =>
      `- ${item.nome} (Qtd: ${item.quantidade}) - R$ ${item.preco.toFixed(2)}`,
  )
  .join('\n')}

Total: R$ ${pedido.itens
      .reduce((total, item) => total + item.quantidade * item.preco, 0)
      .toFixed(2)}
		`.trim();

    // Converter string para Buffer (simulando um PDF real)
    return Buffer.from(pdfContent, 'utf-8');
  } catch (error) {
    console.error('Erro ao gerar PDF:', error);
    throw new Error(
      `Falha na geração do PDF: ${
        error instanceof Error ? error.message : 'Erro desconhecido'
      }`,
    );
  }
}
