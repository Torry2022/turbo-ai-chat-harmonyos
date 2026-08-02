import connection from '@ohos.net.connection'
import socket from '@ohos.net.socket'
import util from '@ohos.util'
import { ChatTurn, GenerationResult, GenerationSettings } from '../models/ChatTypes'
import { MAX_GENERATION_TOKENS } from '../models/ModelProfile'
import { parseAssistantText, stripModelSpecialTokens } from '../utils/thinking'

const MAX_REQUEST_BYTES: number = 1024 * 1024
const SERVER_OWNER: string = 'turbo-ai-chat'

export interface ApiServerConfig {
  port: number
  requireApiKey: boolean
  apiKey: string
}

export interface ApiServerModel {
  id: string
  name: string
}

export interface ApiGenerationRequest {
  turns: ChatTurn[]
  maxNewTokens: number
  settings: GenerationSettings
}

export interface ApiServerCallbacks {
  isModelLoaded: () => boolean
  isGenerationReady: () => boolean
  currentModel: () => ApiServerModel
  currentSettings: () => GenerationSettings
  currentMaxNewTokens: () => number
  generate: (request: ApiGenerationRequest, onChunk: (chunk: string) => void) => Promise<GenerationResult>
  stopGeneration: () => void
  onStatus: (status: string) => void
  onLog: (level: string, message: string) => void
}

interface ApiContentPart {
  type?: string
  text?: string
}

interface ApiMessageInput {
  role?: string
  content?: string | ApiContentPart[]
}

interface ChatCompletionRequestBody {
  model?: string
  messages?: ApiMessageInput[]
  stream?: boolean
  max_tokens?: number
  max_completion_tokens?: number
  temperature?: number
  top_p?: number
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
  usage: TokenUsage
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

interface ResponsePayload {
  id: string
  object: string
  created_at: number
  status: string
  error: Object | null
  incomplete_details: Object | null
  instructions: string | null
  model: string
  output: ResponseOutputItem[]
  parallel_tool_calls: boolean
  previous_response_id: string | null
  tools: Object[]
  tool_choice: string
  truncation: string
  usage?: ResponseUsage
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
  sendChain: Promise<void> = Promise.resolve()

  constructor(connectionValue: socket.TCPSocketConnection) {
    this.connection = connectionValue
  }

  append(message: ArrayBuffer): void {
    this.buffer += this.decoder.decodeToString(new Uint8Array(message), { stream: true })
  }

  send(data: string): void {
    if (this.closed) {
      return
    }
    this.sendChain = this.sendChain.then(() => {
      if (this.closed) {
        return Promise.resolve()
      }
      return this.connection.send({ data, encoding: 'utf-8' })
    }).catch((_err: Error) => {
      this.closed = true
    })
  }

  closeAfterSend(): void {
    this.sendChain = this.sendChain.then(() => {
      if (this.closed) {
        return Promise.resolve()
      }
      this.closed = true
      return this.connection.close()
    }).catch((_err: Error) => {
      this.closed = true
    })
  }

  close(): void {
    if (this.closed) {
      return
    }
    this.closed = true
    this.connection.close().catch((_err: Error) => {
    })
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
  private activeClientId: number = -1
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
        this.acceptClient(client)
      })
      server.on('error', (err: Error) => {
        this.callbacks.onStatus(`API 服务异常：${err.message}`)
        this.callbacks.onLog('ERROR', `Server error: ${errorMessage(err)}`)
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
    this.callbacks.onStatus(`API 服务已启动：${this.baseUrl()}`)
    this.callbacks.onLog('INFO', `Server started on 0.0.0.0:${config.port}`)
    return this.baseUrl()
  }

  async stop(): Promise<void> {
    if (!this.running && this.server === undefined) {
      return
    }
    if (this.activeClientId >= 0) {
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
    if (server !== undefined) {
      server.off('connect')
      server.off('error')
      await server.close().catch((_err: Error) => {
      })
    }
    this.callbacks.onStatus('API 服务已停止')
    this.callbacks.onLog('INFO', 'Server stopped')
  }

  private acceptClient(client: socket.TCPSocketConnection): void {
    const state = new HttpConnectionState(client)
    this.connections.set(client.clientId, state)
    try {
      client.on('message', (info: socket.SocketMessageInfo) => {
        const message = info.message !== undefined ? info.message : info as Object as ArrayBuffer
        this.handleClientData(state, message)
      })
      client.on('close', () => {
        state.closed = true
        this.connections.delete(client.clientId)
        if (this.activeClientId === client.clientId) {
          this.callbacks.stopGeneration()
        }
      })
      client.on('error', (_err: Error) => {
        state.close()
        this.connections.delete(client.clientId)
        if (this.activeClientId === client.clientId) {
          this.callbacks.stopGeneration()
        }
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
    state.append(message)
    if (utf8Length(state.buffer) > MAX_REQUEST_BYTES) {
      state.handled = true
      this.callbacks.onLog('ERROR', '413 HTTP request · 请求内容超过 1 MB')
      this.sendError(state, 413, 'request_too_large', '请求内容超过 1 MB。')
      return
    }
    let request: ParsedHttpRequest | undefined
    try {
      request = parseHttpRequest(state.buffer)
    } catch (err) {
      state.handled = true
      this.callbacks.onLog('ERROR', `400 HTTP request · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
      return
    }
    if (request === undefined) {
      return
    }
    state.handled = true
    this.route(state, request)
  }

  private route(state: HttpConnectionState, request: ParsedHttpRequest): void {
    this.callbacks.onLog('REQ', `${request.method} ${request.path}`)
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
    if (request.method === 'POST' && request.path === '/v1/chat/completions') {
      this.handleChatCompletions(state, request.body)
      return
    }
    if (request.method === 'POST' && request.path === '/v1/responses') {
      this.handleResponses(state, request.body)
      return
    }
    this.sendError(state, 404, 'not_found', '不支持该 API 路径。')
    this.callbacks.onLog('ERROR', `404 ${request.method} ${request.path}`)
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
    if (this.callbacks.isModelLoaded()) {
      const modelObject: ApiModelObject = {
        id: model.id,
        object: 'model',
        created: Math.floor(Date.now() / 1000),
        owned_by: SERVER_OWNER
      }
      data.push(modelObject)
    }
    const payload: ApiModelList = { object: 'list', data }
    this.sendJson(state, 200, payload)
    this.callbacks.onLog('RESP', '200 GET /v1/models')
  }

  private handleChatCompletions(state: HttpConnectionState, bodyText: string): void {
    try {
      const body = JSON.parse(bodyText.replace(/^\uFEFF/, '')) as ChatCompletionRequestBody
      const turns = parseMessages(body.messages)
      const request = this.buildGenerationRequest(
        turns,
        body.max_completion_tokens ?? body.max_tokens,
        body.temperature,
        body.top_p
      )
      this.runGeneration(state, body.model ?? '', body.stream === true, false, request)
    } catch (err) {
      this.callbacks.onLog('ERROR', `400 POST /v1/chat/completions · ${errorMessage(err)}`)
      this.sendError(state, 400, 'invalid_request_error', errorMessage(err))
    }
  }

  private handleResponses(state: HttpConnectionState, bodyText: string): void {
    try {
      const body = JSON.parse(bodyText.replace(/^\uFEFF/, '')) as ResponsesRequestBody
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

  private buildGenerationRequest(
    turns: ChatTurn[],
    requestedMaxTokens?: number,
    requestedTemperature?: number,
    requestedTopP?: number
  ): ApiGenerationRequest {
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
        penaltyWindow: defaults.penaltyWindow
      }
    }
  }

  private runGeneration(
    state: HttpConnectionState,
    requestedModel: string,
    streaming: boolean,
    responsesApi: boolean,
    request: ApiGenerationRequest
  ): void {
    const apiPath = responsesApi ? '/v1/responses' : '/v1/chat/completions'
    if (!this.callbacks.isGenerationReady()) {
      this.callbacks.onLog('ERROR', `503 POST ${apiPath} · 模型未就绪或当前任务未完成`)
      this.sendError(state, 503, 'model_not_ready', '请先在 Turbo AI Chat 中加载模型，并等待当前任务完成。')
      return
    }
    if (this.activeClientId >= 0) {
      this.callbacks.onLog('ERROR', `409 POST ${apiPath} · 当前已有生成任务`)
      this.sendError(state, 409, 'server_busy', '当前已有 API 生成任务，请稍后重试。')
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
        this.sendChatChunk(state, responseId, model.id, created, { reasoning: '', answer: '' }, 'assistant')
      }
    }

    this.callbacks.onStatus(`API 请求：${apiPath}`)
    this.callbacks.onLog(
      'INFO',
      `model=${model.id}, stream=${streaming}, maxTokens=${request.maxNewTokens}`
    )
    this.callbacks.generate(request, (chunk: string) => {
      const delta = filter.append(chunk)
      if (!streaming || (delta.reasoning.length <= 0 && delta.answer.length <= 0) || state.closed) {
        return
      }
      if (responsesApi) {
        this.sendResponsesDelta(state, responsesContext, delta)
      } else {
        if (delta.reasoning.length > 0) {
          this.sendChatChunk(
            state, responseId, model.id, created, { reasoning: delta.reasoning, answer: '' }
          )
        }
        if (delta.answer.length > 0) {
          this.sendChatChunk(state, responseId, model.id, created, { reasoning: '', answer: delta.answer })
        }
      }
    }).then((result: GenerationResult) => {
      const finalDelta = filter.complete(result.text)
      if (streaming && (finalDelta.reasoning.length > 0 || finalDelta.answer.length > 0) && !state.closed) {
        if (responsesApi) {
          this.sendResponsesDelta(state, responsesContext, finalDelta)
        } else {
          if (finalDelta.reasoning.length > 0) {
            this.sendChatChunk(
              state, responseId, model.id, created, { reasoning: finalDelta.reasoning, answer: '' }
            )
          }
          if (finalDelta.answer.length > 0) {
            this.sendChatChunk(
              state, responseId, model.id, created, { reasoning: '', answer: finalDelta.answer }
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
              finishReason(result)
            )
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
      this.activeClientId = -1
      const streamLabel = streaming ? ' (stream)' : ''
      this.callbacks.onLog(
        'RESP',
        `200 POST ${apiPath}${streamLabel} · ${Date.now() - startedAt} ms · ` +
          `${result.generatedTokens} tokens · ${output.answer.length} chars`
      )
      this.callbacks.onStatus(`API 生成完成：${result.generatedTokens} tokens`)
    }).catch((err: Error) => {
      if (!state.closed) {
        if (streaming) {
          const payload: ApiStreamError = {
            type: 'error', code: 'generation_failed', message: errorMessage(err), param: null
          }
          state.send(`event: error\ndata: ${JSON.stringify(payload)}\n\n`)
          state.closeAfterSend()
        } else {
          this.sendError(state, 500, 'generation_failed', errorMessage(err))
        }
      }
      this.activeClientId = -1
      this.callbacks.onLog('ERROR', `500 POST ${apiPath} · ${errorMessage(err)}`)
      this.callbacks.onStatus(`API 生成失败：${errorMessage(err)}`)
    })
  }

  private sendChatChunk(
    state: HttpConnectionState,
    id: string,
    model: string,
    created: number,
    output: ApiReasoningOutput,
    role?: string,
    finishReasonValue?: string
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

  private finishResponsesReasoning(state: HttpConnectionState, context: ResponsesStreamContext): void {
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
      status: 'completed',
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
    context.reasoningText = output.reasoning
    context.answerText = output.answer
    if (output.reasoning.length > 0) {
      this.startResponsesReasoning(state, context)
    }
    this.finishResponsesReasoning(state, context)
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
      id: context.messageId, type: 'message', status: 'completed', role: 'assistant', content: [content]
    }
    const itemDoneEvent: ResponseOutputItemEvent = {
      type: 'response.output_item.done', output_index: outputIndex, item,
      sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.output_item.done', itemDoneEvent)
    const response = responsesObject(
      context.responseId, context.reasoningId, context.messageId, context.model, context.created, output, result
    )
    const completedEvent: ResponseCompletedEvent = {
      type: 'response.completed', response, sequence_number: context.sequenceNumber++
    }
    this.sendResponseEvent(state, 'response.completed', completedEvent)
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

export function splitApiOutput(rawText: string, finalValue: boolean): ApiReasoningOutput {
  const normalized = stripModelSpecialTokens(rawText)
  const trimmedStart = normalized.trimStart()
  if (!finalValue && trimmedStart.length > 0 && '<think>'.startsWith(trimmedStart)) {
    return { reasoning: '', answer: '' }
  }
  const openTag = '<think>'
  const closeTag = '</think>'
  const openIndex = normalized.indexOf(openTag)
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
    answer: finalValue ? normalized.trim() : normalized.trimStart().trimEnd()
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
  if (content.length <= 0) {
    throw new Error('消息内容不能为空，第一版暂不支持图片或工具消息。')
  }
  return { role, content }
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
    throw new Error('第一版 API 服务仅支持文本输入。')
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
  const usage: TokenUsage = {
    prompt_tokens: 0,
    completion_tokens: result.generatedTokens,
    total_tokens: result.generatedTokens
  }
  return {
    id,
    object: 'chat.completion',
    created,
    model,
    choices: [choice],
    usage
  }
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
  const items: ResponseOutputItem[] = []
  if (output.reasoning.length > 0) {
    const reasoningContent: ResponseOutputContent = {
      type: 'reasoning_text',
      text: output.reasoning
    }
    items.push({
      id: reasoningId,
      type: 'reasoning',
      status: 'completed',
      content: [reasoningContent],
      summary: []
    })
  }
  const content: ResponseOutputContent = { type: 'output_text', text: output.answer, annotations: [] }
  const item: ResponseOutputItem = {
    id: messageId,
    type: 'message',
    status: 'completed',
    role: 'assistant',
    content: [content]
  }
  items.push(item)
  const response = responseBase(responseId, model, created, 'completed', items)
  const inputDetails: ResponseInputTokenDetails = { cached_tokens: 0 }
  const outputDetails: ResponseOutputTokenDetails = { reasoning_tokens: 0 }
  response.usage = {
    input_tokens: 0,
    input_tokens_details: inputDetails,
    output_tokens: result.generatedTokens,
    output_tokens_details: outputDetails,
    total_tokens: result.generatedTokens
  }
  return response
}

function finishReason(result: GenerationResult): string {
  return result.stopReason === 'max_tokens' ? 'length' : 'stop'
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
