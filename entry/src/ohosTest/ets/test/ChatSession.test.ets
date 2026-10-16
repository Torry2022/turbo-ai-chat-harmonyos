import { describe, expect, it } from '@ohos/hypium'
import { ChatSession } from '../../../main/ets/state/ChatSession'

export default function chatSessionTest(): void {
  describe('ChatSession', () => {
    it('keepsOnlyCompleteRecentTurnPairs', 0, () => {
      const session = new ChatSession()
      session.appendMessage('user', '问题一')
      session.appendMessage('assistant', '回答一。')
      session.appendMessage('user', '问题二')
      session.appendMessage('assistant', '回答二。')
      const turns = session.composeChatTurns('系统提示', '问题三', 2)
      expect(turns.length).assertEqual(4)
      expect(turns[0].role).assertEqual('system')
      expect(turns[1].content).assertEqual('问题二')
      expect(turns[2].content).assertEqual('回答二。')
      expect(turns[3].content).assertEqual('问题三')
    })

    it('excludesIncompleteAssistantTurn', 0, () => {
      const session = new ChatSession()
      session.appendMessage('user', '问题')
      session.appendMessage('assistant', '<think>尚未完成')
      const turns = session.composeChatTurns('系统提示', '新问题', 6)
      expect(turns.length).assertEqual(2)
      expect(turns[1].content).assertEqual('新问题')
    })

    it('neverSplitsTurnPairsForOddContextLimits', 0, () => {
      const session = new ChatSession()
      session.appendMessage('user', '问题一')
      session.appendMessage('assistant', '回答一。')
      session.appendMessage('user', '问题二')
      session.appendMessage('assistant', '回答二。')
      const turns = session.composeChatTurns('系统提示', '问题三', 3)
      expect(turns.length).assertEqual(4)
      expect(turns[1].content).assertEqual('问题二')
      expect(turns[2].content).assertEqual('回答二。')
      expect(turns[3].content).assertEqual('问题三')
    })

    it('excludesStoppedAndFailedAnswersFromContext', 0, () => {
      const session = new ChatSession()
      session.appendMessage('user', '问题一')
      const stopped = session.appendMessage('assistant', '未完成回答')
      session.updateMessage(stopped, '未完成回答', false)
      session.markGeneration(stopped, 'stopped')
      session.appendMessage('user', '问题二')
      const failed = session.appendMessage('assistant', '部分回答')
      session.updateMessage(failed, '部分回答', false)
      session.markGeneration(failed, 'failed')
      const turns = session.composeChatTurns('系统提示', '问题三', 6)
      expect(turns.length).assertEqual(2)
      expect(turns[1].content).assertEqual('问题三')
    })
  })
}
