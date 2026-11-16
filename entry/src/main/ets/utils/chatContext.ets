import { ChatContextSelection, ChatMessage, ChatTurn, PreparedChatInput } from '../models/ChatTypes'

interface ContextConfig {
  max_position_embeddings?: number
  context_length?: number
  text_config?: ContextConfig
}

export interface PreparedChatContext {
  selection: ChatContextSelection
  input: PreparedChatInput
  contextTokens: number
  exceedsContext: boolean
}

export function declaredContextTokens(configText: string): number {
  try {
    const config = JSON.parse(configText) as ContextConfig
    const text = config.text_config ?? config
    const tokens = text.max_position_embeddings ?? text.context_length
    return typeof tokens === 'number' && Number.isSafeInteger(tokens) && tokens > 0 && tokens <= 2147483647 ? tokens : 0
  } catch (_) {
    return 0
  }
}

export async function prepareChatContext(selection: ChatContextSelection, messages: ChatMessage[],
  outputTokens: number, imageInput: boolean,
  measure: (turns: ChatTurn[]) => Promise<PreparedChatInput>): Promise<PreparedChatContext> {
  const omit = (ids: number[], reason: string): void => {
    ids.forEach((id: number) => {
      const message = messages.find((item: ChatMessage) => item.id === id)
      if (message !== undefined) selection.omitted.push({ messageId: id, role: message.role,
        content: message.content, reason })
    })
  }
  while (true) {
    const input = await measure(selection.turns)
    const contextTokens = declaredContextTokens(input.modelConfig)
    if (contextTokens === 0 || input.inputTokens < 0 || input.inputTokens + outputTokens <= contextTokens) {
      return { selection, input, contextTokens, exceedsContext: false }
    }
    if (selection.historyMessageIds.length < 2) {
      return { selection, input, contextTokens, exceedsContext: true }
    }
    const removed = selection.historyMessageIds.splice(0, 2)
    selection.turns.splice(selection.turns[0].role === 'system' ? 1 : 0, 2)
    omit(removed, '为本次问题和输出预留空间')
  }
}
