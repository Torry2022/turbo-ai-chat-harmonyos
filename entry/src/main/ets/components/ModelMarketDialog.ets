import { ChatViewModel } from '../state/ChatViewModel'
import { ModelCatalogItem, formatBytes } from '../models/BuiltinModelDownloadTypes'

@Component
export struct ModelMarketDialog {
  @ObjectLink viewModel: ChatViewModel
  @State isClosePressed: boolean = false

  @Builder
  private FilterButton(label: string) {
    Button(label)
      .height(30)
      .fontSize(12)
      .fontColor(this.viewModel.modelMarketCapabilityFilter === label ? '#F4FBFF' : '#5AB0F2')
      .backgroundColor(this.viewModel.modelMarketCapabilityFilter === label ? '#14344A' : '#0A1623')
      .border({ width: 1, color: '#1F5C83' })
      .borderRadius(15)
      .onClick(() => {
        this.viewModel.updateModelMarketCapabilityFilter(label)
      })
  }

  @Builder
  private CapabilityTag(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(text === '图片' ? '#8DE4C3' : '#5AB0F2')
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(text === '图片' ? '#12372E' : '#0D2A42')
      .borderRadius(4)
  }

  @Builder
  private PresetTag() {
    Text('预置')
      .fontSize(10)
      .fontColor('#8DE4C3')
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor('#12372E')
      .borderRadius(4)
  }

  @Builder
  private CatalogItemCard(item: ModelCatalogItem) {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(item.displayName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (item.recommended) {
            this.PresetTag()
          }
        }
        .width('100%')

        Text(`${formatBytes(item.totalBytes)} · ${item.provider} · ${item.sourceName}`)
          .fontSize(12)
          .fontColor('#8CA2B8')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(item.description)
          .fontSize(12)
          .lineHeight(17)
          .fontColor('#6F86A0')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 6 }) {
          ForEach(item.capabilities, (capability: string) => {
            this.CapabilityTag(capability)
          }, (capability: string) => capability)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button(this.viewModel.isCatalogItemInstalled(item.id) ? '已安装' : '下载')
        .height(28)
        .width(68)
        .fontSize(12)
        .fontColor(this.viewModel.isCatalogItemInstalled(item.id) ? '#8DE4C3' : '#F4FBFF')
        .backgroundColor(this.viewModel.isCatalogItemInstalled(item.id) ? '#12372E' : '#0F62FE')
        .borderRadius(8)
        .enabled(!this.viewModel.isCatalogItemInstalled(item.id) &&
      !this.viewModel.busy &&
          !this.viewModel.modelLoading &&
          !this.viewModel.modelImporting &&
          !this.viewModel.builtinModelInstalling)
        .onClick(() => {
          this.viewModel.installCatalogItem(item.id)
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#0A1623')
    .borderRadius(8)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000B3')
        .onClick(() => {
          this.viewModel.dismissTopDialogIfIdle()
        })

      Column({ space: 12 }) {
        Row() {
          Text('模型市场')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .layoutWeight(1)
          Row() {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') : $r('app.media.model_market_close_icon'))
              .width(24)
              .height(24)
          }
          .width(30)
          .height(30)
          .justifyContent(FlexAlign.Center)
          .enabled(!this.viewModel.builtinModelInstalling)
          .opacity(this.viewModel.builtinModelInstalling ? 0.4 : 1)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.isClosePressed = true
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isClosePressed = false
            }
          })
          .onClick(() => {
            this.viewModel.closeModelMarketDialog()
          })
        }
        .padding({ left: 2 })
        .width('100%')

        TextInput({ text: this.viewModel.modelMarketSearchText, placeholder: '搜索模型名称或厂商' })
          .height(40)
          .fontSize(13)
          .fontColor('#EAF4FF')
          .placeholderColor('#6F86A0')
          .backgroundColor('#0A1623')
          .borderRadius(8)
          .onChange((value: string) => {
            this.viewModel.updateModelMarketSearchText(value)
          })

        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.viewModel.modelCatalogFilterTags(), (tag: string) => {
              this.FilterButton(tag)
            }, (tag: string) => tag)
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.viewModel.modelCatalogItems(), (item: ModelCatalogItem) => {
              this.CatalogItemCard(item)
            }, (item: ModelCatalogItem) => item.id)
          }
          .width('100%')
        }
        .height(380)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, {
          alwaysEnabled: true
        })
      }
      .width('90%')
      .padding({ top: 14, bottom: 14, left: 12, right: 12 })
      .backgroundColor('#102235')
      .border({ width: 1, color: '#23445F' })
      .borderRadius(10)
      .shadow({
        radius: 24,
        color: '#00000088',
        offsetX: 0,
        offsetY: 10
      })
    }
    .width('100%')
    .height('100%')
  }
}
