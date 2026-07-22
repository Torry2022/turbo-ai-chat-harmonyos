export interface ModelDragFrame {
  top: number
  height: number
}

export interface ModelDragPreview {
  offsetY: number
  targetIndex: number
}

export function resolveModelDragPreview(
  frames: ModelDragFrame[],
  startIndex: number,
  offsetY: number
): ModelDragPreview {
  const draggedFrame = frames[startIndex]
  const draggedCenter = draggedFrame.top + draggedFrame.height / 2 + offsetY
  let targetIndex = startIndex

  if (offsetY > 0) {
    for (let index = startIndex + 1; index < frames.length; index++) {
      const frame = frames[index]
      if (draggedCenter < frame.top + frame.height / 2) {
        break
      }
      targetIndex = index
    }
  } else if (offsetY < 0) {
    for (let index = startIndex - 1; index >= 0; index--) {
      const frame = frames[index]
      if (draggedCenter > frame.top + frame.height / 2) {
        break
      }
      targetIndex = index
    }
  }

  return { offsetY, targetIndex }
}

export function reorderVisibleModelIds(
  allIds: string[],
  visibleIds: string[],
  modelId: string,
  targetIndex: number
): string[] {
  const currentIndex = visibleIds.indexOf(modelId)
  const nextIndex = Math.max(0, Math.min(visibleIds.length - 1, Math.round(targetIndex)))
  if (currentIndex < 0 || currentIndex === nextIndex) {
    return allIds.slice()
  }

  const reorderedVisibleIds = visibleIds.slice()
  const movedId = reorderedVisibleIds.splice(currentIndex, 1)[0]
  reorderedVisibleIds.splice(nextIndex, 0, movedId)

  let visibleIndex = 0
  return allIds.map((id: string) => {
    if (visibleIds.indexOf(id) < 0) {
      return id
    }
    const reorderedId = reorderedVisibleIds[visibleIndex]
    visibleIndex++
    return reorderedId
  })
}
