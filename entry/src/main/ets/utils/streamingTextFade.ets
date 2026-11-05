import { graphemeBoundaries } from './graphemeBoundaries'
import { MarkdownSpan } from './markdown'

export const STREAM_TEXT_FADE_MS: number = 180

interface TextBirth {
  start: number
  end: number
  time: number
}

export interface FadingMarkdownSpan {
  span: MarkdownSpan
  start: number
  opacity: number
}

function sliceSpan(span: MarkdownSpan, text: string): MarkdownSpan {
  return { text, bold: span.bold, italic: span.italic, code: span.code,
    link: span.link, strikethrough: span.strikethrough }
}

// Keep timestamps only for the short, still-fading tail. Completed text stays a single span.
export class StreamingTextFade {
  private text: string = ''
  private births: TextBirth[] = []

  update(text: string, streaming: boolean, now: number): void {
    this.births = this.births.filter((birth: TextBirth) => now - birth.time < STREAM_TEXT_FADE_MS)
    if (!streaming || !text.startsWith(this.text)) {
      this.births = []
    } else if (text.length > this.text.length) {
      const start = this.text.length
      let previous = start
      const ends = graphemeBoundaries(text.substring(start))
      ends.forEach((end: number, index: number) => {
        this.births.push({ start: previous, end: start + end, time: now + Math.min(index * 8, 48) })
        previous = start + end
      })
    }
    this.text = text
  }

  active(now: number): boolean {
    return this.births.some((birth: TextBirth) => now - birth.time < STREAM_TEXT_FADE_MS)
  }

  spans(spans: MarkdownSpan[], now: number): FadingMarkdownSpan[] {
    const active = this.births.filter((birth: TextBirth) => now - birth.time < STREAM_TEXT_FADE_MS)
    const result: FadingMarkdownSpan[] = []
    let offset = 0
    spans.forEach((span: MarkdownSpan) => {
      const end = offset + span.text.length
      let cursor = offset
      active.forEach((birth: TextBirth) => {
        if (span.code || birth.end <= cursor || birth.start >= end) return
        const start = Math.max(cursor, birth.start)
        if (start > cursor) {
          result.push({ span: sliceSpan(span, span.text.substring(cursor - offset, start - offset)),
            start: cursor, opacity: 1 })
        }
        const stop = Math.min(end, birth.end)
        const progress = Math.min(1, Math.max(0, (now - birth.time) / STREAM_TEXT_FADE_MS))
        result.push({ span: sliceSpan(span, span.text.substring(start - offset, stop - offset)),
          start, opacity: 1 - (1 - progress) * (1 - progress) })
        cursor = stop
      })
      if (cursor < end) {
        result.push({ span: sliceSpan(span, span.text.substring(cursor - offset)), start: cursor, opacity: 1 })
      }
      offset = end
    })
    return result
  }
}
