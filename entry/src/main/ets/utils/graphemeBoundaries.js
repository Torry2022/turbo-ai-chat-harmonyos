// Ark's Intl.Segmenter is not declared in the current ArkTS SDK typings.
const segmenter = new Intl.Segmenter('zh', { granularity: 'grapheme' });

export function graphemeBoundaries(text) {
  const ends = [];
  for (const part of segmenter.segment(text)) ends.push(part.index + part.segment.length);
  return ends;
}
