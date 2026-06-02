export interface AssistantTextParts {
  hasThinking: boolean;
  thinking: string;
  answer: string;
  thinkingClosed: boolean;
}

export function stripModelSpecialTokens(content: string): string {
  let text = content
    .replace(/<s>/g, '')
    .replace(/<\/s>/g, '')
    .replace(/<pad>/g, '')
    .replace(/<unk>/g, '')
    .replace(/<\|im_start\|>/g, '')
    .replace(/<\|im_end\|>/g, '')
    .replace(/<\|begin_of_text\|>/g, '')
    .replace(/<\|end_of_text\|>/g, '');

  if (text.indexOf('<think>') < 0) {
    text = text.replace(/<\/think>/g, '');
  }
  return text;
}

export function parseAssistantText(content: string): AssistantTextParts {
  const normalizedContent = stripModelSpecialTokens(content);
  const openTag = '<think>';
  const closeTag = '</think>';
  const openIndex = normalizedContent.indexOf(openTag);
  if (openIndex < 0) {
    return {
      hasThinking: false,
      thinking: '',
      answer: normalizedContent.trim(),
      thinkingClosed: false
    };
  }

  const before = normalizedContent.substring(0, openIndex).trim();
  const afterOpen = normalizedContent.substring(openIndex + openTag.length);
  const closeIndex = afterOpen.indexOf(closeTag);
  if (closeIndex < 0) {
    return {
      hasThinking: true,
      thinking: afterOpen.trim(),
      answer: before,
      thinkingClosed: false
    };
  }

  const thinking = afterOpen.substring(0, closeIndex).trim();
  const afterClose = afterOpen.substring(closeIndex + closeTag.length).trim();
  let answer = before;
  if (answer.length > 0 && afterClose.length > 0) {
    answer = `${answer}\n${afterClose}`;
  } else if (afterClose.length > 0) {
    answer = afterClose;
  }

  return {
    hasThinking: true,
    thinking,
    answer: answer.trim(),
    thinkingClosed: true
  };
}

export function answerTextForContext(content: string): string {
  const parts = parseAssistantText(content);
  if (!parts.hasThinking) {
    return stripModelSpecialTokens(content).trim();
  }
  return parts.answer.trim();
}

export function isLikelyIncompleteAssistantText(content: string): boolean {
  const parts = parseAssistantText(content);
  if (parts.hasThinking && !parts.thinkingClosed) {
    return true;
  }

  const answer = parts.answer.trim();
  if (answer.length === 0) {
    return false;
  }
  if (/[。！？!?\.…」』”'")）】》]$/.test(answer)) {
    return false;
  }
  if (/[，、；：,;:]$/.test(answer)) {
    return true;
  }
  return answer.length >= 12;
}
