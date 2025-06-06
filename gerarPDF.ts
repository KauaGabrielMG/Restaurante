import { jsPDF } from 'jspdf';

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

    console.log('📄 Gerando PDF com jsPDF...');

    // Criar novo documento PDF
    const doc = new jsPDF();

    // Configurar fonte
    doc.setFont('helvetica');

    // Título do documento
    doc.setFontSize(20);
    doc.setFont('helvetica', 'bold');
    doc.text('COMPROVANTE DE PEDIDO', 20, 30);

    // Linha separadora
    doc.setLineWidth(0.5);
    doc.line(20, 35, 190, 35);

    // Informações do pedido
    doc.setFontSize(12);
    doc.setFont('helvetica', 'normal');

    let yPosition = 50;

    doc.text(`ID do Pedido: ${pedido.id}`, 20, yPosition);
    yPosition += 10;

    doc.text(`Cliente: ${pedido.cliente}`, 20, yPosition);
    yPosition += 10;

    doc.text(`Mesa: ${pedido.mesa}`, 20, yPosition);
    yPosition += 10;

    doc.text(`Status: ${pedido.status}`, 20, yPosition);
    yPosition += 10;

    doc.text(
      `Data: ${new Date(pedido.criadoEm).toLocaleString('pt-BR')}`,
      20,
      yPosition,
    );
    yPosition += 20;

    // Seção de itens
    doc.setFont('helvetica', 'bold');
    doc.text('ITENS DO PEDIDO:', 20, yPosition);
    yPosition += 10;

    // Linha separadora
    doc.line(20, yPosition, 190, yPosition);
    yPosition += 10;

    // Lista de itens
    doc.setFont('helvetica', 'normal');
    let total = 0;

    pedido.itens.forEach((item, index) => {
      const subtotal = item.quantidade * item.preco;
      total += subtotal;

      // Nome do item
      doc.text(`${index + 1}. ${item.nome}`, 25, yPosition);
      yPosition += 8;

      // Detalhes do item
      doc.text(`   Quantidade: ${item.quantidade}`, 30, yPosition);
      doc.text(`Preço unit.: R$ ${item.preco.toFixed(2)}`, 100, yPosition);
      doc.text(`Subtotal: R$ ${subtotal.toFixed(2)}`, 150, yPosition);
      yPosition += 12;

      // Verificar se precisa de nova página
      if (yPosition > 250) {
        doc.addPage();
        yPosition = 30;
      }
    });

    // Linha separadora antes do total
    yPosition += 5;
    doc.setLineWidth(0.3);
    doc.line(20, yPosition, 190, yPosition);
    yPosition += 15;

    // Total do pedido
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(14);
    doc.text(`TOTAL: R$ ${total.toFixed(2)}`, 120, yPosition);

    // Rodapé
    yPosition += 30;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.text('Obrigado pela preferência!', 20, yPosition);
    doc.text('Sistema de Restaurante - LocalStack', 20, yPosition + 8);
    doc.text(
      `Gerado em: ${new Date().toLocaleString('pt-BR')}`,
      20,
      yPosition + 16,
    );

    // Converter para buffer
    const pdfBuffer = Buffer.from(doc.output('arraybuffer'));

    console.log(
      `✅ PDF gerado com sucesso! Tamanho: ${pdfBuffer.length} bytes`,
    );

    return pdfBuffer;
  } catch (error) {
    console.error('❌ Erro ao gerar PDF:', error);
    throw new Error(
      `Falha na geração do PDF: ${
        error instanceof Error ? error.message : 'Erro desconhecido'
      }`,
    );
  }
}
