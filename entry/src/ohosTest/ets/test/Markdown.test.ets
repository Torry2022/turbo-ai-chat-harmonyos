import { describe, expect, it } from '@ohos/hypium'
import { parseInlineMarkdown, parseLightMarkdown } from '../../../main/ets/utils/markdown'

export default function markdownTest(): void {
  describe('MarkdownParser', () => {
    it('normalizesTableColumnsAndPreservesEmptyCells', 0, () => {
      const blocks = parseLightMarkdown('| A | B | C |\n| --- | --- | --- |\n| 1 | | 3 |\n| 4 | 5 |')
      expect(blocks.length).assertEqual(1)
      expect(JSON.stringify(blocks[0].headers)).assertEqual(JSON.stringify(['A', 'B', 'C']))
      expect(JSON.stringify(blocks[0].rows)).assertEqual(JSON.stringify([['1', '', '3'], ['4', '5', '']]))
    })

    it('keepsOrderedListStartNumber', 0, () => {
      const blocks = parseLightMarkdown('3. third\n4. fourth')
      expect(blocks[0].type).assertEqual('ordered-list')
      expect(blocks[0].startNumber).assertEqual(3)
      expect(JSON.stringify(blocks[0].items)).assertEqual(JSON.stringify(['third', 'fourth']))
    })

    it('rendersIncompleteInlineCodeDuringStreaming', 0, () => {
      const spans = parseInlineMarkdown('run `hvigorw')
      expect(spans.length).assertEqual(2)
      expect(spans[1].code).assertTrue()
      expect(spans[1].text).assertEqual('hvigorw')
    })

  })
}
