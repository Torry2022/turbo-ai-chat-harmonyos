import { graphemeBoundaries } from './graphemeBoundaries'

export const STREAM_DISPLAY_INTERVAL_MS: number = 16

let cachedText: string = ''
let cachedEnds: number[] = []

function graphemeEnds(text: string): number[] {
  if (text === cachedText) return cachedEnds
  const append = text.startsWith(cachedText)
  // Only the trailing cluster can grow when more text arrives.
  const keep = append ? Math.max(0, cachedEnds.length - 1) : 0
  const start = keep > 0 ? cachedEnds[keep - 1] : 0
  cachedEnds.length = keep
  for (const end of graphemeBoundaries(text.substring(start))) {
    cachedEnds.push(start + end)
  }
  cachedText = text
  return cachedEnds
}

export class StreamingDisplay {
  text: string = ''
  private credit: number = 0

  reset(): void {
    this.text = ''
    this.credit = 0
  }

  advance(received: string, elapsedMs: number): string {
    if (!received.startsWith(this.text)) {
      this.credit = 0
      this.text = received
      return this.text
    }
    const ends = graphemeEnds(received)
    let left = 0
    let right = ends.length
    while (left < right) {
      const middle = Math.floor((left + right) / 2)
      if (ends[middle] <= this.text.length) left = middle + 1
      else right = middle
    }
    // Keep the trailing cluster until another boundary arrives or generation finishes.
    const pending = Math.max(0, ends.length - 1 - left)
    if (pending === 0) {
      this.credit = 0
      return this.text
    }
    // Show the first complete cluster promptly, then spread bursts across frames.
    if (this.text.length === 0) {
      this.text = received.substring(0, ends[left])
      return this.text
    }
    const rate = Math.max(24, pending * 1000 / 250)
    this.credit = Math.min(4, this.credit + rate * Math.max(0, Math.min(elapsedMs, 32)) / 1000)
    const step = Math.min(pending, Math.floor(this.credit))
    if (step > 0) {
      this.credit -= step
      this.text = received.substring(0, ends[left + step - 1])
    }
    return this.text
  }
}
