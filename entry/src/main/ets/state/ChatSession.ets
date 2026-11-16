import { ChatAnswerVersion, ChatContextOmission, ChatContextSelection, ChatMessage, ChatTurn, CONTEXT_MESSAGE_LIMIT, GenerationStopReason, PerfMetrics } from '../models/ChatTypes'
import { nowTime } from '../utils/formatters'
import { sanitizeAssistantText, sanitizeStreamingAssistantText } from '../utils/generationText'
import { answerTextForContext, isLikelyIncompleteAssistantText, parseAssistantText } from '../utils/thinking'

interface ChatContextPair {
  question: ChatMessage
  answer: ChatMessage
  body: string
}

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
    if (index >= 0) {
      let start = index
      while (start > 0 && this.messages[start - 1].role === 'notice') start--
      this.messages = this.messages.slice(0, start)
    }
  }

  private answerSnapshot(message: ChatMessage): ChatAnswerVersion {
    return {
      content: message.content, time: message.time, createdAt: message.createdAt,
      completedAt: message.completedAt, modelId: message.modelId, modelName: message.modelName,
      generationState: message.generationState, stopReason: message.stopReason, includeInContext: message.includeInContext,
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
      generationState: selected.generationState, stopReason: selected.stopReason, includeInContext: selected.includeInContext,
      thinkingExpanded: selected.thinkingExpanded, perfMetrics: selected.perfMetrics,
      answerVersions: versions, answerVersionIndex: index
    })
    return true
  }

  restore(messages: ChatMessage[]): void {
    this.messages = messages.map((message: ChatMessage) => {
      if (message.generationState === 'generating') {
        message.generationState = 'interrupted'
      }
      if (message.role === 'assistant' && message.kind !== 'notice') {
        message.includeInContext = this.contextAnswer(message).trim().length > 0
      }
      if (message.answerVersions) {
        message.answerVersions.forEach((version: ChatAnswerVersion) => {
          if (version.generationState === 'generating') {
            version.generationState = 'interrupted'
          }
          version.includeInContext = this.contextAnswer(version).trim().length > 0
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
          stopReason: message.stopReason,
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
          stopReason: message.stopReason,
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
          stopReason: message.stopReason,
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

  markGeneration(id: number, state: 'complete' | 'interrupted' | 'stopped' | 'failed', stopReason?: GenerationStopReason): void {
    this.messages.forEach((message: ChatMessage) => {
      if (message.id === id) {
        message.generationState = state
        message.stopReason = stopReason
        message.completedAt = Date.now()
        if (message.answerVersions) {
          message.answerVersions[message.answerVersionIndex ?? 0] = this.answerSnapshot(message)
        }
      }
    })
  }

  composeChatTurns(systemPrompt: string, text: string, contextMessageLimit: number = CONTEXT_MESSAGE_LIMIT): ChatTurn[] {
    return this.composeContext(systemPrompt, text, contextMessageLimit).turns
  }

  sanitizeAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    return sanitizeAssistantText(text, stripLeadingSeparator)
  }

  sanitizeStreamingAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
    return sanitizeStreamingAssistantText(text, stripLeadingSeparator)
  }

  composeContext(systemPrompt: string, text: string, contextMessageLimit: number = CONTEXT_MESSAGE_LIMIT,
    beforeQuestionId: number = 0): ChatContextSelection {
    const pairs: ChatContextPair[] = []
    const omitted: ChatContextOmission[] = []
    let pendingUser: ChatMessage | undefined = undefined
    for (const message of this.messages) {
      if (message.id === beforeQuestionId) break
      if (message.kind === 'notice' || message.role === 'notice') {
        omitted.push({ messageId: message.id, role: message.role, content: message.content, reason: '应用提示' })
        continue
      }
      if (message.role === 'user') {
        if (pendingUser !== undefined) {
          omitted.push({ messageId: pendingUser.id, role: pendingUser.role, content: pendingUser.content,
            reason: '没有对应的回答' })
        }
        pendingUser = message.includeInContext && message.content.trim().length > 0 ? message : undefined
        if (pendingUser === undefined) omitted.push({ messageId: message.id, role: message.role,
          content: message.content, reason: '问题为空或已排除' })
        continue
      }
      if (message.role !== 'assistant' || pendingUser === undefined) {
        omitted.push({ messageId: message.id, role: message.role, content: message.content,
          reason: '没有对应的问题' })
        continue
      }
      const body = this.contextAnswer(message)
      if (body.trim().length > 0) {
        pairs.push({ question: pendingUser, answer: message, body })
      } else {
        const parts = parseAssistantText(message.content)
        const reason = message.stopReason === 'internal_error' ||
          (message.generationState === 'failed' && message.stopReason !== 'timeout') ? '生成失败' :
          (message.generationState === 'generating' ? '正在生成' :
            (parts.hasThinking && parts.answer.trim().length === 0 ? '只生成了思考过程，尚未给出回答' :
              (parts.answer.trim().length === 0 ? '尚未生成回答' : '回答已排除')))
        omitted.push({ messageId: pendingUser.id, role: pendingUser.role, content: pendingUser.content, reason })
        omitted.push({ messageId: message.id, role: message.role, content: message.content, reason })
      }
      pendingUser = undefined
    }
    if (pendingUser !== undefined) omitted.push({ messageId: pendingUser.id, role: pendingUser.role,
      content: pendingUser.content, reason: '没有对应的回答' })
    const pairLimit = Math.floor(Math.max(0, Math.round(contextMessageLimit)) / 2)
    const start = Math.max(0, pairs.length - pairLimit)
    const turns: ChatTurn[] = []
    const historyMessageIds: number[] = []
    if (systemPrompt.length > 0) turns.push({ role: 'system', content: systemPrompt })
    pairs.forEach((pair: ChatContextPair, index: number) => {
      if (index >= start) {
        turns.push({ role: 'user', content: pair.question.content, imageUri: pair.question.imageUri })
        turns.push({ role: 'assistant', content: pair.body })
        historyMessageIds.push(pair.question.id, pair.answer.id)
      } else {
        const reason = pairLimit === 0 ? '当前采用单轮对话' : '超过历史条数上限'
        omitted.push({ messageId: pair.question.id, role: pair.question.role, content: pair.question.content, reason })
        omitted.push({ messageId: pair.answer.id, role: pair.answer.role, content: pair.answer.content, reason })
      }
    })
    turns.push({ role: 'user', content: text })
    return { turns, omitted, historyMessageIds }
  }

  private contextAnswer(message: ChatMessage | ChatAnswerVersion): string {
    if (message.generationState === 'generating') return ''
    if (!message.includeInContext && (message.content === '（已停止生成）' || message.content === '（原生层返回空内容）')) return ''
    if (message.stopReason === 'internal_error' || (message.generationState === 'failed' && message.stopReason !== 'timeout')) {
      return ''
    }
    const interrupted = message.generationState === 'interrupted' || message.generationState === 'stopped' ||
      message.stopReason === 'user_stop' || message.stopReason === 'max_tokens' || message.stopReason === 'timeout'
    if (!message.includeInContext && !interrupted) return ''
    if (!interrupted && message.stopReason !== 'eos' && isLikelyIncompleteAssistantText(message.content)) return ''
    return answerTextForContext(message.content)
  }
}
