export interface MarkdownSpan {
  text: string;
  bold: boolean;
}

export interface MarkdownBlock {
  type: string;
  text: string;
  items: string[];
  language: string;
}

function emptyBlock(type: string): MarkdownBlock {
  return {
    type,
    text: '',
    items: [],
    language: ''
  };
}

function flushParagraph(blocks: MarkdownBlock[], paragraphLines: string[]): void {
  if (paragraphLines.length <= 0) {
    return;
  }
  const block = emptyBlock('paragraph');
  block.text = paragraphLines.join('\n').trim();
  if (block.text.length > 0) {
    blocks.push(block);
  }
  paragraphLines.length = 0;
}

function flushList(blocks: MarkdownBlock[], listItems: string[], ordered: boolean): void {
  if (listItems.length <= 0) {
    return;
  }
  const block = emptyBlock(ordered ? 'ordered-list' : 'unordered-list');
  listItems.forEach((item: string) => {
    block.items.push(item);
  });
  blocks.push(block);
  listItems.length = 0;
}

function isTableLine(line: string): boolean {
  const trimmed = line.trim();
  return trimmed.indexOf('|') >= 0 && trimmed.replace(/[\|\s:-]/g, '').length > 0;
}

export function parseInlineMarkdown(text: string): MarkdownSpan[] {
  const spans: MarkdownSpan[] = [];
  let index = 0;
  while (index < text.length) {
    const start = text.indexOf('**', index);
    if (start < 0) {
      spans.push({ text: text.substring(index), bold: false });
      break;
    }
    if (start > index) {
      spans.push({ text: text.substring(index, start), bold: false });
    }
    const end = text.indexOf('**', start + 2);
    if (end < 0) {
      spans.push({ text: text.substring(start), bold: false });
      break;
    }
    const boldText = text.substring(start + 2, end);
    if (boldText.length > 0) {
      spans.push({ text: boldText, bold: true });
    }
    index = end + 2;
  }
  return spans.filter((span: MarkdownSpan) => span.text.length > 0);
}

export function parseLightMarkdown(content: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = [];
  const paragraphLines: string[] = [];
  const listItems: string[] = [];
  const codeLines: string[] = [];
  let inCode = false;
  let codeLanguage = '';
  let listOrdered = false;

  const lines = content.replace(/\r\n/g, '\n').split('\n');
  lines.forEach((line: string) => {
    const trimmed = line.trim();

    if (trimmed.startsWith('```')) {
      if (inCode) {
        const block = emptyBlock('code');
        block.text = codeLines.join('\n');
        block.language = codeLanguage;
        blocks.push(block);
        codeLines.length = 0;
        codeLanguage = '';
        inCode = false;
        return;
      }
      flushParagraph(blocks, paragraphLines);
      flushList(blocks, listItems, listOrdered);
      inCode = true;
      codeLanguage = trimmed.substring(3).trim();
      return;
    }

    if (inCode) {
      codeLines.push(line);
      return;
    }

    if (trimmed.length <= 0) {
      flushParagraph(blocks, paragraphLines);
      flushList(blocks, listItems, listOrdered);
      return;
    }

    const headingMatch = trimmed.match(/^(#{1,3})\s+(.+)$/);
    if (headingMatch !== null) {
      flushParagraph(blocks, paragraphLines);
      flushList(blocks, listItems, listOrdered);
      const block = emptyBlock('heading');
      block.text = headingMatch[2].trim();
      blocks.push(block);
      return;
    }

    if (isTableLine(line)) {
      flushParagraph(blocks, paragraphLines);
      flushList(blocks, listItems, listOrdered);
      const block = emptyBlock('code');
      block.text = line;
      blocks.push(block);
      return;
    }

    const unorderedMatch = trimmed.match(/^[-*•]\s+(.+)$/);
    const orderedMatch = trimmed.match(/^\d+[.)]\s+(.+)$/);
    if (unorderedMatch !== null || orderedMatch !== null) {
      flushParagraph(blocks, paragraphLines);
      const ordered = orderedMatch !== null;
      if (listItems.length > 0 && listOrdered !== ordered) {
        flushList(blocks, listItems, listOrdered);
      }
      listOrdered = ordered;
      if (orderedMatch !== null) {
        listItems.push(orderedMatch[1].trim());
      } else if (unorderedMatch !== null) {
        listItems.push(unorderedMatch[1].trim());
      }
      return;
    }

    flushList(blocks, listItems, listOrdered);
    paragraphLines.push(line);
  });

  if (inCode) {
    const block = emptyBlock('code');
    block.text = codeLines.join('\n');
    block.language = codeLanguage;
    blocks.push(block);
  }
  flushParagraph(blocks, paragraphLines);
  flushList(blocks, listItems, listOrdered);
  return blocks;
}
