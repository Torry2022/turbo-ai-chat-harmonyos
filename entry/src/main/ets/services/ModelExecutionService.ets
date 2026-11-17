export type ModelTaskOwner = 'chat' | 'title' | 'decision' | 'rerank'

interface ModelTaskTicket { owner: ModelTaskOwner }

// One execution permit is shared by all runtime entry points. Model residency is independent.
export class ModelExecutionService {
  private static active?: ModelTaskTicket

  static current(): ModelTaskOwner | undefined { return ModelExecutionService.active?.owner }

  static acquire(owner: ModelTaskOwner): () => void {
    if (ModelExecutionService.active !== undefined) throw new Error('当前模型任务尚未结束')
    const ticket: ModelTaskTicket = { owner }
    ModelExecutionService.active = ticket
    return (): void => { if (ModelExecutionService.active === ticket) ModelExecutionService.active = undefined }
  }
}
