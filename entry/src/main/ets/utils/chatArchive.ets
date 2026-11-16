import { ChatConversation } from '../models/ChatHistoryTypes'
import { ChatMessage } from '../models/ChatTypes'

export interface ChatArchive {
  format: string
  version: number
  createdAt: number
  conversations: ChatConversation[]
}

export const CHAT_ARCHIVE_MANIFEST_MAX_BYTES: number = 16 * 1024 * 1024

export function archiveImagePath(value: string): boolean {
  return /^images\/[0-9]+-[0-9]+$/.test(value)
}

export function parseChatArchive(text: string): ChatArchive {
  const archive = JSON.parse(text) as ChatArchive
  if (!archive || archive.format !== 'turbo-ai-chat-history' || archive.version !== 1 ||
    !Number.isFinite(archive.createdAt) || !Array.isArray(archive.conversations)) {
    throw new Error('无法识别此备份，请选择 Turbo AI Chat 导出的备份文件')
  }
  const ids: Set<string> = new Set()
  archive.conversations.forEach((record: ChatConversation) => {
    if (!record || record.version !== 1 || typeof record.id !== 'string' || ids.has(record.id) ||
      typeof record.title !== 'string' || !Number.isFinite(record.createdAt) ||
      !Number.isFinite(record.updatedAt) || !Array.isArray(record.messages)) {
      throw new Error('备份中的对话记录不完整')
    }
    ids.add(record.id)
    const messages: Set<number> = new Set()
    record.messages.forEach((message: ChatMessage) => {
      if (!message || !Number.isSafeInteger(message.id) || message.id < 1 || messages.has(message.id) ||
        !['user', 'assistant', 'notice'].includes(message.role) || typeof message.content !== 'string' ||
        typeof message.time !== 'string' || typeof message.includeInContext !== 'boolean' ||
        typeof message.thinkingExpanded !== 'boolean' || typeof message.imageUri !== 'string' ||
        (message.imageUri !== '' && !archiveImagePath(message.imageUri))) {
        throw new Error('备份中的消息或图片引用无效')
      }
      messages.add(message.id)
    })
  })
  return archive
}

export function conversationMarkdown(record: ChatConversation): string {
  const blocks: string[] = [`# ${record.title.replace(/[\r\n]/g, ' ')}`]
  record.messages.forEach((message: ChatMessage) => {
    if (message.kind === 'notice' || message.role === 'notice') return
    blocks.push(`## ${message.role === 'user' ? '你' : (message.modelName || '助手')}`)
    if (message.imageUri) blocks.push(`![图片](${message.imageUri})`)
    blocks.push(message.content)
  })
  return blocks.join('\n\n') + '\n'
}
