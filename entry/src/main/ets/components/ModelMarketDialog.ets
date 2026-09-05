import { ChatViewModel } from '../state/ChatViewModel'
import { ModelCatalogItem, formatBytes } from '../models/BuiltinModelDownloadTypes'

@Component
export struct ModelMarketDialog {
  @ObjectLink viewModel: ChatViewModel
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  @State isClosePressed: boolean = false
  private searchController: TextInputController = new TextInputController()

  private padTimePart(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private formatCatalogPublishedAt(value: string): string {
    if (value.length <= 0) {
      return ''
    }
    const publishedAt = new Date(value)
    if (!Number.isFinite(publishedAt.getTime())) {
      return value.replace('T', ' ').substring(0, Math.min(16, value.length))
    }
    return `${publishedAt.getFullYear()}年${publishedAt.getMonth() + 1}月${publishedAt.getDate()}日 ` +
      `${this.padTimePart(publishedAt.getHours())}:${this.padTimePart(publishedAt.getMinutes())}`
  }

  private catalogMetadata(): string {
    let metadata = this.viewModel.modelCatalogSource
    if (this.viewModel.modelCatalogVersion > 0) {
      metadata += `，目录版本 ${this.viewModel.modelCatalogVersion}`
    }
    const publishedAt = this.formatCatalogPublishedAt(this.viewModel.modelCatalogPublishedAt)
    if (publishedAt.length > 0) {
      metadata += `，发布于 ${publishedAt}`
    }
    return metadata
  }

  @Builder
  private FilterButton(label: string) {
    Button(label)
      .height(40)
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
            .layoutWeight(item.recommended ? 0 : 1)
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
        .height(40)
        .width(68)
        .fontSize(12)
        .fontColor(this.viewModel.isCatalogItemInstalled(item.id) ? '#8DE4C3' : '#F4FBFF')
        .backgroundColor(this.viewModel.isCatalogItemInstalled(item.id) ? '#12372E' : '#0F62FE')
        .borderRadius(8)
        .enabled(!this.viewModel.isCatalogItemInstalled(item.id) &&
          !this.viewModel.busy &&
          !this.viewModel.modelLoading &&
          !this.viewModel.modelImporting &&
          !this.viewModel.builtinModelInstalling &&
          !this.viewModel.modelCatalogRefreshing)
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
        .focusable(false)
        .width('100%')
        .height('100%')
        .backgroundColor('#000000B3')
        .onClick(() => {
          this.viewModel.dismissTopDialogIfIdle()
        })

      Column({ space: 12 }) {
        Row() {
          Text('模型广场')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .layoutWeight(1)
          Button(this.viewModel.modelCatalogRefreshing ? '更新中' : '刷新')
            .height(40)
            .width(58)
            .fontSize(11)
            .fontColor('#5AB0F2')
            .backgroundColor('#0A1623')
            .border({ width: 1, color: '#1F5C83' })
            .enabled(!this.viewModel.modelCatalogRefreshing && !this.viewModel.builtinModelInstalling)
            .onClick(() => {
              this.viewModel.refreshModelCatalog()
            })
          Button({ type: ButtonType.Normal }) {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') : $r('app.media.model_market_close_icon'))
              .width(24)
              .height(24)
          }
          .width(40)
          .height(40)
          .focusable(true)
          .accessibilityText('关闭模型广场')
          .hoverEffect(HoverEffect.Auto)
          .backgroundColor(Color.Transparent)
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

        Column({ space: 2 }) {
          Text(this.viewModel.modelCatalogStatus)
            .fontSize(12)
            .lineHeight(17)
            .fontColor(this.viewModel.modelCatalogStatus.indexOf('失败') >= 0 ? '#F2B35D' : '#8CA2B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.catalogMetadata())
            .fontSize(10)
            .lineHeight(15)
            .fontColor('#5F768D')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        TextInput({ text: this.viewModel.modelMarketSearchText, placeholder: '搜索模型名称或厂商',
          controller: this.searchController })
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
        .align(Alignment.Start)
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
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, {
          alwaysEnabled: true
        })
        .onClick(() => this.searchController.stopEditing())
      }
      .width(Math.max(1, Math.min(840, this.availableWidth - 32)))
      .height(Math.max(1, Math.min(800, this.availableHeight * 0.85)))
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
