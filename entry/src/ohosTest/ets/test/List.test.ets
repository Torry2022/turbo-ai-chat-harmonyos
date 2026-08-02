import chatSessionTest from './ChatSession.test'
import markdownTest from './Markdown.test'
import modelRulesTest from './ModelRules.test'
import thinkingTest from './Thinking.test'
import generationMetricsTest from './GenerationMetrics.test'
import openAiApiServerTest from './OpenAiApiServer.test'

export default function testsuite(): void {
  markdownTest()
  thinkingTest()
  chatSessionTest()
  modelRulesTest()
  generationMetricsTest()
  openAiApiServerTest()
}
