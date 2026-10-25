import { ChatAnswerVersion, ChatMessage, ChatTurn, CONTEXT_MESSAGE_LIMIT, PerfMetrics } from '../models/ChatTypes'
import { nowTime } from '../utils/formatters'
import { sanitizeAssistantText, sanitizeStreamingAssistantText } from '../utils/generationText'
import { answerTextForContext, isLikelyIncompleteAssistantText } from '../utils/thinking'

export class ChatSession {
  messages: ChatMessage[] = []
  private nextMessageId: number = 1
  private modelId: string = ''
  private modelName: string = ''

  lastQuestion(): ChatMessage | undefined {
    for (let index = this.messages.length - 1; index >= 0; index--) {
      if (this.messages[index].role === 'user') return this.messages[index]
    }
    return undefined
  }

  lastAnswer(): ChatMessage | undefined {
    const question = this.lastQuestion()
    if (question === undefined) return undefined
    for (let index = this.messages.length - 1; index >= 0; index--) {
      const message = this.messages[index]
      if (message.id === question.id) break
      if (message.role === 'assistant' && message.kind !== 'notice') return message
    }
    return undefined
  }

  removeFromQuestion(messageId: number): void {
    const index = this.messages.findIndex((message: ChatMessage) =>
      message.id === messageId && message.role === 'user' && message.kind !== 'notice')
    if (index >= 0) this.messages = this.messages.slice(0, index)
  }

  private answerSnapshot(message: ChatMessage): ChatAnswerVersion {
    return {
      content: message.content, time: message.time, createdAt: message.createdAt,
      completedAt: message.completedAt, modelId: message.modelId, modelName: message.modelName,
      generationState: message.generationState, includeInContext: message.includeInContext,
      thinkingExpanded: message.thinkingExpanded, perfMetrics: message.perfMetrics
    }
  }

  startAnswerVersion(messageId: number): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id !== messageId || message.role !== 'assistant' || message.kind === 'notice') return message
      const versions = message.answerVersions?.slice() ?? [this.answerSnapshot(message)]
      versions[message.answerVersionIndex ?? 0] = this.answerSnapshot(message)
      const next: ChatAnswerVersion = {
        content: '', time: nowTime(), createdAt: Date.now(), modelId: this.modelId, modelName: this.modelName,
        generationState: 'generating', includeInContext: true, thinkingExpanded: false
      }
      versions.push(next)
      return {
        id: message.id, role: message.role, content: next.content, imageUri: message.imageUri,
        time: next.time, createdAt: next.createdAt, modelId: next.modelId, modelName: next.modelName,
        kind: message.kind, generationState: next.generationState, includeInContext: next.includeInContext,
        thinkingExpanded: next.thinkingExpanded, answerVersions: versions, answerVersionIndex: versions.length - 1
      }
    })
  }

  selectAnswerVersion(messageId: number, index: number): boolean {
    const message = this.messages.find((item: ChatMessage) => item.id === messageId)
    if (message === undefined || message.role !== 'assistant' || message.kind === 'notice' ||
      !message.answerVersions || !Number.isInteger(index) || index < 0 || index >= message.answerVersions.length ||
      index === message.answerVersionIndex || message.generationState === 'generating') return false
    const versions = message.answerVersions.slice()
    versions[message.answerVersionIndex ?? 0] = this.answerSnapshot(message)
    const selected = versions[index]
    this.messages = this.messages.map((item: ChatMessage) => item.id !== messageId ? item : {
      id: item.id, role: item.role, content: selected.content, imageUri: item.imageUri,
      time: selected.time, createdAt: selected.createdAt, completedAt: selected.completedAt,
      modelId: selected.modelId, modelName: selected.modelName, kind: item.kind,
      generationState: selected.generationState, includeInContext: selected.includeInContext,
      thinkingExpanded: selected.thinkingExpanded, perfMetrics: selected.perfMetrics,
      answerVersions: versions, answerVersionIndex: index
    })
    return true
  }

  restore(messages: ChatMessage[]): void {
    this.messages = messages.map((message: ChatMessage) => {
      if (message.generationState === 'generating') {
        message.generationState = 'interrupted'
        message.includeInContext = false
      }
      if (message.answerVersions) {
        message.answerVersions.forEach((version: ChatAnswerVersion) => {
          if (version.generationState === 'generating') {
            version.generationState = 'interrupted'
            version.includeInContext = false
          }
        })
        // The visible fields may contain a newer streaming checkpoint than its version snapshot.
        message.answerVersions[message.answerVersionIndex ?? 0] = this.answerSnapshot(message)
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
          answerVersions: message.answerVersions,
          answerVersionIndex: message.answerVersionIndex,
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
          answerVersions: message.answerVersions,
          answerVersionIndex: message.answerVersionIndex,
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
          answerVersions: message.answerVersions,
          answerVersionIndex: message.answerVersionIndex,
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
        if (message.answerVersions) {
          message.answerVersions[message.answerVersionIndex ?? 0] = this.answerSnapshot(message)
        }
      }
    })
  }

  composeChatTurns(systemPrompt: string, text: string, contextMessageLimit: number = CONTEXT_MESSAGE_LIMIT): ChatTurn[] {
    const turns: ChatTurn[] = [{
      role: 'system',
      content: systemPrompt
    }]
    const roundedContextLimit = Math.max(0, Math.round(contextMessageLimit))
    const safeContextLimit = roundedContextLimit - roundedContextLimit % 2
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
