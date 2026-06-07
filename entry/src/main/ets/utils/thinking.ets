export interface AssistantTextParts {
  hasThinking: boolean;
  thinking: string;
  answer: string;
  thinkingClosed: boolean;
}

function stripThinkTags(text: string): string {
  return text
    .replace(/<think>/g, '')
    .replace(/<\/think>/g, '')
    .trim();
}

export function stripModelSpecialTokens(content: string): string {
  let text = content
    .replace(/<s>/g, '')
    .replace(/<\/s>/g, '')
    .replace(/<pad>/g, '')
    .replace(/<unk>/g, '')
    .replace(/<\|im_start\|>/g, '')
    .replace(/<\|im_end\|>/g, '')
    .replace(/<\|begin_of_sentence\|>/g, '')
    .replace(/<\|end_of_sentence\|>/g, '')
    .replace(/<\|User\|>/g, '')
    .replace(/<\|Assistant\|>/g, '')
    .replace(/<\|begin_of_text\|>/g, '')
    .replace(/<\|end_of_text\|>/g, '')
    .replace(/<bos>/g, '')
    .replace(/<\|turn>/g, '')
    .replace(/<turn\|>/g, '');

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
  const afterClose = stripThinkTags(afterOpen.substring(closeIndex + closeTag.length));
  let answer = stripThinkTags(before);
  if (answer.length > 0 && afterClose.length > 0) {
    answer = `${answer}\n${afterClose}`;
  } else if (afterClose.length > 0) {
    answer = afterClose;
  }
  if (thinking.length <= 0) {
    return {
      hasThinking: false,
      thinking: '',
      answer: answer.trim(),
      thinkingClosed: false
    };
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

export function trimLikelyIncompleteTrailingFragment(content: string): string {
  const text = content.trim();
  if (text.length <= 0 || /[。！？!?\.…」』”'")）】》]$/.test(text)) {
    return text;
  }

  const lines = text.split('\n');
  if (lines.length <= 1) {
    return text;
  }

  const lastLine = lines[lines.length - 1].trim();
  const previousText = lines.slice(0, lines.length - 1).join('\n').trim();
  if (previousText.length <= 0 || lastLine.length <= 0) {
    return text;
  }

  if (lastLine.length <= 2 && /[\u4e00-\u9fff]+/.test(lastLine) && /[。！？!?\.…」』”'")）】》]$/.test(previousText)) {
    return previousText;
  }

  if (lastLine.length <= 4 && /^[，、；：,;:\-—]+[\u4e00-\u9fff]*$/.test(lastLine)) {
    return previousText;
  }

  return text;
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
