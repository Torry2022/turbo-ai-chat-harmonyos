import { ChatMessage } from './ChatTypes'

export interface ChatConversation {
  version: number
  id: string
  title: string
  createdAt: number
  updatedAt: number
  messages: ChatMessage[]
}

export interface ChatConversationSummary {
  id: string
  title: string
  createdAt: number
  updatedAt: number
  modelName: string
}

export interface ChatHistoryIndex {
  version: number
  activeId: string
  conversations: ChatConversationSummary[]
}

export interface ChatHistorySearchResult extends ChatConversationSummary {
  messageId?: number
  excerpt: string
}

export function conversationTitle(text: string): string {
  return Array.from(text.trim().replace(/\s+/g, ' ')).slice(0, 32).join('') || '新对话'
}

export function historyGroup(timestamp: number, now: number = Date.now()): string {
  const today = new Date(now)
  today.setHours(0, 0, 0, 0)
  const date = new Date(timestamp)
  date.setHours(0, 0, 0, 0)
  const days = Math.round((today.getTime() - date.getTime()) / 86400000)
  return days <= 0 ? '今天' : days === 1 ? '昨天' : days < 7 ? '近七天' : '更早'
}

export function messageDate(timestamp: number): string {
  const date = new Date(timestamp)
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
}
