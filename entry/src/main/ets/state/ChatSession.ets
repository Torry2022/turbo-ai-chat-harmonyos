import { ChatMessage, ChatTurn, CONTEXT_MESSAGE_LIMIT, PerfMetrics } from '../models/ChatTypes';
import { nowTime } from '../utils/formatters';
import { answerTextForContext, isLikelyIncompleteAssistantText, stripModelSpecialTokens } from '../utils/thinking';

export class ChatSession {
  messages: ChatMessage[] = [];
  private nextMessageId: number = 1;

  initializeWelcome(modelShortName: string): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `请先加载 ${modelShortName}，然后发送一条简短问题。想要更快响应，可以降低最大输出。`,
      imageUri: '',
      time: nowTime(),
      includeInContext: false,
      thinkingExpanded: false
    }];
  }

  newChat(loaded: boolean, modelShortName: string): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `新对话已开始。${loaded ? `已加载的 ${modelShortName} 会继续保留在内存中。` : '请先加载模型。'}`,
      imageUri: '',
      time: nowTime(),
      includeInContext: false,
      thinkingExpanded: false
    }];
  }

  resetForModelSwitch(modelShortName: string): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `已切换至 ${modelShortName}。请先加载模型，然后开始新的对话。`,
      imageUri: '',
      time: nowTime(),
      includeInContext: false,
      thinkingExpanded: false
    }];
  }

  appendMessage(role: string, content: string, imageUri: string = '', includeInContext: boolean = true): number {
    const message: ChatMessage = {
      id: this.nextMessageId++,
      role,
      content,
      imageUri,
      time: nowTime(),
      includeInContext,
      thinkingExpanded: false
    };
    this.messages = [...this.messages, message];
    return message.id;
  }

  updateMessage(id: number, content: string, includeInContext?: boolean, perfMetrics?: PerfMetrics): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: includeInContext === undefined ? message.includeInContext : includeInContext,
          thinkingExpanded: message.thinkingExpanded,
          perfMetrics: perfMetrics ?? message.perfMetrics
        };
      }
      return message;
    });
  }

  appendToMessage(id: number, chunk: string): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content: message.content + chunk,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: message.includeInContext,
          thinkingExpanded: message.thinkingExpanded
        };
      }
      return message;
    });
  }

  toggleThinkingExpanded(id: number): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content: message.content,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: message.includeInContext,
          thinkingExpanded: !message.thinkingExpanded
        };
      }
      return message;
    });
  }

  composeChatTurns(systemPrompt: string, text: string, contextMessageLimit: number = CONTEXT_MESSAGE_LIMIT): ChatTurn[] {
    const turns: ChatTurn[] = [{
      role: 'system',
      content: systemPrompt
    }];
    const safeContextLimit = Math.max(0, Math.round(contextMessageLimit));
    const contextTurns = safeContextLimit > 0 ? this.composeCompleteContextTurns().slice(-safeContextLimit) : [];
    contextTurns.forEach((turn: ChatTurn) => {
      turns.push(turn);
    });
    turns.push({
      role: 'user',
      content: text
    });
    return turns;
  }

  sanitizeAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    const normalizedText = stripModelSpecialTokens(text);
    const lines = normalizedText
      .split('\n')
      .map((line: string) => line.trimEnd())
      .filter((line: string) => {
        const trimmed = line.trim();
        return trimmed.length > 0 && !/^[*\-•]+\s*$/.test(trimmed);
    });
    const cleanedText = lines.join('\n').trim();
    return stripLeadingSeparator ? this.stripLeadingAssistantSeparator(cleanedText) : cleanedText;
  }

  sanitizeStreamingAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    const cleanedText = this.sanitizeAssistantText(text, stripLeadingSeparator);
    return cleanedText.replace(/^\uFFFD+/, '').trimStart();
  }

  private stripLeadingAssistantSeparator(text: string): string {
    return text.replace(/^(assistant|助手)?\s*[:：]\s*/, '').trim();
  }

  private composeCompleteContextTurns(): ChatTurn[] {
    const turns: ChatTurn[] = [];
    let pendingUser: ChatMessage | undefined = undefined;

    this.messages.forEach((message: ChatMessage) => {
      if (!message.includeInContext || message.content.trim().length === 0) {
        if (message.role === 'assistant') {
          pendingUser = undefined;
        }
        return;
      }

      if (message.role === 'user') {
        pendingUser = message;
        return;
      }

      if (message.role !== 'assistant' || pendingUser === undefined) {
        return;
      }

      if (isLikelyIncompleteAssistantText(message.content)) {
        pendingUser = undefined;
        return;
      }

      const userContent = pendingUser.content.trim();
      const assistantContent = answerTextForContext(message.content).trim();
      pendingUser = undefined;
      if (userContent.length <= 0 || assistantContent.length <= 0) {
        return;
      }

      turns.push({
        role: 'user',
        content: userContent
      });
      turns.push({
        role: 'assistant',
        content: assistantContent
      });
    });

    return turns;
  }
}
