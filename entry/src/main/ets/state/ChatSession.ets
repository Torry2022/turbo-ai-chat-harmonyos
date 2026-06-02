import { ChatMessage, ChatTurn, CONTEXT_MESSAGE_LIMIT } from '../models/ChatTypes';
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

  updateMessage(id: number, content: string, includeInContext?: boolean): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: includeInContext === undefined ? message.includeInContext : includeInContext,
          thinkingExpanded: message.thinkingExpanded
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

  composeChatTurns(systemPrompt: string, text: string): ChatTurn[] {
    const turns: ChatTurn[] = [{
      role: 'system',
      content: systemPrompt
    }];
    const contextMessages = this.messages
      .filter((message: ChatMessage) => {
        if (!message.includeInContext || message.content.trim().length === 0) {
          return false;
        }
        return message.role !== 'assistant' || !isLikelyIncompleteAssistantText(message.content);
      })
      .slice(-CONTEXT_MESSAGE_LIMIT);

    contextMessages.forEach((message: ChatMessage) => {
      const content = message.role === 'assistant' ? answerTextForContext(message.content) : message.content;
      if (content.trim().length === 0) {
        return;
      }
      turns.push({
        role: message.role === 'assistant' ? 'assistant' : 'user',
        content
      });
    });
    turns.push({
      role: 'user',
      content: text
    });
    return turns;
  }

  sanitizeAssistantText(text: string): string {
    const normalizedText = stripModelSpecialTokens(text);
    const lines = normalizedText
      .split('\n')
      .map((line: string) => line.trimEnd())
      .filter((line: string) => {
        const trimmed = line.trim();
        return trimmed.length > 0 && !/^[*\-•]+\s*$/.test(trimmed);
      });
    return lines.join('\n').trim();
  }
}
