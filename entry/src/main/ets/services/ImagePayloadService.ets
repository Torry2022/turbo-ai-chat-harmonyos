import photoAccessHelper from '@ohos.file.photoAccessHelper'
import fs from '@ohos.file.fs'
import image from '@ohos.multimedia.image'
import { ImagePayload, VISION_MAX_PIXELS } from '../models/ChatTypes'

export class ImagePayloadService {
  async pickImage(): Promise<string | undefined> {
    const photoPicker = new photoAccessHelper.PhotoViewPicker()
    const options = new photoAccessHelper.PhotoSelectOptions()
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    try {
      const result = await photoPicker.select(options)
      return result.photoUris.length > 0 ? result.photoUris[0] : undefined
    } catch (_) {
      return undefined
    }
  }

  async buildImagePayload(uri: string): Promise<ImagePayload> {
    let file: fs.File | undefined = undefined
    let source: image.ImageSource | undefined = undefined
    let pixelMap: image.PixelMap | undefined = undefined
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
      source = image.createImageSource(file.fd)
      const sourceInfo = await source.getImageInfo()
      const sourceWidth = sourceInfo.size.width
      const sourceHeight = sourceInfo.size.height
      const sourcePixels = sourceWidth * sourceHeight
      const scale = sourcePixels > VISION_MAX_PIXELS ? Math.sqrt(VISION_MAX_PIXELS / sourcePixels) : 1
      const targetWidth = Math.max(1, Math.round(sourceWidth * scale))
      const targetHeight = Math.max(1, Math.round(sourceHeight * scale))

      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: targetWidth,
          height: targetHeight
        }
      })
      if (!pixelMap) {
        pixelMap = await source.createPixelMap({
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        })
      }
      if (!pixelMap) {
        throw new Error('createPixelMap returned undefined')
      }
      const info = await pixelMap.getImageInfo()
      const width = info.size.width
      const height = info.size.height
      const pixels = new ArrayBuffer(width * height * 4)
      await pixelMap.readPixelsToBuffer(pixels)
      return { pixels, width, height }
    } catch (err) {
      throw new Error(`图片读取失败：${err}`)
    } finally {
      if (pixelMap) {
        await pixelMap.release()
      }
      if (source) {
        source.release()
      }
      if (file) {
        try {
          fs.closeSync(file)
        } catch (_) {
        }
      }
    }
  }
}
