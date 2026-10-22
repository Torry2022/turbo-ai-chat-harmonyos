import fs from '@ohos.file.fs'
import { ChatMessage } from '../models/ChatTypes'
import { ChatConversation, ChatConversationSummary, ChatHistoryIndex, ChatHistorySearchResult } from '../models/ChatHistoryTypes'
import { parseAssistantText } from '../utils/thinking'
import { conversationTitleSignature } from './ConversationTitleService'
import { MarkdownBlock, MarkdownSpan, parseInlineMarkdown, parseLightMarkdown } from '../utils/markdown'

export class ChatHistoryService {
  warning: string = ''
  private root: string = ''
  private queue: Promise<void> = Promise.resolve()
  private summaries: ChatConversationSummary[] = []
  private activeId: string = ''
  private retiredIds: Set<string> = new Set()
  onAttachmentError: () => void = () => {}

  async initialize(filesDir: string): Promise<ChatHistoryIndex> {
    this.root = `${filesDir}/chat-history`
    return this.enqueue(async (): Promise<ChatHistoryIndex> => {
      await this.ensureDirectory(this.root)
      this.summaries = []
      try {
        const index = JSON.parse(await fs.readText(`${this.root}/index.json`)) as ChatHistoryIndex
        this.activeId = this.validId(index.activeId) ? index.activeId : ''
      } catch (_) {
        this.activeId = ''
      }
      // The index is a cache. Rebuild from records after interrupted writes.
      const names = await fs.listFile(this.root)
      let damaged = false
      for (const name of names) {
        if (!this.validId(name)) continue
        try {
          this.upsertSummary(await this.readRecord(name))
        } catch (_) {
          damaged = true
        }
      }
      if (!this.summaries.some((item: ChatConversationSummary) => item.id === this.activeId)) {
        this.activeId = ''
      }
      await this.writeIndex()
      this.warning = damaged ? '部分历史记录无法读取，其他对话已保留。' : ''
      return this.index()
    })
  }

  list(): ChatConversationSummary[] {
    return this.summaries.slice().sort((a: ChatConversationSummary, b: ChatConversationSummary) => b.updatedAt - a.updatedAt)
  }

  load(id: string): Promise<ChatConversation> {
    return this.enqueue(async (): Promise<ChatConversation> => {
      const record = await this.readRecord(id)
      this.activeId = id
      await this.writeIndex()
      return record
    })
  }

  search(query: string): Promise<ChatHistorySearchResult[]> {
    const needle = query.trim().replace(/\s+/g, ' ').toLowerCase()
    return this.enqueue(async (): Promise<ChatHistorySearchResult[]> => {
      if (needle.length === 0) return []
      const results: ChatHistorySearchResult[] = []
      for (const summary of this.list()) {
        try {
          const record = await this.readRecord(summary.id)
          let match: ChatHistorySearchResult | undefined = undefined
          for (const message of record.messages) {
            if (message.kind === 'notice' || (message.role !== 'user' && message.role !== 'assistant')) continue
            const text = this.searchText(message)
            const position = text.toLowerCase().indexOf(needle)
            if (position < 0) continue
            const start = Math.max(0, position - 18)
            const end = Math.min(text.length, Math.max(start + 90, position + needle.length))
            match = {
              id: summary.id, title: summary.title, createdAt: summary.createdAt, updatedAt: summary.updatedAt,
              modelName: summary.modelName, messageId: message.id,
              excerpt: `${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}`
            }
            break
          }
          if (match !== undefined) results.push(match)
          else if (record.title.toLowerCase().indexOf(needle) >= 0) {
            results.push({
              id: summary.id, title: summary.title, createdAt: summary.createdAt, updatedAt: summary.updatedAt,
              modelName: summary.modelName, excerpt: ''
            })
          }
        } catch (_) {
          // A damaged record must not prevent searching the remaining conversations.
        }
      }
      return results
    })
  }

  private searchText(message: ChatMessage): string {
    if (message.role === 'user') return message.content.replace(/\s+/g, ' ').trim()
    const inlineText = (text: string): string =>
      parseInlineMarkdown(text).map((span: MarkdownSpan) => span.text).join('')
    return parseLightMarkdown(parseAssistantText(message.content).answer).map((block: MarkdownBlock): string => {
      if (block.type === 'code') return block.text
      if (block.type === 'table') {
        return [block.headers ?? [], ...(block.rows ?? [])]
          .map((row: string[]) => row.map(inlineText).join(' ')).join(' ')
      }
      if (block.items.length > 0) return block.items.map(inlineText).join(' ')
      return inlineText(block.text)
    }).join(' ').replace(/\s+/g, ' ').trim()
  }

  save(conversation: ChatConversation): Promise<void> {
    // Capture now, before a queued write can observe another UI state.
    const snapshot = JSON.parse(JSON.stringify(conversation)) as ChatConversation
    return this.enqueue(async (): Promise<void> => {
      if (this.retiredIds.has(snapshot.id)) throw new Error('该对话已删除')
      const savedTitle = this.summaries.find((item: ChatConversationSummary) => item.id === snapshot.id)
      if (savedTitle?.titleSource === 'manual' ||
        (snapshot.titleSource === 'temporary' && savedTitle?.titleSource === 'generated')) {
        const latest = await this.readRecord(snapshot.id)
        if (latest.titleSource === 'manual' ||
          conversationTitleSignature(latest) === conversationTitleSignature(snapshot)) {
          snapshot.title = latest.title
          snapshot.titleSource = latest.titleSource
        }
      }
      let attachmentFailed = false
      const directory = this.directory(snapshot.id)
      await this.ensureDirectory(directory)
      for (const message of snapshot.messages) {
        if (!message.imageUri) continue
        const destination = `${directory}/image-${message.id}`
        if (message.imageUri === destination) continue
        let source: fs.File | undefined = undefined
        try {
          if (!await this.exists(destination)) {
            source = fs.openSync(message.imageUri, fs.OpenMode.READ_ONLY)
            await fs.copyFile(source.fd, destination)
          }
          message.imageUri = destination
          message.imageUnavailable = false
        } catch (_) {
          message.imageUri = ''
          message.imageUnavailable = true
          attachmentFailed = true
          this.onAttachmentError()
        } finally {
          if (source) fs.closeSync(source)
        }
      }
      await this.atomicWrite(`${directory}/conversation.json`, JSON.stringify(snapshot))
      this.upsertSummary(snapshot)
      this.activeId = snapshot.id
      await this.writeIndex()
      if (attachmentFailed) throw new Error('对话文字已保存，但有图片未能保存。请重试。')
    })
  }

  rename(id: string, title: string): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      const record = await this.readRecord(id)
      record.title = title.trim()
      record.titleSource = 'manual'
      if (!record.title) throw new Error('请输入对话名称')
      await this.atomicWrite(`${this.directory(id)}/conversation.json`, JSON.stringify(record))
      this.upsertSummary(record)
      await this.writeIndex()
    })
  }

  remove(id: string): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await this.removeRecord(id)
      await this.writeIndex()
    })
  }

  applyGeneratedTitle(id: string, signature: string, title: string, canApply: () => boolean): Promise<boolean> {
    return this.enqueue(async (): Promise<boolean> => {
      if (this.retiredIds.has(id) || !canApply()) return false
      const record = await this.readRecord(id)
      if (record.titleSource !== 'temporary' || conversationTitleSignature(record) !== signature || !canApply()) return false
      record.title = title
      record.titleSource = 'generated'
      await this.atomicWrite(`${this.directory(id)}/conversation.json`, JSON.stringify(record))
      this.upsertSummary(record)
      // Background naming must not change activeId or conversation chronology.
      await this.writeIndex()
      return true
    })
  }

  clear(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      for (const name of await fs.listFile(this.root)) {
        if (this.validId(name)) await this.removeRecord(name)
        else if (name.startsWith('.deleted-c-')) await this.removeDirectory(`${this.root}/${name}`)
      }
      this.activeId = ''
      await this.writeIndex()
    })
  }

  selectEmpty(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      this.activeId = ''
      await this.writeIndex()
    })
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const next = this.queue.then(task)
    this.queue = next.then(() => {}, () => {})
    return next
  }

  private validId(id: string): boolean {
    return typeof id === 'string' && /^c-[a-z0-9-]+$/.test(id)
  }

  private directory(id: string): string {
    if (!this.validId(id)) throw new Error('对话标识无效')
    return `${this.root}/${id}`
  }

  private async readRecord(id: string): Promise<ChatConversation> {
    const path = `${this.directory(id)}/conversation.json`
    try {
      return this.parseRecord(await fs.readText(path), id)
    } catch (_) {
      try {
        const record = this.parseRecord(await fs.readText(`${path}.bak`), id)
        // Preserve damaged data for recovery; never replace another conversation.
        if (await this.exists(path)) await fs.rename(path, `${path}.invalid-${Date.now()}`)
        await fs.rename(`${path}.bak`, path)
        return record
      } catch (_) {
        throw new Error('该对话暂时无法读取，记录仍保留在本机。')
      }
    }
  }

  private parseRecord(text: string, id: string): ChatConversation {
    const record = JSON.parse(text) as ChatConversation
    if (record.version !== 1 || record.id !== id || typeof record.title !== 'string' ||
      !Number.isFinite(record.createdAt) || !Number.isFinite(record.updatedAt) || !Array.isArray(record.messages)) {
      throw new Error('历史记录格式不兼容')
    }
    record.messages.forEach((message: ChatMessage) => {
      if (!Number.isInteger(message.id) || message.id < 1 || typeof message.content !== 'string' ||
        typeof message.role !== 'string' || typeof message.imageUri !== 'string') {
        throw new Error('历史消息格式不兼容')
      }
    })
    return record
  }

  private upsertSummary(record: ChatConversation): void {
    const replies = record.messages.filter((message: ChatMessage) => message.kind === 'message' && message.role === 'assistant')
    const summary: ChatConversationSummary = {
      id: record.id, title: record.title, titleSource: record.titleSource, createdAt: record.createdAt, updatedAt: record.updatedAt,
      modelName: replies.length > 0 ? replies[replies.length - 1].modelName ?? '' : ''
    }
    this.summaries = [...this.summaries.filter((item: ChatConversationSummary) => item.id !== record.id), summary]
  }

  private index(): ChatHistoryIndex {
    return { version: 1, activeId: this.activeId, conversations: this.list() }
  }

  private writeIndex(): Promise<void> {
    return this.atomicWrite(`${this.root}/index.json`, JSON.stringify(this.index()))
  }

  private async atomicWrite(path: string, content: string): Promise<void> {
    const temporary = `${path}.tmp`
    const backup = `${path}.bak`
    const file = fs.openSync(temporary, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      await fs.write(file.fd, content)
      await fs.fsync(file.fd)
    } finally {
      fs.closeSync(file)
    }
    if (await this.exists(backup)) await fs.unlink(backup)
    if (await this.exists(path)) await fs.rename(path, backup)
    try {
      await fs.rename(temporary, path)
    } catch (error) {
      if (!await this.exists(path) && await this.exists(backup)) await fs.rename(backup, path)
      throw new Error(`${error}`)
    }
  }

  private async removeRecord(id: string): Promise<void> {
    const directory = this.directory(id)
    const tombstone = `${this.root}/.deleted-${id}-${Date.now()}`
    if (await this.exists(directory)) await fs.rename(directory, tombstone)
    this.retiredIds.add(id)
    this.summaries = this.summaries.filter((item: ChatConversationSummary) => item.id !== id)
    if (this.activeId === id) this.activeId = ''
    if (await this.exists(tombstone)) await this.removeDirectory(tombstone)
  }

  private async removeDirectory(path: string): Promise<void> {
    const stat = await fs.stat(path)
    if (!stat.isDirectory()) {
      await fs.unlink(path)
      return
    }
    for (const name of await fs.listFile(path)) await this.removeDirectory(`${path}/${name}`)
    await fs.rmdir(path)
  }

  private async ensureDirectory(path: string): Promise<void> {
    if (!await this.exists(path)) await fs.mkdir(path, true)
  }

  private async exists(path: string): Promise<boolean> {
    try { return await fs.access(path) } catch (_) { return false }
  }
}
