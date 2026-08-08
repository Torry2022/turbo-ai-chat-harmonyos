import { describe, expect, it } from '@ohos/hypium'
import { calculateDownloadedBytes, calculateDownloadProgress } from '../../../main/ets/utils/downloadProgress'
import {
  MODEL_PREFLIGHT_CONFIG_INVALID,
  MODEL_PREFLIGHT_CONFIG_REFERENCE_MISSING,
  MODEL_PREFLIGHT_FILE_SIZE_MISMATCH,
  MODEL_PREFLIGHT_TEMPLATE_INCOMPATIBLE,
  MODEL_PREFLIGHT_VISUAL_FILES_MISSING,
  ExpectedModelFile,
  inferSupportsImageFromLlmConfig,
  ModelDirectorySnapshot,
  validateModelDirectorySnapshot
} from '../../../main/ets/utils/modelCompatibility'
import {
  importedModelShortName,
  isLegacyFamilyOnlyImportedShortName,
  stripMnnSuffix
} from '../../../main/ets/utils/modelNaming'
import {
  MODEL_CATALOG_ITEMS,
  findModelCatalogItem
} from '../../../main/ets/models/BuiltinModelDownloadTypes'
import { ModelProfile } from '../../../main/ets/models/ModelProfile'
import { ModelImportService } from '../../../main/ets/services/ModelImportService'
import { formatDownloadError } from '../../../main/ets/utils/formatters'
import {
  catalogItemToProfile,
  mergeRemoteModelCatalog,
  parseRemoteModelCatalog
} from '../../../main/ets/utils/modelCatalog'
import {
  ModelDragFrame,
  reorderVisibleModelIds,
  resolveModelDragPreview
} from '../../../main/ets/utils/modelDrag'

class DownloadErrorFixture {
  code: number = 2300007
  name: string = 'BusinessError'
  message: string = '网络不可用'
}

export default function modelRulesTest(): void {
  describe('ModelRules', () => {
    it('acceptsJinjaModelDirectory', 0, () => {
      const result = validateModelDirectorySnapshot(validSnapshot())
      expect(result.compatible).assertTrue()
      expect(result.legacyTemplate).assertFalse()
    })

    it('acceptsLegacyChatMlForAutomaticUpgrade', 0, () => {
      const snapshot = validSnapshot()
      snapshot.llmConfigText = JSON.stringify({
        prompt_template: '<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n%s<|im_end|>'
      })
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertTrue()
      expect(result.legacyTemplate).assertTrue()
    })

    it('rejectsUnknownMissingTemplate', 0, () => {
      const snapshot = validSnapshot()
      snapshot.llmConfigText = '{}'
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_TEMPLATE_INCOMPATIBLE)
    })

    it('rejectsCatalogFileSizeMismatch', 0, () => {
      const snapshot = validSnapshot()
      const expectedFile: ExpectedModelFile = { relativePath: 'llm.mnn.weight', sizeBytes: 101 }
      snapshot.expectedFiles = [expectedFile]
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_FILE_SIZE_MISMATCH)
    })

    it('rejectsConfigWithoutMainModelReference', 0, () => {
      const snapshot = validSnapshot()
      snapshot.configText = '{}'
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_CONFIG_INVALID)
    })

    it('rejectsMissingReferencedWeight', 0, () => {
      const snapshot = validSnapshot()
      snapshot.files = snapshot.files.filter((file) => file.relativePath !== 'llm.mnn.weight')
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_CONFIG_REFERENCE_MISSING)
    })

    it('acceptsTiedEmbeddingWithoutSeparateFile', 0, () => {
      const snapshot = validSnapshot()
      snapshot.configText = '{"llm_model":"llm.mnn","llm_weight":"llm.mnn.weight","embedding_file":"embeddings_int4.bin"}'
      snapshot.llmConfigText = '{"jinja":{"chat_template":"{{ messages }}"},"tie_embeddings":[1,2,3]}'
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertTrue()
    })

    it('rejectsMissingEmbeddingWithoutTieMetadata', 0, () => {
      const snapshot = validSnapshot()
      snapshot.configText = '{"llm_model":"llm.mnn","llm_weight":"llm.mnn.weight","embedding_file":"embeddings_int4.bin"}'
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_CONFIG_REFERENCE_MISSING)
    })

    it('rejectsIncompleteVisualModel', 0, () => {
      const snapshot = validSnapshot()
      snapshot.supportsImage = true
      const result = validateModelDirectorySnapshot(snapshot)
      expect(result.compatible).assertFalse()
      expect(result.code).assertEqual(MODEL_PREFLIGHT_VISUAL_FILES_MISSING)
    })

    it('detectsVisualCapabilityFromLlmConfig', 0, () => {
      expect(inferSupportsImageFromLlmConfig('{"is_visual":true}')).assertTrue()
      expect(inferSupportsImageFromLlmConfig('{"is_visual":false}')).assertFalse()
      expect(inferSupportsImageFromLlmConfig('invalid json')).assertFalse()
    })

    it('normalizesImportedModelNames', 0, () => {
      expect(stripMnnSuffix('Qwen2-0.5B-Instruct-MNN')).assertEqual('Qwen2-0.5B-Instruct')
      expect(importedModelShortName('Qwen2-0.5B-Instruct-MNN')).assertEqual('Qwen2-0.5B-Instruct')
      expect(importedModelShortName('Qwen3-4B-Instruct-2507-MNN')).assertEqual('Qwen3-4B-Instruct')
      expect(importedModelShortName('Qwen-1_8B-Chat-MNN')).assertEqual('Qwen-1_8B-Chat')
      expect(importedModelShortName('Model-Family-Instruct-MNN')).assertEqual('Model-Family-Instruct')
      expect(importedModelShortName('Very-Long-Model-Family-Name-1.5B-Instruct-MNN')).assertEqual(
        'Very-Long-Model-Family-Name-1.5B'
      )
      expect(isLegacyFamilyOnlyImportedShortName('Qwen3-0.6B-MNN', 'Qwen3')).assertTrue()
      expect(isLegacyFamilyOnlyImportedShortName('MiniMind2-MNN', 'MiniMind2')).assertFalse()
    })

    it('updatesImportedModelDescription', 0, () => {
      const service = new ModelImportService()
      const profile: ModelProfile = {
        id: 'imported-test',
        name: 'Imported Test',
        shortName: 'Test',
        directoryName: 'Imported-Test-MNN',
        description: '旧描述',
        supportsImage: false,
        systemPrompt: '测试提示词',
        source: 'imported'
      }
      const draft = service.createDraft(profile)
      draft.description = '新的模型描述'
      expect(service.applyDraft(profile, draft).description).assertEqual('新的模型描述')
    })

    it('calculatesDownloadProgressWithoutOverflow', 0, () => {
      expect(calculateDownloadedBytes(40, 30, 100)).assertEqual(70)
      expect(calculateDownloadedBytes(90, 30, 100)).assertEqual(100)
      expect(calculateDownloadProgress(25, 100)).assertEqual(25)
      expect(calculateDownloadProgress(120, 100)).assertEqual(100)
    })

    it('formatsDownloadErrorsForUsers', 0, () => {
      expect(formatDownloadError(new Error('Error: llm.mnn.weight 下载失败：HTTP 404')))
        .assertEqual('llm.mnn.weight 下载失败：HTTP 404')
      expect(formatDownloadError(new DownloadErrorFixture()))
        .assertEqual('错误码 2300007：网络不可用')
    })

    it('reordersModelCardsAcrossEveryEqualHeightPosition', 0, () => {
      const frames: ModelDragFrame[] = [
        { top: 0, height: 60 },
        { top: 68, height: 60 },
        { top: 136, height: 60 },
        { top: 204, height: 60 }
      ]
      for (let startIndex = 0; startIndex < frames.length; startIndex++) {
        for (let targetIndex = 0; targetIndex < frames.length; targetIndex++) {
          const startCenter = frames[startIndex].top + frames[startIndex].height / 2
          const targetCenter = frames[targetIndex].top + frames[targetIndex].height / 2
          expect(resolveModelDragPreview(frames, startIndex, targetCenter - startCenter).targetIndex)
            .assertEqual(targetIndex)
        }
      }
      expect(resolveModelDragPreview(frames, 2, -180).offsetY).assertEqual(-180)
      expect(resolveModelDragPreview(frames, 2, -180).targetIndex).assertEqual(0)
      expect(resolveModelDragPreview(frames, 1, -67).targetIndex).assertEqual(1)
      expect(resolveModelDragPreview(frames, 1, 20).targetIndex).assertEqual(1)
    })

    it('reordersDifferentHeightModelCardsAtBothBoundaries', 0, () => {
      const frames: ModelDragFrame[] = [
        { top: 0, height: 80 },
        { top: 88, height: 40 },
        { top: 136, height: 100 },
        { top: 244, height: 50 }
      ]
      expect(resolveModelDragPreview(frames, 2, -146).targetIndex).assertEqual(0)
      expect(resolveModelDragPreview(frames, 1, 161).targetIndex).assertEqual(3)
      expect(resolveModelDragPreview(frames, 0, 300).targetIndex).assertEqual(3)
      expect(resolveModelDragPreview(frames, 3, -300).targetIndex).assertEqual(0)
    })

    it('keepsHiddenMarketModelsOutOfVisibleDragIndexes', 0, () => {
      const allIds = ['visible-a', 'hidden-a', 'visible-b', 'hidden-b', 'visible-c']
      const visibleIds = ['visible-a', 'visible-b', 'visible-c']
      expect(reorderVisibleModelIds(allIds, visibleIds, 'visible-c', 0).join(','))
        .assertEqual('visible-c,hidden-a,visible-a,hidden-b,visible-b')
      expect(reorderVisibleModelIds(allIds, visibleIds, 'visible-a', 2).join(','))
        .assertEqual('visible-b,hidden-a,visible-c,hidden-b,visible-a')
    })

    it('keepsQwen3VlCatalogManifestComplete', 0, () => {
      const item = findModelCatalogItem('qwen3-vl-4b-instruct')
      expect(item === undefined).assertFalse()
      if (item === undefined) {
        return
      }
      expect(item.supportsImage).assertTrue()
      expect(item.files.length).assertEqual(7)
      expect(item.totalBytes).assertEqual(2957221068)
    })

    it('keepsPresetAndHidesOptionalBundledCatalogItem', 0, () => {
      const manifest = parseRemoteModelCatalog(
        '{"schemaVersion":1,"catalogVersion":2,"publishedAt":"2026-07-18T12:00:00+08:00",' +
          '"hiddenIds":["qwen3-4b-instruct","qwen3-0.6b"],"items":[]}'
      )
      const merged = mergeRemoteModelCatalog(MODEL_CATALOG_ITEMS, manifest)
      expect(merged.some((item) => item.id === 'qwen3-4b-instruct')).assertTrue()
      expect(merged.some((item) => item.id === 'qwen3-0.6b')).assertFalse()
    })

    it('createsRuntimeProfileForRemoteCatalogModel', 0, () => {
      const manifest = parseRemoteModelCatalog(remoteCatalogText('config.json'))
      const merged = mergeRemoteModelCatalog(MODEL_CATALOG_ITEMS, manifest)
      const item = merged.find((candidate) => candidate.id === 'remote-test-model')
      expect(item === undefined).assertFalse()
      if (item === undefined) {
        return
      }
      const profile = catalogItemToProfile(item)
      expect(profile === undefined).assertFalse()
      expect(profile?.source).assertEqual('catalog')
      expect(profile?.directoryName).assertEqual('Remote-Test-MNN')
    })

    it('rejectsUnsafeRemoteCatalogPath', 0, () => {
      let rejected = false
      try {
        parseRemoteModelCatalog(remoteCatalogText('../config.json'))
      } catch (_) {
        rejected = true
      }
      expect(rejected).assertTrue()
    })
  })
}

function remoteCatalogText(configPath: string): string {
  return '{"schemaVersion":1,"catalogVersion":3,"publishedAt":"2026-07-18T12:00:00+08:00",' +
    '"hiddenIds":[],"items":[{"id":"remote-test-model",' +
    '"directoryName":"Remote-Test-MNN","displayName":"Remote Test","shortName":"Remote Test",' +
    '"description":"远程目录测试模型","provider":"Test","supportsImage":false,' +
    '"capabilities":["文本"],"source":{"type":"modelscope","repo":"Test/Remote-Test-MNN",' +
    '"revision":"abc123"},"files":[{"relativePath":"' + configPath + '","sizeBytes":100},' +
    '{"relativePath":"llm_config.json","sizeBytes":100},{"relativePath":"llm.mnn","sizeBytes":100},' +
    '{"relativePath":"llm.mnn.weight","sizeBytes":100}],"runtime":{"systemPrompt":"你是远程目录测试模型。",' +
    '"contextMessageLimit":4,"generationDefaults":{"temperature":0.6,"topP":0.9,"topK":40}}}]}'
}

function validSnapshot(): ModelDirectorySnapshot {
  return {
    configText: '{"llm_model":"llm.mnn","llm_weight":"llm.mnn.weight"}',
    llmConfigText: '{"jinja":{"chat_template":"{{ messages }}"}}',
    files: [
      { relativePath: 'config.json', sizeBytes: 100 },
      { relativePath: 'llm_config.json', sizeBytes: 100 },
      { relativePath: 'tokenizer.txt', sizeBytes: 100 },
      { relativePath: 'llm.mnn', sizeBytes: 100 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 100 }
    ],
    expectedFiles: [],
    supportsImage: false
  }
}
