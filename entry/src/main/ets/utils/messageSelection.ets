export interface MessageSelectionPart {
  block: number
  row: number
  column: number
  kind: string
  text: string
}

// Only reformat a selection whose nodes exactly match the native selection.
export function joinMessageSelection(parts: MessageSelectionPart[], nativeText: string): string {
  const ordered = parts.filter((part: MessageSelectionPart) => part.text.length > 0)
    .sort((a: MessageSelectionPart, b: MessageSelectionPart) =>
      a.block - b.block || a.row - b.row || a.column - b.column)
  if (ordered.map((part: MessageSelectionPart) => part.text).join('\n') !== nativeText) {
    return nativeText
  }
  let text = ''
  for (let index = 0; index < ordered.length; index++) {
    const part = ordered[index]
    if (index > 0) {
      const previous = ordered[index - 1]
      if (part.block !== previous.block) {
        text += '\n\n' + (part.kind === 'table' ? '\t'.repeat(part.column) : '')
      } else if (part.row !== previous.row) {
        text += '\n' + (part.kind === 'table' ? '\t'.repeat(part.column) : '')
      } else {
        text += part.kind === 'table' ? '\t'.repeat(part.column - previous.column) : ' '
      }
    }
    text += part.text
  }
  return text
}
