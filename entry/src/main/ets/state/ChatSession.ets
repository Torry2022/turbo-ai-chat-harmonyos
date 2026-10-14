import { ChatMessage, ChatTurn, CONTEXT_MESSAGE_LIMIT, PerfMetrics } from '../models/ChatTypes'
import { nowTime } from '../utils/formatters'
import { sanitizeAssistantText, sanitizeStreamingAssistantText } from '../utils/generationText'
import { answerTextForContext, isLikelyIncompleteAssistantText } from '../utils/thinking'

export class ChatSession {
  messages: ChatMessage[] = []
  private nextMessageId: number = 1
  private modelId: string = ''
  private modelName: string = ''

  restore(messages: ChatMessage[]): void {
    this.messages = messages.map((message: ChatMessage) => {
      if (message.generationState === 'generating') {
        message.generationState = 'interrupted'
        message.includeInContext = false
      }
      return message
    })
    this.nextMessageId = this.messages.reduce((id: number, message: ChatMessage) => Math.max(id, message.id + 1), 1)
  }

  prepareModel(modelId: string, modelName: string): void {
    const previous = this.messages.filter((message: ChatMessage) => message.kind === 'message' && message.role === 'assistant')
    this.modelId = modelId
    this.modelName = modelName
    if (previous.length > 0 && previous[previous.length - 1].modelId !== modelId) {
      this.appendMessage('notice', `后续回答使用 ${modelName}`, '', false)
    }
  }

  initializeWelcome(modelShortName: string): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `请先加载 ${modelShortName}，然后发送一条简短问题。想要更快响应，可以降低最大输出。`,
      imageUri: '',
      time: nowTime(),
      createdAt: Date.now(),
      kind: 'notice',
      includeInContext: false,
      thinkingExpanded: false
    }]
  }

  newChat(loaded: boolean, modelShortName: string): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `新对话已开始。${loaded ? `已加载的 ${modelShortName} 会继续保留在内存中。` : '请先加载模型。'}`,
      imageUri: '',
      time: nowTime(),
      createdAt: Date.now(),
      kind: 'notice',
      includeInContext: false,
      thinkingExpanded: false
    }]
  }

  resetForModelSwitch(modelShortName: string): void {
    if (!this.messages.some((message: ChatMessage) => message.role === 'user')) {
      this.initializeWelcome(modelShortName)
    }
  }

  appendMessage(role: string, content: string, imageUri: string = '', includeInContext: boolean = true): number {
    const message: ChatMessage = {
      id: this.nextMessageId++,
      role,
      content,
      imageUri,
      time: nowTime(),
      createdAt: Date.now(),
      kind: includeInContext ? 'message' : 'notice',
      modelId: this.modelId,
      modelName: this.modelName,
      generationState: role === 'assistant' && includeInContext && content.length === 0 ? 'generating' : 'complete',
      includeInContext,
      thinkingExpanded: false
    }
    this.messages = [...this.messages, message]
    return message.id
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
          createdAt: message.createdAt,
          completedAt: message.completedAt,
          modelId: message.modelId,
          modelName: message.modelName,
          kind: message.kind,
          generationState: message.generationState,
          imageUnavailable: message.imageUnavailable,
          includeInContext: includeInContext === undefined ? message.includeInContext : includeInContext,
          thinkingExpanded: message.thinkingExpanded,
          perfMetrics: perfMetrics ?? message.perfMetrics
        }
      }
      return message
    })
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
          createdAt: message.createdAt,
          completedAt: message.completedAt,
          modelId: message.modelId,
          modelName: message.modelName,
          kind: message.kind,
          generationState: message.generationState,
          imageUnavailable: message.imageUnavailable,
          includeInContext: message.includeInContext,
          thinkingExpanded: message.thinkingExpanded,
          perfMetrics: message.perfMetrics
        }
      }
      return message
    })
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
          createdAt: message.createdAt,
          completedAt: message.completedAt,
          modelId: message.modelId,
          modelName: message.modelName,
          kind: message.kind,
          generationState: message.generationState,
          imageUnavailable: message.imageUnavailable,
          includeInContext: message.includeInContext,
          thinkingExpanded: !message.thinkingExpanded,
          perfMetrics: message.perfMetrics
        }
      }
      return message
    })
  }

  markGeneration(id: number, state: 'complete' | 'interrupted' | 'stopped' | 'failed'): void {
    this.messages.forEach((message: ChatMessage) => {
      if (message.id === id) {
        message.generationState = state
        message.completedAt = Date.now()
      }
    })
  }

  composeChatTurns(systemPrompt: string, text: string, contextMessageLimit: number = CONTEXT_MESSAGE_LIMIT): ChatTurn[] {
    const turns: ChatTurn[] = [{
      role: 'system',
      content: systemPrompt
    }]
    const safeContextLimit = Math.max(0, Math.round(contextMessageLimit))
    const contextTurns = safeContextLimit > 0 ? this.composeCompleteContextTurns().slice(-safeContextLimit) : []
    contextTurns.forEach((turn: ChatTurn) => {
      turns.push(turn)
    })
    turns.push({
      role: 'user',
      content: text
    })
    return turns
  }

  sanitizeAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    return sanitizeAssistantText(text, stripLeadingSeparator)
  }

  sanitizeStreamingAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    return sanitizeStreamingAssistantText(text, stripLeadingSeparator)
  }

  private composeCompleteContextTurns(): ChatTurn[] {
    const turns: ChatTurn[] = []
    let pendingUser: ChatMessage | undefined = undefined

    this.messages.forEach((message: ChatMessage) => {
      if (!message.includeInContext || message.content.trim().length === 0) {
        if (message.role === 'assistant') {
          pendingUser = undefined
        }
        return
      }

      if (message.role === 'user') {
        pendingUser = message
        return
      }

      if (message.role !== 'assistant' || pendingUser === undefined) {
        return
      }

      if (isLikelyIncompleteAssistantText(message.content)) {
        pendingUser = undefined
        return
      }

      const userContent = pendingUser.content.trim()
      const assistantContent = answerTextForContext(message.content).trim()
      pendingUser = undefined
      if (userContent.length <= 0 || assistantContent.length <= 0) {
        return
      }

      turns.push({
        role: 'user',
        content: userContent
      })
      turns.push({
        role: 'assistant',
        content: assistantContent
      })
    })

    return turns
  }
}
