export interface MarkdownSpan {
  text: string
  bold: boolean
  italic?: boolean
  code?: boolean
  link?: string
  strikethrough?: boolean
}

export interface MarkdownBlock {
  type: string
  text: string
  items: string[]
  language: string
  startNumber?: number
  headers?: string[]
  rows?: string[][]
}

const INLINE_MARKDOWN_CACHE_LIMIT: number = 360
const BLOCK_MARKDOWN_CACHE_LIMIT: number = 160
const inlineMarkdownCache: Map<string, MarkdownSpan[]> = new Map()
const blockMarkdownCache: Map<string, MarkdownBlock[]> = new Map()

function rememberInlineMarkdown(text: string, spans: MarkdownSpan[]): MarkdownSpan[] {
  if (inlineMarkdownCache.size >= INLINE_MARKDOWN_CACHE_LIMIT) {
    inlineMarkdownCache.clear()
  }
  inlineMarkdownCache.set(text, spans)
  return spans
}

function rememberBlockMarkdown(content: string, blocks: MarkdownBlock[]): MarkdownBlock[] {
  if (blockMarkdownCache.size >= BLOCK_MARKDOWN_CACHE_LIMIT) {
    blockMarkdownCache.clear()
  }
  blockMarkdownCache.set(content, blocks)
  return blocks
}

function emptyBlock(type: string): MarkdownBlock {
  const block: MarkdownBlock = {
    type: type,
    text: '',
    items: [],
    language: ''
  }
  return block
}

function flushParagraph(blocks: MarkdownBlock[], paragraphLines: string[]): void {
  if (paragraphLines.length <= 0) {
    return
  }
  const block = emptyBlock('paragraph')
  block.text = paragraphLines.join('\n').trim()
  if (block.text.length > 0) {
    blocks.push(block)
  }
  paragraphLines.length = 0
}

function flushList(blocks: MarkdownBlock[], listItems: string[], ordered: boolean, startNumber: number = 1): void {
  if (listItems.length <= 0) {
    return
  }
  const block = emptyBlock(ordered ? 'ordered-list' : 'unordered-list')
  if (ordered) {
    block.startNumber = startNumber
  }
  listItems.forEach((item: string) => {
    block.items.push(item)
  })
  blocks.push(block)
  listItems.length = 0
}

function isTableLine(line: string): boolean {
  const trimmed = line.trim()
  return trimmed.indexOf('|') >= 0 && trimmed.replace(/[|]/g, '').trim().length > 0
}

function isTableAlignLine(line: string): boolean {
  const trimmed = line.trim()
  return trimmed.indexOf('|') >= 0 && trimmed.replace(/[\|\:\-\s]/g, '').length === 0
}

function parseTableHeader(line: string): string[] {
  return parseTableCells(line)
}

function parseTableRow(line: string): string[] {
  return parseTableCells(line)
}

function parseTableCells(line: string): string[] {
  const cells = line.trim().split('|').map((c: string) => c.trim())
  if (cells.length > 0 && cells[0].length <= 0) {
    cells.shift()
  }
  if (cells.length > 0 && cells[cells.length - 1].length <= 0) {
    cells.pop()
  }
  return cells
}

function normalizeTableCells(cells: string[], columnCount: number): string[] {
  const normalized: string[] = []
  for (let index = 0; index < columnCount; index += 1) {
    normalized.push(index < cells.length ? cells[index] : '')
  }
  return normalized
}

interface CandidateMarker {
  m: string
  weight: number
}

function isPartOfTripleBacktick(text: string, index: number): boolean {
  const isTripleStart = text.substring(index, index + 3) === '```'
  const isTripleMiddle = index > 0 && text.substring(index - 1, index + 2) === '```'
  const isTripleEnd = index > 1 && text.substring(index - 2, index + 1) === '```'
  return isTripleStart || isTripleMiddle || isTripleEnd
}

function countSingleBackticks(text: string): number {
  let count = 0
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === '`' && !isPartOfTripleBacktick(text, i)) {
      count += 1
    }
  }
  return count
}

function isInsideIncompleteCodeFence(text: string): boolean {
  const matches = text.match(/```/g)
  return matches !== null && matches.length % 2 === 1
}

function completeIncompleteInlineCode(text: string): string {
  if (isInsideIncompleteCodeFence(text) || countSingleBackticks(text) % 2 === 0) {
    return text
  }

  const lastBacktick = text.lastIndexOf('`')
  if (lastBacktick < 0) {
    return text
  }

  const trailing = text.substring(lastBacktick + 1)
  if (trailing.trim().length <= 0 || /^[\s*_~`]*$/.test(trailing)) {
    return text
  }

  return `${text}\``
}

function sameSpanStyle(left: MarkdownSpan, right: MarkdownSpan): boolean {
  return left.bold === right.bold &&
    left.italic === right.italic &&
    left.code === right.code &&
    left.strikethrough === right.strikethrough &&
    left.link === right.link
}

function cloneSpan(span: MarkdownSpan): MarkdownSpan {
  const cloned: MarkdownSpan = {
    text: span.text,
    bold: span.bold
  }
  cloned.italic = span.italic
  cloned.code = span.code
  cloned.link = span.link
  cloned.strikethrough = span.strikethrough
  return cloned
}

function mergeAdjacentSpans(spans: MarkdownSpan[]): MarkdownSpan[] {
  if (spans.length <= 1) {
    return spans
  }

  const result: MarkdownSpan[] = []
  let current: MarkdownSpan = cloneSpan(spans[0])
  for (let i = 1; i < spans.length; i += 1) {
    const next = spans[i]
    if (sameSpanStyle(current, next)) {
      current.text += next.text
      continue
    }
    result.push(current)
    current = cloneSpan(next)
  }
  result.push(current)
  return result
}

export function parseInlineMarkdown(text: string): MarkdownSpan[] {
  const cached = inlineMarkdownCache.get(text)
  if (cached !== undefined) {
    return cached
  }
  return rememberInlineMarkdown(text, parseInlineMarkdownUncached(text))
}

function parseInlineMarkdownUncached(text: string): MarkdownSpan[] {
  text = completeIncompleteInlineCode(text)
  const spans: MarkdownSpan[] = []
  let i: number = 0
  while (i < text.length) {
    let bestKind: string = ''
    let bestStart: number = -1
    let bestEnd: number = -1

    const candidates: CandidateMarker[] = [
      { m: '***', weight: 1 } as CandidateMarker,
      { m: '**', weight: 2 } as CandidateMarker,
      { m: '`', weight: 3 } as CandidateMarker,
      { m: '~~', weight: 4 } as CandidateMarker,
      { m: '*', weight: 5 } as CandidateMarker,
    ]

    for (const c of candidates) {
      const s: number = text.indexOf(c.m, i)
      let foundWeight: number = -1
      for (let ci = 0; ci < candidates.length; ci++) {
        if (candidates[ci].m === bestKind) {
          foundWeight = candidates[ci].weight
          break
        }
      }
      if (s >= 0 && (bestStart < 0 || s < bestStart || (s === bestStart && c.weight < foundWeight))) {
        const e: number = text.indexOf(c.m, s + c.m.length)
        if (e >= 0) {
          bestKind = c.m
          bestStart = s
          bestEnd = e
        }
      }
    }

    // Check for link: [text](url)
    const linkStart = text.indexOf('[', i)
    if (linkStart >= 0 && (bestStart < 0 || linkStart < bestStart)) {
      const linkTextEnd = text.indexOf('](', linkStart + 1)
      const linkUrlEnd = text.indexOf(')', linkTextEnd > 0 ? linkTextEnd + 2 : 0)
      if (linkTextEnd > 0 && linkUrlEnd > 0 &&
        text.substring(linkStart + 1, linkTextEnd).indexOf('[') < 0) {
        bestKind = 'link'
        bestStart = linkStart
        bestEnd = linkUrlEnd
      }
    }

    const urlRegex = /https?:\/\/[^\s<>"')一-鿿。，！？、；：」』》】]+/
    const urlMatch = urlRegex.exec(text.substring(i))
    if (urlMatch !== null && (bestStart < 0 || (i + urlMatch.index) < bestStart)) {
      bestKind = 'url'
      bestStart = i + urlMatch.index
      bestEnd = i + urlMatch.index + urlMatch[0].length
    }

    if (bestStart < 0) {
      const s: MarkdownSpan = { text: text.substring(i), bold: false }
      spans.push(s)
      break
    }

    if (bestStart > i) {
      const s: MarkdownSpan = { text: text.substring(i, bestStart), bold: false }
      spans.push(s)
    }

    const inner: string = text.substring(bestStart + bestKind.length, bestEnd)

    let nextIndex: number = bestEnd + bestKind.length

    if (bestKind === '***' && inner.length > 0) {
      const s: MarkdownSpan = { text: inner, bold: true, italic: true }
      spans.push(s)
    } else if (bestKind === '**' && inner.length > 0) {
      const s: MarkdownSpan = { text: inner, bold: true }
      spans.push(s)
    } else if (bestKind === '*' && inner.length > 0) {
      const s: MarkdownSpan = { text: inner, bold: false, italic: true }
      spans.push(s)
    } else if (bestKind === '`' && inner.length > 0) {
      const s: MarkdownSpan = { text: inner, bold: false, code: true }
      spans.push(s)
    } else if (bestKind === '~~' && inner.length > 0) {
      const s: MarkdownSpan = { text: inner, bold: false, strikethrough: true }
      spans.push(s)
    } else if (bestKind === 'link') {
      const linkText: string = text.substring(bestStart + 1, text.indexOf('](', bestStart))
      const linkUrl: string = text.substring(text.indexOf('](', bestStart) + 2, bestEnd)
      if (linkText.length > 0) {
        const s: MarkdownSpan = { text: linkText, bold: false, link: linkUrl }
        spans.push(s)
      }
      nextIndex = bestEnd + 1
    } else if (bestKind === 'url') {
      const url: string = text.substring(bestStart, bestEnd)
      const s: MarkdownSpan = { text: url, bold: false, link: url }
      spans.push(s)
      nextIndex = bestEnd
    } else {
      const s: MarkdownSpan = { text: text.substring(bestStart, bestEnd + bestKind.length), bold: false }
      spans.push(s)
    }

    i = nextIndex
  }
  return mergeAdjacentSpans(spans.filter((span: MarkdownSpan) => span.text.length > 0))
}

export function parseLightMarkdown(content: string): MarkdownBlock[] {
  const cached = blockMarkdownCache.get(content)
  if (cached !== undefined) {
    return cached
  }
  return rememberBlockMarkdown(content, parseLightMarkdownUncached(content))
}

function parseLightMarkdownUncached(content: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = []
  const paragraphLines: string[] = []
  const codeLines: string[] = []
  const quoteLines: string[] = []
  const tableLines: string[] = []
  let inCode = false
  let codeLanguage = ''
  let inTable = false
  let parentListItems: string[] = []
  let parentListOrdered: boolean | undefined = undefined
  let parentListStart: number = 1
  let childListItems: string[] = []
  let childListOrdered: boolean | undefined = undefined
  let childListStart: number = 1

  const resetListState = () => {
    childListOrdered = undefined
    parentListOrdered = undefined
    childListStart = 1
    parentListStart = 1
  }

  const flushLists = () => {
    flushList(blocks, parentListItems, parentListOrdered ?? false, parentListStart)
    flushList(blocks, childListItems, childListOrdered ?? false, childListStart)
    resetListState()
  }

  const flushQuote = () => {
    if (quoteLines.length > 0) {
      const block = emptyBlock('blockquote')
      block.text = quoteLines.join('\n')
      blocks.push(block)
      quoteLines.length = 0
    }
  }

  const flushTable = () => {
    if (tableLines.length >= 2) {
      const block = emptyBlock('table')
      let startIdx = 0
      // Strip leading separator lines before header
      while (startIdx < tableLines.length && isTableAlignLine(tableLines[startIdx])) {
        startIdx++
      }
      if (startIdx + 1 >= tableLines.length) {
        tableLines.length = 0
        inTable = false
        return
      }
      let headerIdx = startIdx
      if (startIdx + 1 < tableLines.length && isTableAlignLine(tableLines[startIdx + 1])) {
        block.headers = parseTableHeader(tableLines[startIdx])
        headerIdx = startIdx + 2
      } else {
        block.headers = undefined
        headerIdx = startIdx
        if (startIdx < tableLines.length && isTableAlignLine(tableLines[startIdx])) {
          headerIdx = startIdx + 1
        }
      }
      let columnCount = block.headers !== undefined ? block.headers.length : 0
      if (columnCount <= 0) {
        for (let ti = headerIdx; ti < tableLines.length; ti++) {
          if (!isTableAlignLine(tableLines[ti])) {
            columnCount = Math.max(columnCount, parseTableRow(tableLines[ti]).length)
          }
        }
      }
      if (columnCount <= 0) {
        tableLines.length = 0
        inTable = false
        return
      }
      if (block.headers !== undefined) {
        block.headers = normalizeTableCells(block.headers, columnCount)
      }
      block.rows = []
      for (let ti = headerIdx; ti < tableLines.length; ti++) {
        const cells = parseTableRow(tableLines[ti])
        if (cells.length > 0 && !isTableAlignLine(tableLines[ti])) {
          (block.rows as string[][]).push(normalizeTableCells(cells, columnCount))
        }
      }
      blocks.push(block)
    }
    tableLines.length = 0
    inTable = false
  }

  const lines = content.replace(/\r\n/g, '\n').split('\n')
  lines.forEach((line: string) => {
    const trimmed = line.trim()

    if (trimmed.startsWith('```')) {
      flushQuote()
      flushTable()
      if (inCode) {
        const block = emptyBlock('code')
        block.text = codeLines.join('\n')
        block.language = codeLanguage
        blocks.push(block)
        codeLines.length = 0
        codeLanguage = ''
        inCode = false
        return
      }
      flushParagraph(blocks, paragraphLines)
      flushLists()
      inCode = true
      codeLanguage = trimmed.substring(3).trim()
      return
    }

    if (inCode) {
      codeLines.push(line)
      return
    }

    if (trimmed.length <= 0) {
      flushParagraph(blocks, paragraphLines)
      flushLists()
      flushQuote()
      flushTable()
      return
    }

    if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)) {
      flushParagraph(blocks, paragraphLines)
      flushLists()
      flushQuote()
      flushTable()
      const block = emptyBlock('horizontal-rule')
      blocks.push(block)
      return
    }

    const headingMatch = trimmed.match(/^(#{1,3})\s+(.+)$/)
    if (headingMatch !== null) {
      flushParagraph(blocks, paragraphLines)
      flushLists()
      flushQuote()
      flushTable()
      const block = emptyBlock('heading')
      block.text = headingMatch[2].trim()
      blocks.push(block)
      return
    }

    if (trimmed.startsWith('>')) {
      flushParagraph(blocks, paragraphLines)
      flushLists()
      flushTable()
      const q = trimmed.substring(1).trim()
      quoteLines.push(q.length > 0 ? q : '')
      return
    }

    if (isTableLine(trimmed)) {
      flushParagraph(blocks, paragraphLines)
      flushLists()
      flushQuote()
      if (!inTable && isTableAlignLine(trimmed)) {
        return
      }
      inTable = true
      tableLines.push(trimmed)
      return
    }

    flushQuote()
    flushTable()

    const unorderedMatch = trimmed.match(/^[-*•]\s+(.+)$/)
    const orderedMatch = trimmed.match(/^(\d+)[.)]\s+(.+)$/)
    if (unorderedMatch !== null || orderedMatch !== null) {
      flushParagraph(blocks, paragraphLines)
      const ordered = orderedMatch !== null
      const orderedNumber = orderedMatch !== null ? Number.parseInt(orderedMatch[1], 10) : 1
      const orderedText = orderedMatch !== null ? orderedMatch[2].trim() : ''
      const unorderedText = unorderedMatch !== null ? unorderedMatch[1].trim() : ''
      const listItemText = orderedText.length > 0 ? orderedText : unorderedText

      // Determine whether this is parent or child list
      if (parentListOrdered === undefined) {
        parentListOrdered = ordered
        parentListStart = ordered ? orderedNumber : 1
        parentListItems.push(listItemText)
        return
      }

      if (ordered === parentListOrdered) {
        if (childListItems.length > 0) {
          flushList(blocks, parentListItems, parentListOrdered ?? false, parentListStart)
          flushList(blocks, childListItems, childListOrdered ?? false, childListStart)
          childListOrdered = undefined
          childListStart = 1
          parentListStart = ordered ? orderedNumber : 1
        }
        parentListItems.push(listItemText)
        return
      }

      // Different type — accumulate as child
      if (childListOrdered === undefined) {
        childListOrdered = ordered
        childListStart = ordered ? orderedNumber : 1
      }
      if (ordered !== childListOrdered) {
        // Child type changed again — flush child, restart
        flushList(blocks, childListItems, childListOrdered ?? false, childListStart)
        childListItems.length = 0
        childListOrdered = ordered
        childListStart = ordered ? orderedNumber : 1
      }
      childListItems.push(listItemText)
      return
    }

    flushLists()
    paragraphLines.push(line)
  })

  if (inCode) {
    const block = emptyBlock('code')
    block.text = codeLines.join('\n')
    block.language = codeLanguage
    blocks.push(block)
  }
  flushParagraph(blocks, paragraphLines)
  flushLists()
  flushQuote()
  flushTable()
  return blocks
}
