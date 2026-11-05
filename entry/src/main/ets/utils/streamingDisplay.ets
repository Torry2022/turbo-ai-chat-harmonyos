import { graphemeBoundaries } from './graphemeBoundaries'

export const STREAM_DISPLAY_INTERVAL_MS: number = 50

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

export function advanceStreamingDisplay(shown: string, received: string, elapsedMs: number): string {
  if (!received.startsWith(shown)) return received
  const ends = graphemeEnds(received)
  let left = 0
  let right = ends.length
  while (left < right) {
    const middle = Math.floor((left + right) / 2)
    if (ends[middle] <= shown.length) left = middle + 1
    else right = middle
  }
  // A following chunk can still add a skin tone, combining mark or ZWJ sequence.
  // Keep the last cluster pending until the next boundary or the final full-text flush.
  const pending = Math.max(0, ends.length - 1 - left)
  if (pending <= 0) return shown
  const step = Math.min(8, Math.max(1, Math.ceil(pending * Math.min(elapsedMs, 250) / 250)))
  return received.substring(0, ends[left + step - 1])
}
