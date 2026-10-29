import { BuiltinModelDownloadSpec } from './BuiltinModelDownloadTypes'

export const LAYA_MODEL_ID = 'Laya-Multilingual-MNN-FP16'
export const LAYA_SHORT_NAME = 'Laya'
export const LAYA_MODEL_DIRECTORY = 'laya-probe'
export const LAYA_MODEL_FILE = 'laya.mnn'
export const LAYA_TOKENIZER_FILE = 'laya.tokbin'
export const LAYA_MODEL_BYTES = 644944912
export const LAYA_TOKENIZER_BYTES = 13257378

const LAYA_REPO = 'TorryJi/Laya-Multilingual-MNN-FP16'
const LAYA_REVISION = '4e8478fb2bf840c244f2afaaea4c572a61ff3c9e'
const LAYA_BASE_URL = `https://modelscope.cn/models/${LAYA_REPO}/resolve/${LAYA_REVISION}`

export const LAYA_DOWNLOAD_SPEC: BuiltinModelDownloadSpec = {
  id: 'laya-multilingual-mnn-fp16',
  modelId: LAYA_REPO,
  directoryName: LAYA_MODEL_DIRECTORY,
  displayName: LAYA_MODEL_ID,
  sourceName: 'ModelScope',
  sourceUrl: `https://modelscope.cn/models/${LAYA_REPO}`,
  files: [
    { relativePath: LAYA_MODEL_FILE, sizeBytes: LAYA_MODEL_BYTES, url: `${LAYA_BASE_URL}/${LAYA_MODEL_FILE}` },
    { relativePath: LAYA_TOKENIZER_FILE, sizeBytes: LAYA_TOKENIZER_BYTES, url: `${LAYA_BASE_URL}/${LAYA_TOKENIZER_FILE}` }
  ],
  totalBytes: LAYA_MODEL_BYTES + LAYA_TOKENIZER_BYTES
}
