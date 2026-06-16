import { common } from '@kit.AbilityKit'
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import image from '@ohos.multimedia.image'
import { ImagePayload, VISION_MAX_PIXELS } from '../models/ChatTypes'

export class ImagePayloadService {
  pickImage(context: common.UIAbilityContext): Promise<string | undefined> {
    const photoPicker = new picker.PhotoViewPicker(context)
    const options = new picker.PhotoSelectOptions()
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
    options.maxSelectNumber = 1
    return photoPicker.select(options).then((result: picker.PhotoSelectResult) => {
      return result.photoUris.length > 0 ? result.photoUris[0] : undefined
    })
  }

  async buildImagePayload(uri: string): Promise<ImagePayload> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    const source = image.createImageSource(file.fd)
    let pixelMap: image.PixelMap | undefined = undefined
    try {
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
    } finally {
      if (pixelMap) {
        await pixelMap.release()
      }
      source.release()
      fs.closeSync(file)
    }
  }
}
