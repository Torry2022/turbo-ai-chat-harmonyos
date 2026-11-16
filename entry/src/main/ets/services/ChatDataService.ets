import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import picker from '@ohos.file.picker'
import statvfs from '@ohos.file.statvfs'
import zlib from '@ohos.zlib'
import util from '@ohos.util'
import { ChatArchive, CHAT_ARCHIVE_MANIFEST_MAX_BYTES, conversationMarkdown } from '../utils/chatArchive'
import { ChatMessage } from '../models/ChatTypes'
import { ChatConversation, ChatConversationOrigin } from '../models/ChatHistoryTypes'
import { inspectChatArchiveZip } from '../utils/chatArchiveZip'
import { ChatHistoryService } from './ChatHistoryService'

export interface PendingChatRestore {
  archive: ChatArchive
  directory: string
  workspace: string
}

export class ChatDataService {
  private cleanup?: Promise<void>

  private async workspace(context: common.UIAbilityContext): Promise<string> {
    if (this.cleanup === undefined) this.cleanup = this.clearAbandoned(context.cacheDir)
    await this.cleanup
    const directory = `${context.cacheDir}/chat-transfer-${Date.now()}-${Math.random().toString(36).substring(2, 10)}`
    await fs.mkdir(directory)
    return directory
  }

  async exportData(context: common.UIAbilityContext, history: ChatHistoryService, id?: string): Promise<boolean> {
    const workspace = await this.workspace(context)
    try {
      const directory = `${workspace}/backup`
      await fs.mkdir(directory)
      const archive = await history.exportArchive(directory, id)
      let name = `turbo-ai-chat-backup-${Date.now()}.zip`
      let suffix = '对话备份|.zip'
      let source = `${workspace}/export.zip`
      if (id !== undefined) {
        const record = archive.conversations[0]
        this.writeText(`${directory}/conversation.md`, conversationMarkdown(record))
        name = `${record.title.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_').substring(0, 60) || '对话'}`
        if (record.messages.every((message: ChatMessage) => message.imageUri === '')) {
          source = `${directory}/conversation.md`
          name += '.md'
          suffix = 'Markdown|.md'
        } else {
          await zlib.compressFile(directory, source, {})
          name += '.zip'
          suffix = '含图片的对话|.zip'
        }
      } else {
        const manifest = JSON.stringify(archive)
        if (new util.TextEncoder().encodeInto(manifest).byteLength > CHAT_ARCHIVE_MANIFEST_MAX_BYTES) {
          throw new Error('对话文本过多，超出当前备份格式的容量')
        }
        this.writeText(`${directory}/manifest.json`, manifest)
        await zlib.compressFile(directory, source, {})
      }
      const options = new picker.DocumentSaveOptions()
      options.newFileNames = [name]
      options.fileSuffixChoices = [suffix]
      const destinations = await new picker.DocumentViewPicker(context).save(options)
      if (destinations.length === 0) return false
      const target = fs.openSync(destinations[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try { await fs.copyFile(source, target.fd) } finally { fs.closeSync(target) }
      return true
    } finally {
      await this.removeDirectory(workspace)
    }
  }

  async prepareRestore(context: common.UIAbilityContext, history: ChatHistoryService): Promise<PendingChatRestore | undefined> {
    const options = new picker.DocumentSelectOptions()
    options.fileSuffixFilters = ['.zip']
    options.maxSelectNumber = 1
    const sources = await new picker.DocumentViewPicker(context).select(options)
    if (sources.length === 0) return undefined
    const workspace = await this.workspace(context)
    try {
      const zipPath = `${workspace}/backup.zip`
      const input = fs.openSync(sources[0], fs.OpenMode.READ_ONLY)
      try {
        if ((await fs.stat(input.fd)).size + 64 * 1024 * 1024 > await statvfs.getFreeSize(context.cacheDir)) {
          throw new Error('可用存储空间不足，请清理后重试')
        }
        await fs.copyFile(input.fd, zipPath)
      } finally { fs.closeSync(input) }
      const zip = fs.openSync(zipPath, fs.OpenMode.READ_ONLY)
      let expanded: number
      try {
        const size = (await fs.stat(zip.fd)).size
        expanded = inspectChatArchiveZip(size, (offset: number, length: number): Uint8Array => {
          if (offset < 0 || length < 0 || offset + length > size) throw new Error('备份文件不完整')
          const bytes = new Uint8Array(length)
          let read = 0
          while (read < length) {
            const chunk = new Uint8Array(length - read)
            const count = fs.readSync(zip.fd, chunk.buffer, { offset: offset + read, length: chunk.length })
            if (count <= 0) throw new Error('备份文件不完整')
            bytes.set(chunk.subarray(0, count), read)
            read += count
          }
          return bytes
        })
      } finally { fs.closeSync(zip) }
      if (expanded * 2 + 64 * 1024 * 1024 > await statvfs.getFreeSize(context.cacheDir)) {
        throw new Error('可用存储空间不足，请清理后重试')
      }
      const output = `${workspace}/unpacked`
      await fs.mkdir(output)
      await zlib.decompressFile(zipPath, output)
      const directory = await fs.access(`${output}/manifest.json`) ? output : `${output}/backup`
      const archive = history.validateArchive(await fs.readText(`${directory}/manifest.json`))
      if (archive.conversations.length === 0) throw new Error('备份中没有对话记录')
      for (const record of archive.conversations) {
        for (const message of record.messages) {
          if (message.imageUri && !(await fs.stat(`${directory}/${message.imageUri}`)).isFile()) {
            throw new Error('备份中的图片不完整')
          }
        }
      }
      return { archive, directory, workspace }
    } catch (error) {
      await this.removeDirectory(workspace)
      throw error as Error
    }
  }

  async clearRestore(pending: PendingChatRestore): Promise<void> {
    await this.removeDirectory(pending.workspace)
  }

  async createBranch(context: common.UIAbilityContext, history: ChatHistoryService,
    conversationId: string, messageId: number): Promise<ChatConversation> {
    const workspace = await this.workspace(context)
    try {
      const directory = `${workspace}/branch`
      await fs.mkdir(directory)
      const archive = await history.exportArchive(directory, conversationId, messageId)
      const record = archive.conversations[0]
      const origin: ChatConversationOrigin = { conversationId, messageId, title: record.title }
      record.title = `${record.title}（分支）`
      record.titleSource = 'manual'
      record.createdAt = Date.now()
      record.updatedAt = record.createdAt
      const restored = await history.restoreRecords(archive, directory, origin)
      return restored[0]
    } finally {
      await this.removeDirectory(workspace)
    }
  }

  private async clearAbandoned(cacheDir: string): Promise<void> {
    for (const name of await fs.listFile(cacheDir)) {
      if (/^chat-transfer-[0-9]+-[a-z0-9]+$/.test(name)) await this.removeDirectory(`${cacheDir}/${name}`)
    }
  }

  private writeText(path: string, text: string): void {
    const output = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      const bytes = new util.TextEncoder().encodeInto(text)
      let offset = 0
      while (offset < bytes.byteLength) {
        const written = fs.writeSync(output.fd, bytes.buffer.slice(offset))
        if (written <= 0) throw new Error('文件未能完整写入')
        offset += written
      }
      fs.fsyncSync(output.fd)
    } finally { fs.closeSync(output) }
  }

  private async removeDirectory(path: string): Promise<void> {
    for (const name of await fs.listFile(path)) {
      const child = `${path}/${name}`
      if ((await fs.stat(child)).isDirectory()) await this.removeDirectory(child)
      else await fs.unlink(child)
    }
    await fs.rmdir(path)
  }
}
