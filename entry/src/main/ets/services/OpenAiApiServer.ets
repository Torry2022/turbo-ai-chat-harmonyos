import { decisionProbabilities, DecisionOutput } from '../utils/decisionOutput'
import { LAYA_MODEL_ID } from '../models/LayaModelConfig'
import { RerankResponse, RerankRequest, validateRerankRequest, rankScores } from '../utils/rerank'
import connection from '@ohos.net.connection'
import socket from '@ohos.net.socket'
import util from '@ohos.util'
import { ChatTurn, GenerationResult, GenerationSettings } from '../models/ChatTypes'
import { MAX_GENERATION_TOKENS } from '../models/ModelProfile'
import { RuntimeSample, StorageSample } from '../models/RuntimeStats'
import { parseAssistantText } from '../utils/thinking'

const MAX_REQUEST_BYTES: number = 1024 * 1024
const MAX_CONNECTIONS: number = 16
const REQUEST_READ_TIMEOUT_MS: number = 15000
const SEND_TIMEOUT_MS: number = 30000
const MAX_PENDING_SEND_BYTES: number = 4 * 1024 * 1024
const SERVER_OWNER: string = 'turbo-ai-chat'
const DECISION_MODEL_ID: string = LAYA_MODEL_ID

export interface ApiServerConfig {
  port: number
  requireApiKey: boolean
  apiKey: string
}

export interface ApiServerModel {
  id: string
  name: string
}

export interface ApiRuntimeModel extends ApiServerModel {
  requestedThreads?: number
  actualCpuThreads?: number
  loaded: boolean
  loading: boolean
  generating: boolean
}

export interface ApiRuntimeSnapshot {
  chatModel: ApiRuntimeModel
  rerankModel?: ApiRuntimeModel
  metrics: RuntimeSample
  storage: StorageSample
}

interface ApiRuntimeService {
  target: string
  inferenceBusy: boolean
}

interface ApiRuntimeResponse extends ApiRuntimeSnapshot {
  object: string
  service: ApiRuntimeService
}

export interface ApiGenerationRequest {
  turns: ChatTurn[]
  maxNewTokens: number
  settings: GenerationSettings
}

export interface ApiServerCallbacks {
  rerankModel: () => ApiServerModel | undefined
  rerank: (query: string, documents: string[]) => Promise<number[]>
  cancelRerank: () => void
  isRerankBusy: () => boolean
  isModelLoaded: () => boolean
  decisionModel?: () => ApiServerModel | undefined
  isDecisionLoaded: () => boolean
  isDecisionBusy: () => boolean
  isGenerationReady: () => boolean
  currentModel: () => ApiServerModel
  currentSettings: () => GenerationSettings
  currentMaxNewTokens: () => number
  runtimeSnapshot: () => Promise<ApiRuntimeSnapshot>
  generate: (request: ApiGenerationRequest, onChunk: (chunk: string) => void) => Promise<GenerationResult>
  decide: (request: PreparedApiDecision) => Promise<string>
  stopGeneration: () => void
  onRequestState: (kind: string, active: boolean) => void
  onStatus: (status: string) => void
  onLog: (level: string, message: string) => void
}

interface ApiContentPart {
  type?: string
  text?: string
  image_url?: string | ApiImageUrl
}

interface ApiImageUrl {
  url: string
}

interface ApiMessageInput {
  role?: string
  content?: string | ApiContentPart[]
}

interface ChatCompletionRequestBody {
  model?: string
  messages?: ApiMessageInput[]
  stream?: boolean
  stream_options?: ChatStreamOptions
  max_tokens?: number
  max_completion_tokens?: number
  temperature?: number
  top_p?: number
}

interface ChatStreamOptions {
  include_usage?: boolean
}

interface ResponsesRequestBody {
  model?: string
  instructions?: string
  input?: string | ApiMessageInput[]
  stream?: boolean
  max_output_tokens?: number
  temperature?: number
  top_p?: number
}

type ApiDecisionType = 'choice' | 'score' | 'boolean'
type LayaDecisionType = 'choice' | 'score' | 'noul'

interface ApiDecisionTask {
  type: ApiDecisionType
  instruction: string
  options?: Record<string, string>
  levels?: string[]
  criteria?: Record<string, string>
}

interface ApiDecisionBody {
  image?: string
  model?: string
  input: string
  task: ApiDecisionTask
}

export interface PreparedApiDecision {
  descriptions?: string[]
  image?: string
  state: string
  type: LayaDecisionType
  resultType: ApiDecisionType
  instruction: string
  labels: string[]
  options: string[]
}

interface ApiDecisionNativeResult extends DecisionOutput {
  probabilities?: number[]
  logits: number[]
  elapsed_ms: number
}

interface ApiDecisionAnswer {
  type: ApiDecisionType
  choice?: string
  score?: number
  value?: boolean
  probabilities: Record<string, number>
}

interface ApiDecisionMetadata {
  cpu_threads?: number
  input_tokens?: number
  task_calibrated: boolean
  elapsed_ms: number
}

interface ApiDecisionResponse {
  model: string
  result: ApiDecisionAnswer
  metadata: ApiDecisionMetadata
}

interface ParsedHttpRequest {
  method: string
  path: string
  headers: Map<string, string>
  body: string
}

interface ApiModelObject {
  id: string
  object: string
  created: number
  owned_by: string
}

interface ApiModelList {
  object: string
  data: ApiModelObject[]
}

interface ApiErrorObject {
  message: string
  type: string
  param: string | null
  code: string
}

interface ApiErrorResponse {
  error: ApiErrorObject
}

interface ApiStreamError {
  type: string
  code: string
  message: string
  param: string | null
}

interface ChatCompletionDelta {
  role?: string
  content?: string
  reasoning_content?: string
}

interface ChatCompletionStreamChoice {
  index: number
  delta: ChatCompletionDelta
  finish_reason: string | null
}

interface ChatCompletionStreamPayload {
  id: string
  object: string
  created: number
  model: string
  choices: ChatCompletionStreamChoice[]
  usage?: TokenUsage | null
}

interface ChatCompletionMessage {
  role: string
  content: string
  reasoning_content?: string
}

interface ChatCompletionChoice {
  index: number
  message: ChatCompletionMessage
  finish_reason: string
}

interface TokenUsage {
  prompt_tokens: number
  completion_tokens: number
  total_tokens: number
}

interface ChatCompletionPayload {
  id: string
  object: string
  created: number
  model: string
  choices: ChatCompletionChoice[]
  usage?: TokenUsage
}

interface ResponseOutputContent {
  type: string
  text: string
  annotations?: Object[]
}

interface ResponseOutputItem {
  id: string
  type: string
  status: string
  role?: string
  content: ResponseOutputContent[]
  summary?: Object[]
}

interface ResponseInputTokenDetails {
  cached_tokens: number
}

interface ResponseOutputTokenDetails {
  reasoning_tokens: number
}

interface ResponseUsage {
  input_tokens: number
  input_tokens_details: ResponseInputTokenDetails
  output_tokens: number
  output_tokens_details: ResponseOutputTokenDetails
  total_tokens: number
}

interface ApiStreamErrorEnvelope {
  error: ApiStreamError
}

interface ResponseGenerationError {
  code: string
  message: string
}

interface ResponseIncompleteDetails {
  reason: string
}

interface ResponsePayload {
  id: string
  object: string
  created_at: number
  status: string
  error: ResponseGenerationError | null
  incomplete_details: ResponseIncompleteDetails | null
  instructions: string | null
  model: string
  output: ResponseOutputItem[]
  parallel_tool_calls: boolean
  previous_response_id: string | null
  tools: Object[]
  tool_choice: string
  truncation: string
  usage?: ResponseUsage | null
}

interface ResponseCreatedEvent {
  type: string
  response: ResponsePayload
  sequence_number: number
}

interface ResponseOutputItemEvent {
  type: string
  output_index: number
  item: ResponseOutputItem
  sequence_number: number
}

interface ResponseContentPartEvent {
  type: string
  item_id: string
  output_index: number
  content_index: number
  part: ResponseOutputContent
  sequence_number: number
}

interface ResponseTextDeltaEvent {
  type: string
  item_id: string
  output_index: number
  content_index: number
  delta: string
  sequence_number: number
}

interface ResponseTextDoneEvent {
  type: string
  item_id: string
  output_index: number
  content_index: number
  text: string
  sequence_number: number
}

interface ResponsesStreamContext {
  responseId: string
  reasoningId: string
  messageId: string
  model: string
  created: number
  sequenceNumber: number
  reasoningStarted: boolean
  reasoningDone: boolean
  messageStarted: boolean
  reasoningText: string
  answerText: string
}

interface ResponseCompletedEvent {
  type: string
  response: ResponsePayload
  sequence_number: number
}

class HttpConnectionState {
  connection: socket.TCPSocketConnection
  decoder: util.TextDecoder = util.TextDecoder.create('utf-8')
  buffer: string = ''
  handled: boolean = false
  closed: boolean = false
  receivedBytes: number = 0
  private pending: string[] = []
  private pendingBytes: number = 0
  private sending: boolean = false
  private ending: boolean = false
  private readTimer: number = -1
  private sendTimer: number = -1
  private rejectSend?: (error: Error) => void
  private onClosed: () => void

  constructor(connectionValue: socket.TCPSocketConnection, onClosed: () => void) {
    this.connection = connectionValue
    this.onClosed = onClosed
    this.readTimer = setTimeout(() => this.close(), REQUEST_READ_TIMEOUT_MS)
  }

  append(message: ArrayBuffer): void {
    this.receivedBytes += message.byteLength
    this.buffer += this.decoder.decodeToString(new Uint8Array(message), { stream: true })
  }

  finishRequest(): void {
    this.handled = true
    clearTimeout(this.readTimer)
    this.readTimer = -1
    this.buffer = ''
  }

  send(data: string): void {
    if (this.closed || this.ending) return
    const bytes = utf8Length(data)
    if (this.pendingBytes + bytes > MAX_PENDING_SEND_BYTES) {
      this.close()
      return
    }
    this.pending.push(data)
    this.pendingBytes += bytes
    if (!this.sending) this.flush()
  }

  closeAfterSend(): void {
    this.ending = true
    if (!this.sending) this.close()
  }

  private async flush(): Promise<void> {
    this.sending = true
    try {
      while (!this.closed && this.pending.length > 0) {
        const data = this.pending.shift() as string
        await Promise.race([
          this.connection.send({ data, encoding: 'utf-8' }),
          new Promise<void>((_resolve, reject) => {
            this.rejectSend = reject
            this.sendTimer = setTimeout(() => reject(new Error('发送超时')), SEND_TIMEOUT_MS)
          })
        ])
        clearTimeout(this.sendTimer)
        this.sendTimer = -1
        this.rejectSend = undefined
        if (!this.closed) this.pendingBytes -= utf8Length(data)
      }
    } catch (_error) {
      this.close()
    } finally {
      this.sending = false
      if (this.ending) this.close()
    }
  }

  close(): void {
    if (this.closed) {
      return
    }
    this.closed = true
    clearTimeout(this.readTimer)
    clearTimeout(this.sendTimer)
    this.readTimer = -1
    this.sendTimer = -1
    this.rejectSend?.(new Error('连接已关闭'))
    this.rejectSend = undefined
    this.buffer = ''
    this.pending = []
    this.pendingBytes = 0
    this.onClosed()
    try {
      this.connection.close().catch((_err: Error) => {})
    } catch (_err) {
    }
  }
}

export interface ApiReasoningOutput {
  reasoning: string
  answer: string
}

export class ApiReasoningStreamFilter {
  private rawText: string = ''
  private emittedReasoning: string = ''
  private emittedAnswer: string = ''

  append(chunk: string): ApiReasoningOutput {
    this.rawText += chunk
    return this.nextDelta(false)
  }

  complete(text: string): ApiReasoningOutput {
    this.rawText = text
    return this.nextDelta(true)
  }

  output(): ApiReasoningOutput {
    return splitApiOutput(this.rawText, true)
  }

  private nextDelta(finalValue: boolean): ApiReasoningOutput {
    const output = splitApiOutput(this.rawText, finalValue)
    let reasoning = ''
    let answer = ''
    if (output.reasoning.startsWith(this.emittedReasoning)) {
      reasoning = output.reasoning.substring(this.emittedReasoning.length)
      this.emittedReasoning = output.reasoning
    }
    if (output.answer.startsWith(this.emittedAnswer)) {
      answer = output.answer.substring(this.emittedAnswer.length)
      this.emittedAnswer = output.answer
    }
    return { reasoning, answer }
  }
}

export class OpenAiApiServer {
  private callbacks: ApiServerCallbacks
  private server?: socket.TCPSocketServer
  private config: ApiServerConfig = { port: 8080, requireApiKey: true, apiKey: '' }
  private connections: Map<number, HttpConnectionState> = new Map()
  private rerankConnection?: HttpConnectionState
  private activeClientId: number = -1
  private activeConnection?: HttpConnectionState
  private activeRequestKind: 'chat' | 'decision' | '' = ''
  private running: boolean = false
  private lanAddress: string = ''

  constructor(callbacks: ApiServerCallbacks) {
    this.callbacks = callbacks
  }

  isRunning(): boolean {
    return this.running
  }

  baseUrl(): string {
    const host = this.lanAddress.length > 0 ? this.lanAddress : '设备局域网 IP'
    return `http://${host}:${this.config.port}`
  }

  async refreshLanAddress(port: number = this.config.port): Promise<string> {
    this.lanAddress = await resolveLanIpv4()
    const host = this.lanAddress.length > 0 ? this.lanAddress : '设备局域网 IP'
    return `http://${host}:${port}`
  }

  async start(config: ApiServerConfig): Promise<string> {
    if (this.running) {
      return this.baseUrl()
    }
    this.config = config
    this.lanAddress = await resolveLanIpv4()
    const server = socket.constructTCPSocketServerInstance()
    this.server = server
    try {
      server.on('connect', (client: socket.TCPSocketConnection) => {
        if (this.server !== server) {
          client.close().catch((_err: Error) => {})
          return
        }
        this.acceptClient(client)
      })
      server.on('error', (err: Error) => {
        this.callbacks.onStatus(`API 服务异常：${err.message}`)
        this.callbacks.onLog('ERROR', `服务异常：${errorMessage(err)}`)
      })
      await server.listen({ address: '0.0.0.0', family: 1, port: config.port })
    } catch (err) {
      this.server = undefined
      try {
        server.off('connect')
        server.off('error')
      } catch (_offError) {
      }
      await server.close().catch((_closeError: Error) => {
      })
      throw new Error(errorMessage(err))
    }
    this.running = true
    this.callbacks.onStatus('API 服务运行中')
    this.callbacks.onLog('INFO', `服务已启动，正在监听端口 ${config.port}`)
    return this.baseUrl()
  }

  async stop(): Promise<void> {
    if (this.rerankConnection !== undefined) this.callbacks.cancelRerank()
    if (!this.running && this.server === undefined) {
      return
    }
    if (this.activeClientId >= 0 && this.activeRequestKind === 'chat') {
      this.callbacks.stopGeneration()
    }
    this.connections.forEach((state: HttpConnectionState) => {
      state.close()
    })
    this.connections.clear()
    const server = this.server
    this.server = undefined
    this.running = false
    this.activeClientId = -1
    this.activeConnection = undefined
    this.activeRequestKind = ''
    if (server !== undefined) {
      server.off('connect')
      server.off('error')
      await server.close().catch((_err: Error) => {
      })
    }
    this.callbacks.onRequestState('', false)
    this.callbacks.onStatus('API 服务未启动')
    this.callbacks.onLog('INFO', '服务已停止')
  }

  private acceptClient(client: socket.TCPSocketConnection): void {
    if (this.connections.size >= MAX_CONNECTIONS) {
      client.close().catch((_err: Error) => {})
      return
    }
    const state = new HttpConnectionState(client, () => {
      if (this.connections.get(client.clientId) !== state) return
      this.connections.delete(client.clientId)
      if (this.rerankConnection === state) this.callbacks.cancelRerank()
      if (this.activeConnection === state && this.activeRequestKind === 'chat') {
        this.callbacks.stopGeneration()
      }
    })
    this.connections.set(client.clientId, state)
    try {
      client.on('message', (info: socket.SocketMessageInfo) => {
        const message = info.message !== undefined ? info.message : info as Object as ArrayBuffer
        this.handleClientData(state, message)
      })
      client.on('close', () => {
        state.close()
      })
      client.on('error', (_err: Error) => {
        state.close()
      })
    } catch (_err) {
      state.close()
      this.connections.delete(client.clientId)
    }
  }

  private handleClientData(state: HttpConnectionState, message: ArrayBuffer): void {
    if (state.handled || state.closed) {
      return
    }
    if (state.receivedBytes + message.byteLength > MAX_REQUEST_BYTES) {
      state.finishRequest()
      this.callbacks.onLog('ERROR', '413 HTTP request · 请求内容超过 1 MB')
      this.sendError(state, 413, 'request_too_large', '请求内容超过 1 MB。')
      return
    }
    state.append(message)
    let request: ParsedHttpRequest | undefined
    try {
      request = parseHttpRequest(state.buffer)
    } catch (err) {
      state.finishRequest()
      this.callbacks.onLog('ERROR', `400 HTTP request · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
      return
    }
    if (request === undefined) {
      return
    }
    state.finishRequest()
    this.route(state, request)
  }

  private route(state: HttpConnectionState, request: ParsedHttpRequest): void {
    if (request.path !== '/turbo/runtime') {
      this.callbacks.onLog('REQ', `${request.method} ${request.path}`)
    }
    if (request.method === 'OPTIONS') {
      this.sendEmpty(state, 204)
      this.callbacks.onLog('RESP', `204 OPTIONS ${request.path}`)
      return
    }
    if (!this.authorized(request)) {
      this.sendError(state, 401, 'invalid_api_key', 'API Key 无效。')
      this.callbacks.onLog('ERROR', `401 ${request.method} ${request.path} · API Key 无效`)
      return
    }
    if (request.method === 'GET' && request.path === '/v1/models') {
      this.sendModels(state)
      return
    }
    if (request.method === 'GET' && request.path === '/turbo/runtime') {
      this.sendRuntime(state)
      return
    }
    if (request.method === 'POST' && request.path === '/v1/rerank') {
      this.handleRerank(state, request.body)
      return
    }
    if (request.method === 'POST' && request.path === '/v1/chat/completions') {
      this.handleChatCompletions(state, request.body)
      return
    }
    if (request.method === 'POST' && request.path === '/v1/responses') {
      this.handleResponses(state, request.body)
      return
    }
    if (request.method === 'POST' && request.path === '/v1/decisions') {
      this.handleDecision(state, request.body)
      return
    }
    this.sendError(state, 404, 'not_found', '不支持该 API 路径。')
    this.callbacks.onLog('ERROR', `404 ${request.method} ${request.path}`)
  }

  private handleRerank(state: HttpConnectionState, body: string): void {
    let request: RerankRequest
    try {
      request = JSON.parse(body) as RerankRequest
      const invalid = validateRerankRequest(request)
      if (invalid.length > 0) throw new Error(invalid)
    } catch (_error) {
      this.sendError(state, 400, 'invalid_request', '请提供 query、1–64 段非空 documents 和有效的 top_n。')
      return
    }
    const model = this.callbacks.rerankModel()
    if (model === undefined) {
      this.sendError(state, 503, 'model_not_loaded', '请先在模型页加载重排模型。')
      return
    }
    if (request.model !== undefined && request.model !== model.id) {
      this.sendError(state, 400, 'model_not_found', 'model 与已加载的重排模型不匹配。')
      return
    }
    if (this.rerankConnection !== undefined || this.activeClientId >= 0 || this.callbacks.isRerankBusy()) {
      this.sendError(state, 409, 'model_busy', '正在处理其他推理请求，请稍后重试。')
      return
    }
    this.rerankConnection = state
    this.callbacks.onRequestState('rerank', true)
    this.callbacks.rerank(request.query, request.documents).then((scores: number[]) => {
      if (scores.length !== request.documents.length) throw new Error('重排结果数量不匹配')
      const results = rankScores(scores, request.top_n ?? scores.length)
      const response: RerankResponse = { model: model.id, results }
      if (!state.closed) this.sendJson(state, 200, response)
      this.callbacks.onLog('RESP', '200 POST /v1/rerank')
    }).catch((error: Error) => {
      const invalid = errorMessage(error).indexOf('exceeds the configured token limit') >= 0
      if (!state.closed) this.sendError(state, invalid ? 400 : 500, invalid ? 'input_too_long' : 'rerank_failed',
        invalid ? '输入超过重排模型的单条输入上限，请缩短问题或候选文本。' : '重排未完成，请检查模型状态后重试。')
      this.callbacks.onLog('ERROR', invalid ? '400 POST /v1/rerank：输入超长' : '重排未完成')
    }).finally(() => {
      if (this.rerankConnection === state) {
        this.rerankConnection = undefined
        this.callbacks.onRequestState('rerank', false)
      }
    })
  }

  private authorized(request: ParsedHttpRequest): boolean {
    if (!this.config.requireApiKey) {
      return true
    }
    return request.headers.get('authorization') === `Bearer ${this.config.apiKey}`
  }

  private sendModels(state: HttpConnectionState): void {
    const model = this.callbacks.currentModel()
    const data: ApiModelObject[] = []
    const reranker = this.callbacks.rerankModel()
    if (reranker !== undefined) data.push({ id: reranker.id, object: 'model', created: 0, owned_by: SERVER_OWNER })
    if (this.callbacks.isModelLoaded()) {
      data.push({ id: model.id, object: 'model', created: 0, owned_by: SERVER_OWNER })
    }
    if (this.callbacks.isDecisionLoaded()) {
      data.push({ id: this.callbacks.decisionModel?.()?.id ?? DECISION_MODEL_ID, object: 'model', created: 0, owned_by: SERVER_OWNER })
    }
    const payload: ApiModelList = { object: 'list', data }
    this.sendJson(state, 200, payload)
    this.callbacks.onLog('RESP', '200 GET /v1/models')
  }

  private sendRuntime(state: HttpConnectionState): void {
    this.callbacks.runtimeSnapshot().then((snapshot: ApiRuntimeSnapshot) => {
      if (state.closed) return
      const payload: ApiRuntimeResponse = {
        object: 'turbo.runtime',
        service: { target: 'all', inferenceBusy: this.activeClientId >= 0 || this.rerankConnection !== undefined },
        chatModel: snapshot.chatModel,
        metrics: snapshot.metrics,
        storage: snapshot.storage
      }
      this.sendJson(state, 200, payload)
    }).catch((_err: Error) => {
      if (state.closed) return
      this.sendError(state, 503, 'runtime_unavailable', '暂时无法读取运行状态，请稍后重试。')
      this.callbacks.onLog('ERROR', '503 GET /turbo/runtime · 读取运行状态失败')
    })
  }

  private handleChatCompletions(state: HttpConnectionState, bodyText: string): void {
    try {
      const value = JSON.parse(bodyText.replace(/^\uFEFF/, '')) as Object
      validateApiGenerationOptions(value, false)
      const body = value as ChatCompletionRequestBody
      const turns = parseMessages(body.messages)
      const request = this.buildGenerationRequest(
        turns,
        body.max_completion_tokens ?? body.max_tokens,
        body.temperature,
        body.top_p
      )
      this.runGeneration(state, body.model ?? '', body.stream === true, false, request,
        body.stream_options?.include_usage === true)
    } catch (err) {
      this.callbacks.onLog('ERROR', `400 POST /v1/chat/completions · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
    }
  }

  private handleResponses(state: HttpConnectionState, bodyText: string): void {
    try {
      const value = JSON.parse(bodyText.replace(/^\uFEFF/, '')) as Object
      validateApiGenerationOptions(value, true)
      const body = value as ResponsesRequestBody
      const turns = parseResponseInput(body.instructions ?? '', body.input)
      const request = this.buildGenerationRequest(
        turns,
        body.max_output_tokens,
        body.temperature,
        body.top_p
      )
      this.runGeneration(state, body.model ?? '', body.stream === true, true, request)
    } catch (err) {
      this.callbacks.onLog('ERROR', `400 POST /v1/responses · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
    }
  }

  private handleDecision(state: HttpConnectionState, bodyText: string): void {
    let request: PreparedApiDecision
    try {
      request = prepareApiDecision(bodyText, this.callbacks.decisionModel?.()?.id ?? DECISION_MODEL_ID)
    } catch (err) {
      this.callbacks.onLog('ERROR', `400 POST /v1/decisions · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
      return
    }
    if (!this.callbacks.isDecisionLoaded()) {
      this.callbacks.onLog('ERROR', '503 POST /v1/decisions · 决策模型未加载')
      this.sendError(state, 503, 'model_not_loaded', '请先在模型页加载决策模型。')
      return
    }
    if (this.activeClientId >= 0 || this.rerankConnection !== undefined) {
      this.callbacks.onLog('ERROR', '409 POST /v1/decisions · 当前已有 API 请求')
      this.sendError(state, 409, 'server_busy', '正在处理其他推理请求，请稍后重试。')
      return
    }
    if (this.callbacks.isDecisionBusy()) {
      this.sendError(state, 409, 'server_busy', '正在处理其他推理请求，请稍后重试。')
      return
    }
    const startedAt = Date.now()
    const clientId = state.connection.clientId
    this.activeClientId = clientId
    this.activeConnection = state
    this.activeRequestKind = 'decision'
    this.callbacks.onRequestState('decision', true)
    Promise.resolve().then(() => this.callbacks.decide(request)).then((raw: string) => {
      const response = formatApiDecision(request, raw, this.callbacks.decisionModel?.()?.id ?? DECISION_MODEL_ID)
      if (!state.closed) this.sendJson(state, 200, response)
      this.callbacks.onLog('RESP', `200 POST /v1/decisions · ${Date.now() - startedAt} ms`)
    }).catch((err: Error) => {
      const status = err.name === 'InvalidImageError' ? 400 : 500
      const code = status === 400 ? 'invalid_request_error' : 'decision_failed'
      if (!state.closed) this.sendError(state, status, code, errorMessage(err))
      this.callbacks.onLog('ERROR', `${status} POST /v1/decisions · ${errorMessage(err)}`)
    }).finally(() => {
      if (this.activeConnection === state && this.activeRequestKind === 'decision') {
        this.activeClientId = -1
        this.activeConnection = undefined
        this.activeRequestKind = ''
        this.callbacks.onRequestState('decision', false)
      }
    })
  }

  private buildGenerationRequest(
    turns: ChatTurn[],
    requestedMaxTokens?: number,
    requestedTemperature?: number,
    requestedTopP?: number
  ): ApiGenerationRequest {
    const images = turns.filter((turn: ChatTurn) => (turn.imageUri ?? '').length > 0)
    if (images.length > 1) throw new Error('当前每次请求支持一张图片。')
    const defaults = this.callbacks.currentSettings()
    const defaultMaxTokens = this.callbacks.currentMaxNewTokens()
    return {
      turns,
      maxNewTokens: clampInteger(requestedMaxTokens, defaultMaxTokens, 1, MAX_GENERATION_TOKENS),
      settings: {
        temperature: clampNumber(requestedTemperature, defaults.temperature, 0, 2),
        topP: clampNumber(requestedTopP, defaults.topP, 0, 1),
        topK: defaults.topK,
        repetitionPenalty: defaults.repetitionPenalty,
        frequencyPenalty: defaults.frequencyPenalty,
        presencePenalty: defaults.presencePenalty,
        penaltyWindow: defaults.penaltyWindow,
        thinkingEnabled: defaults.thinkingEnabled
      }
    }
  }

  private runGeneration(
    state: HttpConnectionState,
    requestedModel: string,
    streaming: boolean,
    responsesApi: boolean,
    request: ApiGenerationRequest,
    includeUsage: boolean = false
  ): void {
    const apiPath = responsesApi ? '/v1/responses' : '/v1/chat/completions'
    if (!this.callbacks.isModelLoaded()) {
      this.callbacks.onLog('ERROR', `503 POST ${apiPath} · 对话模型未加载`)
      this.sendError(state, 503, 'model_not_ready', '请先在模型页加载对话模型。')
      return
    }
    if (this.activeClientId >= 0 || this.rerankConnection !== undefined || !this.callbacks.isGenerationReady()) {
      this.callbacks.onLog('ERROR', `409 POST ${apiPath} · 当前已有模型任务`)
      this.sendError(state, 409, 'server_busy', '当前有模型任务正在执行，请稍后重试。')
      return
    }
    const model = this.callbacks.currentModel()
    if (requestedModel.length > 0 && requestedModel !== model.id && requestedModel !== model.name) {
      this.callbacks.onLog('ERROR', `400 POST ${apiPath} · 模型 ${requestedModel} 不可用`)
      this.sendError(state, 400, 'model_not_found', `当前仅提供模型 ${model.id}。`)
      return
    }

    const startedAt = Date.now()
    this.activeClientId = state.connection.clientId
    this.activeConnection = state
    this.activeRequestKind = 'chat'
    const created = Math.floor(Date.now() / 1000)
    const responseId = `resp_${created}_${state.connection.clientId}`
    const reasoningId = `rs_${created}_${state.connection.clientId}`
    const messageId = `msg_${created}_${state.connection.clientId}`
    const filter = new ApiReasoningStreamFilter()
    const responsesContext: ResponsesStreamContext = {
      responseId,
      reasoningId,
      messageId,
      model: model.id,
      created,
      sequenceNumber: 0,
      reasoningStarted: false,
      reasoningDone: false,
      messageStarted: false,
      reasoningText: '',
      answerText: ''
    }
    if (streaming) {
      this.sendStreamHeaders(state)
      if (responsesApi) {
        this.sendResponsesStart(state, responsesContext)
      } else {
        this.sendChatChunk(state, responseId, model.id, created, { reasoning: '', answer: '' }, 'assistant', undefined, includeUsage)
      }
    }

    this.callbacks.onRequestState('chat', true)
    this.callbacks.onLog(
      'INFO',
      `model=${model.id}, stream=${streaming}, maxTokens=${request.maxNewTokens}`
    )
    let completed = false
    this.callbacks.generate(request, (chunk: string) => {
      if (completed || state.closed) return
      const delta = filter.append(chunk)
      if (!streaming || (delta.reasoning.length <= 0 && delta.answer.length <= 0) || state.closed) {
        return
      }
      if (responsesApi) {
        this.sendResponsesDelta(state, responsesContext, delta)
      } else {
        if (delta.reasoning.length > 0) {
          this.sendChatChunk(
            state, responseId, model.id, created, { reasoning: delta.reasoning, answer: '' }, undefined, undefined, includeUsage
          )
        }
        if (delta.answer.length > 0) {
          this.sendChatChunk(state, responseId, model.id, created, { reasoning: '', answer: delta.answer }, undefined, undefined, includeUsage)
        }
      }
    }).then((result: GenerationResult) => {
      completed = true
      if (!responsesApi && result.stopReason !== 'eos' && result.stopReason !== 'max_tokens') {
        throw new Error(generationFailureMessage(result))
      }
      const finalDelta = filter.complete(result.text)
      if (streaming && (finalDelta.reasoning.length > 0 || finalDelta.answer.length > 0) && !state.closed) {
        if (responsesApi) {
          this.sendResponsesDelta(state, responsesContext, finalDelta)
        } else {
          if (finalDelta.reasoning.length > 0) {
            this.sendChatChunk(
              state, responseId, model.id, created, { reasoning: finalDelta.reasoning, answer: '' }, undefined, undefined, includeUsage
            )
          }
          if (finalDelta.answer.length > 0) {
            this.sendChatChunk(
              state, responseId, model.id, created, { reasoning: '', answer: finalDelta.answer }, undefined, undefined, includeUsage
            )
          }
        }
      }
      const output = filter.output()
      if (!state.closed) {
        if (streaming) {
          if (responsesApi) {
            this.sendResponsesDone(state, responsesContext, output, result)
          } else {
            this.sendChatChunk(
              state, responseId, model.id, created, { reasoning: '', answer: '' }, undefined,
              finishReason(result), includeUsage
            )
            if (includeUsage) {
              const counted = chatCompletionObject(responseId, model.id, created, output, result)
              const usageChunk: ChatCompletionStreamPayload = {
                id: responseId, object: 'chat.completion.chunk', created, model: model.id,
                choices: [], usage: counted.usage ?? null
              }
              state.send(`data: ${JSON.stringify(usageChunk)}\n\n`)
            }
            state.send('data: [DONE]\n\n')
            state.closeAfterSend()
          }
        } else if (responsesApi) {
          this.sendJson(
            state, 200,
            responsesObject(responseId, reasoningId, messageId, model.id, created, output, result)
          )
        } else {
          this.sendJson(state, 200, chatCompletionObject(responseId, model.id, created, output, result))
        }
      }
      if (this.activeConnection === state) {
        this.activeClientId = -1
        this.activeConnection = undefined
        this.activeRequestKind = ''
        this.callbacks.onRequestState('chat', false)
      }
      const streamLabel = streaming ? ' (stream)' : ''
      this.callbacks.onLog(
        'RESP',
        `200 POST ${apiPath}${streamLabel} · ${Date.now() - startedAt} ms · ` +
          `${result.generatedTokens} tokens · ${output.answer.length} chars`
      )
    }).catch((err: Error) => {
      completed = true
      const invalidImage = err.name === 'InvalidImageError'
      if (!state.closed) {
        if (streaming) {
          const payload: ApiStreamError = {
            type: 'error', code: invalidImage ? 'invalid_request_error' : 'generation_failed', message: errorMessage(err), param: null
          }
          const event: Object = responsesApi ? payload : { error: payload } as ApiStreamErrorEnvelope
          state.send(`event: error\ndata: ${JSON.stringify(event)}\n\n`)
          state.closeAfterSend()
        } else {
          this.sendError(state, invalidImage ? 400 : 500, invalidImage ? 'invalid_request_error' : 'generation_failed', errorMessage(err))
        }
      }
      if (this.activeConnection === state) {
        this.activeClientId = -1
        this.activeConnection = undefined
        this.activeRequestKind = ''
        this.callbacks.onRequestState('chat', false)
      }
      this.callbacks.onLog('ERROR', `${invalidImage ? 400 : 500} POST ${apiPath} · ${errorMessage(err)}`)
    })
  }

  private sendChatChunk(
    state: HttpConnectionState,
    id: string,
    model: string,
    created: number,
    output: ApiReasoningOutput,
    role?: string,
    finishReasonValue?: string,
    includeUsage: boolean = false
  ): void {
    const delta: ChatCompletionDelta = {}
    if (role !== undefined) {
      delta.role = role
      delta.content = ''
    }
    if (output.reasoning.length > 0) {
      delta.reasoning_content = output.reasoning
    }
    if (output.answer.length > 0) {
      delta.content = output.answer
    }
    const choice: ChatCompletionStreamChoice = {
      index: 0,
      delta,
      finish_reason: finishReasonValue ?? null
    }
    const payload: ChatCompletionStreamPayload = {
      id,
      object: 'chat.completion.chunk',
      created,
      model,
      choices: [choice]
    }
    if (includeUsage) payload.usage = null
    state.send(`data: ${JSON.stringify(payload)}\n\n`)
  }

  private sendResponsesStart(
    state: HttpConnectionState,
    context: ResponsesStreamContext
  ): void {
    const response = responseBase(context.responseId, context.model, context.created, 'in_progress', [])
    const createdEvent: ResponseCreatedEvent = { type: 'response.created', response, sequence_number: 0 }
    this.sendResponseEvent(state, 'response.created', createdEvent)
    context.sequenceNumber = 1
  }

  private startResponsesReasoning(state: HttpConnectionState, context: ResponsesStreamContext): void {
    if (context.reasoningStarted) {
      return
    }
    context.reasoningStarted = true
    const item: ResponseOutputItem = {
      id: context.reasoningId,
      type: 'reasoning',
      status: 'in_progress',
      content: [],
      summary: []
    }
    const itemEvent: ResponseOutputItemEvent = {
      type: 'response.output_item.added',
      output_index: 0,
      item,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_item.added', itemEvent)
    const part: ResponseOutputContent = { type: 'reasoning_text', text: '' }
    const partEvent: ResponseContentPartEvent = {
      type: 'response.content_part.added',
      item_id: context.reasoningId,
      output_index: 0,
      content_index: 0,
      part,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.content_part.added', partEvent)
  }

  private finishResponsesReasoning(state: HttpConnectionState, context: ResponsesStreamContext, status: string = 'completed'): void {
    if (!context.reasoningStarted || context.reasoningDone) {
      return
    }
    context.reasoningDone = true
    const content: ResponseOutputContent = { type: 'reasoning_text', text: context.reasoningText }
    const textDoneEvent: ResponseTextDoneEvent = {
      type: 'response.reasoning_text.done',
      item_id: context.reasoningId,
      output_index: 0,
      content_index: 0,
      text: context.reasoningText,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.reasoning_text.done', textDoneEvent)
    const contentDoneEvent: ResponseContentPartEvent = {
      type: 'response.content_part.done',
      item_id: context.reasoningId,
      output_index: 0,
      content_index: 0,
      part: content,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.content_part.done', contentDoneEvent)
    const item: ResponseOutputItem = {
      id: context.reasoningId,
      type: 'reasoning',
      status,
      content: [content],
      summary: []
    }
    const itemDoneEvent: ResponseOutputItemEvent = {
      type: 'response.output_item.done',
      output_index: 0,
      item,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_item.done', itemDoneEvent)
  }

  private startResponsesMessage(state: HttpConnectionState, context: ResponsesStreamContext): void {
    if (context.messageStarted) {
      return
    }
    context.messageStarted = true
    const outputIndex = context.reasoningStarted ? 1 : 0
    const item: ResponseOutputItem = {
      id: context.messageId, type: 'message', status: 'in_progress', role: 'assistant', content: []
    }
    const itemEvent: ResponseOutputItemEvent = {
      type: 'response.output_item.added', output_index: outputIndex, item,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_item.added', itemEvent)
    const part: ResponseOutputContent = { type: 'output_text', text: '', annotations: [] }
    const partEvent: ResponseContentPartEvent = {
      type: 'response.content_part.added',
      item_id: context.messageId,
      output_index: outputIndex,
      content_index: 0,
      part,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.content_part.added', partEvent)
  }

  private sendResponsesDelta(
    state: HttpConnectionState,
    context: ResponsesStreamContext,
    delta: ApiReasoningOutput
  ): void {
    if (delta.reasoning.length > 0) {
      this.startResponsesReasoning(state, context)
      context.reasoningText += delta.reasoning
      const event: ResponseTextDeltaEvent = {
        type: 'response.reasoning_text.delta',
        item_id: context.reasoningId,
        output_index: 0,
        content_index: 0,
        delta: delta.reasoning,
        sequence_number: context.sequenceNumber++
      }
      this.sendResponseEvent(state, 'response.reasoning_text.delta', event)
    }
    if (delta.answer.length > 0) {
      this.finishResponsesReasoning(state, context)
      this.startResponsesMessage(state, context)
      context.answerText += delta.answer
      const outputIndex = context.reasoningStarted ? 1 : 0
      const event: ResponseTextDeltaEvent = {
        type: 'response.output_text.delta',
        item_id: context.messageId,
        output_index: outputIndex,
        content_index: 0,
        delta: delta.answer,
        sequence_number: context.sequenceNumber++
      }
      this.sendResponseEvent(state, 'response.output_text.delta', event)
    }
  }

  private sendResponsesDone(
    state: HttpConnectionState,
    context: ResponsesStreamContext,
    output: ApiReasoningOutput,
    result: GenerationResult
  ): void {
    const response = responsesObject(
      context.responseId, context.reasoningId, context.messageId, context.model, context.created, output, result
    )
    context.reasoningText = output.reasoning
    context.answerText = output.answer
    if (output.reasoning.length > 0) {
      this.startResponsesReasoning(state, context)
    }
    this.finishResponsesReasoning(state, context, parseAssistantText(result.text).thinkingClosed ? 'completed' : 'incomplete')
    this.startResponsesMessage(state, context)
    const outputIndex = context.reasoningStarted ? 1 : 0
    const content: ResponseOutputContent = { type: 'output_text', text: output.answer, annotations: [] }
    const textDoneEvent: ResponseTextDoneEvent = {
      type: 'response.output_text.done', item_id: context.messageId, output_index: outputIndex, content_index: 0,
      text: output.answer, sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_text.done', textDoneEvent)
    const contentDoneEvent: ResponseContentPartEvent = {
      type: 'response.content_part.done', item_id: context.messageId, output_index: outputIndex, content_index: 0,
      part: content, sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.content_part.done', contentDoneEvent)
    const item: ResponseOutputItem = {
      id: context.messageId, type: 'message', status: response.status === 'completed' ? 'completed' : 'incomplete',
      role: 'assistant', content: [content]
    }
    const itemDoneEvent: ResponseOutputItemEvent = {
      type: 'response.output_item.done', output_index: outputIndex, item,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_item.done', itemDoneEvent)
    const completedEvent: ResponseCompletedEvent = {
      type: `response.${response.status}`, response, sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, completedEvent.type, completedEvent)
    state.closeAfterSend()
  }

  private sendResponseEvent(state: HttpConnectionState, eventName: string, payload: Object): void {
    state.send(`event: ${eventName}\ndata: ${JSON.stringify(payload)}\n\n`)
  }

  private sendStreamHeaders(state: HttpConnectionState): void {
    state.send(httpHeaders(200, 'text/event-stream; charset=utf-8', false))
  }

  private sendJson(state: HttpConnectionState, statusCode: number, payload: Object): void {
    const body = JSON.stringify(payload)
    state.send(httpHeaders(statusCode, 'application/json; charset=utf-8', true, utf8Length(body)) + body)
    state.closeAfterSend()
  }

  private sendError(state: HttpConnectionState, statusCode: number, code: string, message: string): void {
    const error: ApiErrorObject = { message, type: code, param: null, code }
    const payload: ApiErrorResponse = { error }
    this.sendJson(state, statusCode, payload)
  }

  private sendEmpty(state: HttpConnectionState, statusCode: number): void {
    state.send(httpHeaders(statusCode, 'text/plain; charset=utf-8', true, 0))
    state.closeAfterSend()
  }
}

export function prepareApiDecision(bodyText: string, modelId: string = DECISION_MODEL_ID): PreparedApiDecision {
  const body = JSON.parse(bodyText.replace(/^\uFEFF/, '')) as ApiDecisionBody
  if (body === null || typeof body !== 'object' || typeof body.input !== 'string' || (body.input.trim().length === 0 && !body.image) ||
    body.task === undefined || body.task === null ||
    typeof body.task.instruction !== 'string' || body.task.instruction.trim().length === 0) {
    throw new Error('请填写 input 和 task.instruction。')
  }
  if (body.model !== undefined && body.model !== modelId) {
    throw new Error(`当前已加载的决策模型为 ${modelId}。`)
  }
  if (body.image !== undefined && (modelId === DECISION_MODEL_ID || typeof body.image !== 'string' ||
    !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(body.image))) {
    throw new Error(modelId === DECISION_MODEL_ID ? '当前决策模型不支持图片。' : 'image 应为 PNG、JPEG 或 WebP 的 Base64 数据 URI。')
  }
  const maximum = modelId === DECISION_MODEL_ID ? 20 : 255
  const descriptions: string[] = []
  const task = body.task
  const labels: string[] = []
  const options: string[] = []
  if (task.type === 'choice') {
    if (task.options === undefined || task.options === null || Array.isArray(task.options) ||
      typeof task.options !== 'object') {
      throw new Error('选择题的 task.options 应为候选项对象。')
    }
    const criteria = task.options as Record<string, string>
    for (const label of Object.keys(criteria)) {
      if (label.trim().length === 0 || typeof criteria[label] !== 'string') {
        throw new Error('候选项须包含非空标签和文本。')
      }
      const description = criteria[label].trim()
      descriptions.push(description.length > 0 ? description : label)
      labels.push(label)
      options.push(description.length > 0 ? `${label}: ${description}` : label)
    }
    if (labels.length < 2) throw new Error('选择题至少需要两个候选项。')
    if (labels.length > maximum) throw new Error(`选择题最多支持 ${maximum} 个候选项。`)
  } else if (task.type === 'score') {
    if (!Array.isArray(task.levels) || task.levels.length < 2) {
      throw new Error('评分题的 task.levels 至少需要两个等级。')
    }
    if (task.levels.length > maximum) throw new Error(`评分题最多支持 ${maximum} 个等级。`)
    const criteria = task.levels as string[]
    for (let index = 0; index < criteria.length; index++) {
      if (typeof criteria[index] !== 'string' || criteria[index].trim().length === 0) {
        throw new Error('评分等级不能为空。')
      }
      descriptions.push(criteria[index].trim())
      labels.push(`等级 ${index}`)
      options.push(`level ${index}: ${criteria[index].trim()}`)
    }
  } else if (task.type === 'boolean') {
    if (task.criteria !== undefined && task.criteria !== null &&
      (Array.isArray(task.criteria) || typeof task.criteria !== 'object')) {
      throw new Error('判断题的 task.criteria 应为可选的判断标准对象。')
    }
    const criteria = (task.criteria ?? {}) as Record<string, string>
    const falseText = criteria['false'] ?? 'no, the statement does not hold'
    const trueText = criteria['true'] ?? 'yes, the statement holds'
    if (typeof falseText !== 'string' || typeof trueText !== 'string') {
      throw new Error('判断标准须为文本。')
    }
    descriptions.push(falseText, trueText)
    labels.push('否', '是')
    options.push(`false: ${falseText}`, `true: ${trueText}`)
  } else {
    throw new Error('task.type 只支持 choice、score 或 boolean。')
  }
  const prepared: PreparedApiDecision = {
    state: body.input.trim(), type: task.type === 'boolean' ? 'noul' : task.type,
    resultType: task.type, instruction: task.instruction.trim(), labels, options
  }
  if (modelId !== DECISION_MODEL_ID) prepared.descriptions = descriptions
  if (body.image !== undefined) prepared.image = body.image
  return prepared
}

export function formatApiDecision(request: PreparedApiDecision, raw: string, modelId: string = DECISION_MODEL_ID): ApiDecisionResponse {
  const result = JSON.parse(raw) as ApiDecisionNativeResult
  const weights = decisionProbabilities(result, request.labels.length)
  const total = weights.reduce((sum: number, value: number) => sum + value, 0)
  const probabilities: Record<string, number> = {}
  for (let index = 0; index < weights.length; index++) {
    const key = request.type === 'choice' ? request.labels[index] :
      request.type === 'score' ? `${index}` : index === 0 ? 'false' : 'true'
    probabilities[key] = weights[index]
  }
  const answer: ApiDecisionAnswer = { type: request.resultType, probabilities }
  if (request.type === 'choice') answer.choice = request.labels[weights.indexOf(Math.max(...weights))]
  else if (request.type === 'score') {
    answer.score = Number((weights.reduce((sum: number, value: number, index: number) =>
      sum + index * value, 0) / total).toFixed(4))
  } else answer.value = weights[1] >= weights[0]
  const metadata: ApiDecisionMetadata = { task_calibrated: false, elapsed_ms: result.elapsed_ms }
  if (result.input_tokens !== undefined) {
    if (!Number.isSafeInteger(result.input_tokens) || result.input_tokens < 0)
      throw new Error('模型返回的输入词元数无效')
    metadata.input_tokens = result.input_tokens
  }
  if (result.cpu_threads !== undefined) {
    if (!Number.isInteger(result.cpu_threads) || result.cpu_threads < 1 || result.cpu_threads > 16)
      throw new Error('模型返回的实际线程数无效')
    metadata.cpu_threads = result.cpu_threads
  }
  return { model: modelId, result: answer, metadata }
}

export function splitApiOutput(rawText: string, finalValue: boolean): ApiReasoningOutput {
  const normalized = rawText
  const trimmedStart = normalized.trimStart()
  if (!finalValue && trimmedStart.length > 0 && '<think>'.startsWith(trimmedStart)) {
    return { reasoning: '', answer: '' }
  }
  const openTag = '<think>'
  const closeTag = '</think>'
  const prefixLength = normalized.length - trimmedStart.length
  const openIndex = normalized.startsWith(openTag, prefixLength) ? prefixLength : -1
  if (openIndex >= 0) {
    const afterOpen = normalized.substring(openIndex + openTag.length)
    if (afterOpen.indexOf(closeTag) < 0) {
      return {
        reasoning: withoutPartialSuffix(afterOpen, closeTag).trim(),
        answer: normalized.substring(0, openIndex).trim()
      }
    }
  }
  const parts = parseAssistantText(normalized)
  if (parts.hasThinking) {
    return { reasoning: parts.thinking, answer: parts.answer }
  }
  return {
    reasoning: '',
    answer: normalized
  }
}

export function visibleAnswer(rawText: string, finalValue: boolean): string {
  return splitApiOutput(rawText, finalValue).answer
}

function withoutPartialSuffix(value: string, marker: string): string {
  const maxLength = Math.min(value.length, marker.length - 1)
  for (let length = maxLength; length > 0; length--) {
    if (marker.startsWith(value.substring(value.length - length))) {
      return value.substring(0, value.length - length)
    }
  }
  return value
}

function parseHttpRequest(buffer: string): ParsedHttpRequest | undefined {
  const headerEnd = buffer.indexOf('\r\n\r\n')
  if (headerEnd < 0) {
    return undefined
  }
  const headerText = buffer.substring(0, headerEnd)
  const lines = headerText.split('\r\n')
  if (lines.length <= 0) {
    throw new Error('HTTP 请求头为空。')
  }
  const requestParts = lines[0].split(' ')
  if (requestParts.length < 2) {
    throw new Error('HTTP 请求行无效。')
  }
  const headers: Map<string, string> = new Map()
  for (let index = 1; index < lines.length; index++) {
    const separator = lines[index].indexOf(':')
    if (separator <= 0) {
      continue
    }
    headers.set(lines[index].substring(0, separator).trim().toLowerCase(), lines[index].substring(separator + 1).trim())
  }
  const contentLengthText = headers.get('content-length') ?? '0'
  const contentLength = Number.parseInt(contentLengthText, 10)
  if (!Number.isFinite(contentLength) || contentLength < 0 || contentLength > MAX_REQUEST_BYTES) {
    throw new Error('Content-Length 无效。')
  }
  const body = buffer.substring(headerEnd + 4)
  if (utf8Length(body) < contentLength) {
    return undefined
  }
  const path = requestParts[1].split('?')[0]
  return { method: requestParts[0].toUpperCase(), path, headers, body }
}

function parseMessages(messages?: ApiMessageInput[]): ChatTurn[] {
  if (messages === undefined || !Array.isArray(messages) || messages.length <= 0) {
    throw new Error('messages 不能为空。')
  }
  const turns: ChatTurn[] = []
  for (let index = 0; index < messages.length; index++) {
    turns.push(parseMessage(messages[index]))
  }
  return turns
}

function parseResponseInput(instructions: string, input?: string | ApiMessageInput[]): ChatTurn[] {
  const turns: ChatTurn[] = []
  if (instructions.trim().length > 0) {
    turns.push({ role: 'system', content: instructions.trim() })
  }
  if (typeof input === 'string') {
    if (input.trim().length <= 0) {
      throw new Error('input 不能为空。')
    }
    turns.push({ role: 'user', content: input })
    return turns
  }
  if (input === undefined || !Array.isArray(input) || input.length <= 0) {
    throw new Error('input 不能为空。')
  }
  for (let index = 0; index < input.length; index++) {
    turns.push(parseMessage(input[index]))
  }
  return turns
}

function parseMessage(message: ApiMessageInput): ChatTurn {
  const role = normalizeRole(message.role ?? '')
  const content = contentText(message.content)
  let imageUri = ''
  if (Array.isArray(message.content)) {
    for (const part of message.content) {
      if (part.type !== 'image_url' && part.type !== 'input_image') continue
      if (role !== 'user') throw new Error('图片只能放在用户消息中。')
      if (imageUri.length > 0) throw new Error('当前每次请求支持一张图片。')
      const value = part.image_url
      imageUri = typeof value === 'string' ? value : value?.url ?? ''
      if (imageUri.length === 0) throw new Error('请提供图片地址或 Base64 图片。')
      if (!/^https?:\/\//i.test(imageUri) && !/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(imageUri)) {
        throw new Error('请提供图片的 HTTP 地址或 PNG、JPEG、WebP Base64 数据。')
      }
    }
  }
  if (content.length <= 0) {
    if (imageUri.length === 0) throw new Error('消息内容不能为空。')
  }
  return { role, content: content.length > 0 ? content : '请描述这张图片。', imageUri }
}

function normalizeRole(role: string): string {
  if (role === 'developer') {
    return 'system'
  }
  if (role === 'system' || role === 'user' || role === 'assistant') {
    return role
  }
  throw new Error(`暂不支持消息角色 ${role}。`)
}

function contentText(content?: string | ApiContentPart[]): string {
  if (typeof content === 'string') {
    return content.trim()
  }
  if (content === undefined || !Array.isArray(content)) {
    return ''
  }
  const texts: string[] = []
  for (let index = 0; index < content.length; index++) {
    const part = content[index]
    if (part.type === 'text' || part.type === 'input_text' || part.type === 'output_text') {
      if (part.text !== undefined && part.text.trim().length > 0) {
        texts.push(part.text.trim())
      }
      continue
    }
    if (part.type === 'image_url' || part.type === 'input_image') continue
    throw new Error('消息包含不支持的内容类型。')
  }
  return texts.join('\n')
}

function clampInteger(value: number | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || !Number.isFinite(value)) {
    return Math.max(min, Math.min(max, Math.round(fallback)))
  }
  return Math.max(min, Math.min(max, Math.round(value)))
}

function clampNumber(value: number | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || !Number.isFinite(value)) {
    return Math.max(min, Math.min(max, fallback))
  }
  return Math.max(min, Math.min(max, value))
}

function chatCompletionObject(
  id: string,
  model: string,
  created: number,
  output: ApiReasoningOutput,
  result: GenerationResult
): ChatCompletionPayload {
  const message: ChatCompletionMessage = { role: 'assistant', content: output.answer }
  if (output.reasoning.length > 0) {
    message.reasoning_content = output.reasoning
  }
  const choice: ChatCompletionChoice = {
    index: 0,
    message,
    finish_reason: finishReason(result)
  }
  const response: ChatCompletionPayload = {
    id, object: 'chat.completion', created, model, choices: [choice]
  }
  if (!result.generatedTokensEstimated && result.inputTokens !== undefined && Number.isSafeInteger(result.inputTokens) && result.inputTokens >= 0) {
    response.usage = {
      prompt_tokens: result.inputTokens,
      completion_tokens: result.generatedTokens,
      total_tokens: result.inputTokens + result.generatedTokens
    }
  }
  return response
}

function responseBase(
  id: string,
  model: string,
  created: number,
  status: string,
  output: ResponseOutputItem[]
): ResponsePayload {
  return {
    id,
    object: 'response',
    created_at: created,
    status,
    error: null,
    incomplete_details: null,
    instructions: null,
    model,
    output,
    parallel_tool_calls: false,
    previous_response_id: null,
    tools: [],
    tool_choice: 'none',
    truncation: 'disabled'
  }
}

function responsesObject(
  responseId: string,
  reasoningId: string,
  messageId: string,
  model: string,
  created: number,
  output: ApiReasoningOutput,
  result: GenerationResult
): ResponsePayload {
  const status = result.stopReason === 'eos' ? 'completed' :
    result.stopReason === 'max_tokens' ? 'incomplete' : 'failed'
  const itemStatus = status === 'completed' ? 'completed' : 'incomplete'
  const items: ResponseOutputItem[] = []
  if (output.reasoning.length > 0) {
    const reasoningContent: ResponseOutputContent = {
      type: 'reasoning_text',
      text: output.reasoning
    }
    items.push({
      id: reasoningId,
      type: 'reasoning',
      status: parseAssistantText(result.text).thinkingClosed ? 'completed' : 'incomplete',
      content: [reasoningContent],
      summary: []
    })
  }
  const content: ResponseOutputContent = { type: 'output_text', text: output.answer, annotations: [] }
  const item: ResponseOutputItem = {
    id: messageId,
    type: 'message',
    status: itemStatus,
    role: 'assistant',
    content: [content]
  }
  items.push(item)
  const response = responseBase(responseId, model, created, status, items)
  if (status === 'incomplete') response.incomplete_details = { reason: 'max_output_tokens' }
  if (status === 'failed') response.error = { code: 'server_error', message: generationFailureMessage(result) }
  response.usage = null
  if (!result.generatedTokensEstimated && result.inputTokens !== undefined && Number.isSafeInteger(result.inputTokens) && result.inputTokens >= 0 &&
    output.reasoning.length === 0) {
    response.usage = {
      input_tokens: result.inputTokens,
      input_tokens_details: { cached_tokens: 0 },
      output_tokens: result.generatedTokens,
      output_tokens_details: { reasoning_tokens: 0 },
      total_tokens: result.inputTokens + result.generatedTokens
    }
  }
  return response
}

function generationFailureMessage(result: GenerationResult): string {
  if (result.stopReason === 'user_stop') return '生成已取消，已停止返回回答。'
  if (result.stopReason === 'timeout') return '生成超时，回答未正常完成。'
  if (result.stopReason === 'internal_error') return '模型生成失败，回答未正常完成。'
  return '模型未报告正常结束，回答未正常完成。'
}

interface ApiOutputFormat {
  type?: string
}

interface ApiResponseTextOptions {
  format?: ApiOutputFormat
}

function validateApiGenerationOptions(value: Object, responses: boolean): void {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('请求体必须是 JSON 对象。')
  const body = value as Record<string, Object>
  if (!responses && body['stream_options'] !== undefined && body['stream_options'] !== null) {
    const options = body['stream_options']
    if (typeof options !== 'object' || Array.isArray(options)) throw new Error('stream_options 必须是 JSON 对象。')
    const includeUsage = (options as ChatStreamOptions).include_usage
    if (includeUsage !== undefined && typeof includeUsage !== 'boolean') throw new Error('include_usage 必须为布尔值。')
    if (body['stream'] !== true) throw new Error('stream_options 仅适用于流式请求。')
  }
  const unsupported = responses ? ['previous_response_id', 'conversation', 'reasoning'] : ['stop', 'seed']
  unsupported.forEach((name: string) => {
    if (body[name] !== undefined && body[name] !== null) throw new Error(`当前接口不支持 ${name}。`)
  })
  for (const name of ['tools', 'functions']) {
    const tools = body[name]
    if (tools !== undefined && tools !== null && (!Array.isArray(tools) || tools.length > 0)) {
      throw new Error(`当前接口不支持 ${name}，请移除工具调用配置。`)
    }
  }
  for (const name of ['tool_choice', 'function_call']) {
    if (body[name] !== undefined && body[name] !== null && body[name] !== 'none') {
      throw new Error(`当前接口只支持 ${name}=none。`)
    }
  }
  if (body['parallel_tool_calls'] === true) throw new Error('当前接口不支持并行工具调用。')
  if (body['n'] !== undefined && body['n'] !== 1) throw new Error('当前接口只支持 n=1。')
  if (body['store'] === true || body['background'] === true) throw new Error('当前接口不支持服务端保存或后台任务模式。')
  const formats: Object[] = []
  if (body['response_format'] !== undefined && body['response_format'] !== null) {
    formats.push(body['response_format'])
  }
  if (responses && body['text'] !== undefined && body['text'] !== null) {
    if (typeof body['text'] !== 'object' || Array.isArray(body['text'])) {
      throw new Error('text 必须是 JSON 对象。')
    }
    const text = body['text'] as ApiResponseTextOptions
    if (text.format !== undefined && text.format !== null) formats.push(text.format)
  }
  for (const value of formats) {
    const format = value as ApiOutputFormat
    if (typeof value !== 'object' || Array.isArray(value) || format.type !== 'text') {
      throw new Error('当前接口只支持普通文本输出，不支持 JSON 模式或结构化输出。')
    }
  }
}

function finishReason(result: GenerationResult): string {
  if (result.stopReason === 'max_tokens') return 'length'
  if (result.stopReason === 'eos') return 'stop'
  throw new Error(generationFailureMessage(result))
}

function httpHeaders(statusCode: number, contentType: string, includeLength: boolean, contentLength: number = 0): string {
  const reason = statusCode === 200 ? 'OK' :
    statusCode === 204 ? 'No Content' :
      statusCode === 400 ? 'Bad Request' :
        statusCode === 401 ? 'Unauthorized' :
          statusCode === 404 ? 'Not Found' :
            statusCode === 409 ? 'Conflict' :
              statusCode === 413 ? 'Payload Too Large' :
                statusCode === 503 ? 'Service Unavailable' : 'Internal Server Error'
  let headers = `HTTP/1.1 ${statusCode} ${reason}\r\n` +
    `Content-Type: ${contentType}\r\n` +
    'Cache-Control: no-cache\r\n' +
    'Access-Control-Allow-Origin: *\r\n' +
    'Access-Control-Allow-Headers: Authorization, Content-Type\r\n' +
    'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n' +
    'Connection: close\r\n'
  if (includeLength) {
    headers += `Content-Length: ${contentLength}\r\n`
  }
  return `${headers}\r\n`
}

function utf8Length(value: string): number {
  let length = 0
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index)
    if (code <= 0x7f) {
      length += 1
    } else if (code <= 0x7ff) {
      length += 2
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        length += 4
        index += 1
      } else {
        length += 3
      }
    } else {
      length += 3
    }
  }
  return length
}

async function resolveLanIpv4(): Promise<string> {
  try {
    const nets = await connection.getAllNets()
    let fallback = ''
    for (let netIndex = 0; netIndex < nets.length; netIndex++) {
      const properties = await connection.getConnectionProperties(nets[netIndex])
      for (let addressIndex = 0; addressIndex < properties.linkAddresses.length; addressIndex++) {
        const address = properties.linkAddresses[addressIndex].address.address
        if (!isUsableIpv4(address)) {
          continue
        }
        if (isPrivateIpv4(address) && properties.interfaceName.toLowerCase().indexOf('wlan') >= 0) {
          return address
        }
        if (fallback.length <= 0 && isPrivateIpv4(address)) {
          fallback = address
        }
      }
    }
    return fallback
  } catch (_err) {
    return ''
  }
}

function isUsableIpv4(address: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(address) && address !== '127.0.0.1' && address !== '0.0.0.0'
}

function isPrivateIpv4(address: string): boolean {
  if (address.startsWith('10.') || address.startsWith('192.168.')) {
    return true
  }
  const parts = address.split('.')
  if (parts.length !== 4 || parts[0] !== '172') {
    return false
  }
  const second = Number.parseInt(parts[1], 10)
  return second >= 16 && second <= 31
}

function errorMessage(err: Object): string {
  if (err === undefined || err === null) {
    return '未知错误'
  }
  if (typeof err === 'string') {
    return err
  }
  const record = err as Record<string, Object>
  const message = record.message !== undefined ? `${record.message}` : ''
  if (record.code !== undefined) {
    return message.length > 0 ? `错误码 ${record.code}：${message}` : `错误码 ${record.code}`
  }
  if (message.length > 0) {
    return message
  }
  const fallback = `${err}`
  return fallback === '[object Object]' ? '未知错误' : fallback
}
