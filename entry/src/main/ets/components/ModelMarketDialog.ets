import { InputFieldStyle } from './ControlStyles'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
import { ModelType, ModelTypeSelector } from './ModelTypeSelector'
import { ChatViewModel } from '../state/ChatViewModel'
import { ModelCatalogItem, formatBytes } from '../models/BuiltinModelDownloadTypes'

import { dialogFade, dialogScale } from './DialogMotion'

interface ModelMarketRow { key: string; items: ModelCatalogItem[] }

class ModelMarketRows implements IDataSource {
  private rows: ModelMarketRow[] = []
  private listeners: DataChangeListener[] = []
  private signature: string = ''
  totalCount(): number { return this.rows.length }
  getData(index: number): ModelMarketRow { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener)
  }
  replace(rows: ModelCatalogItem[][], variants: Map<string, ModelCatalogItem[]> = new Map()): void {
    const keys = rows.map((items: ModelCatalogItem[]): string => JSON.stringify(items.map((item: ModelCatalogItem) =>
      item.variantGroup === undefined ? item : variants.get(item.variantGroup) ?? [item])))
    const signature = JSON.stringify(keys)
    if (signature === this.signature) return
    this.signature = signature
    this.rows = rows.map((items: ModelCatalogItem[], index: number): ModelMarketRow => ({ key: keys[index], items }))
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

@Component
export struct ModelMarketDialog {
  @ObjectLink viewModel: ChatViewModel
  @Prop @Watch('refreshRows') availableWidth: number = 360
  @Prop @Watch('refreshRows') renderVersion: number = 0
  @Prop availableHeight: number = 640
  @State isClosePressed: boolean = false
  @State private hasRows: boolean = false
  @State private expandedVariantGroup: string = ''
  private searchController: TextInputController = new TextInputController()
  private rows: ModelMarketRows = new ModelMarketRows()
  private variantGroups: Map<string, ModelCatalogItem[]> = new Map()

  aboutToAppear(): void { this.refreshRows() }
  private refreshRows(): void {
    const items = this.viewModel.modelCatalogItems()
    const groups: Map<string, ModelCatalogItem[]> = new Map()
    for (const item of items) {
      if (item.variantGroup === undefined) continue
      const group = groups.get(item.variantGroup)
      if (group === undefined) groups.set(item.variantGroup, [item])
      else group.push(item)
    }
    this.variantGroups = groups
    this.rows.replace(this.catalogRows(items), groups)
    this.hasRows = this.rows.totalCount() > 0
  }

  private twoColumnCards(): boolean {
    return Math.min(840, this.availableWidth - 32) >= 720
  }

  private catalogRows(items: ModelCatalogItem[]): ModelCatalogItem[][] {
    const groups: Set<string> = new Set()
    const cards = items.filter((item: ModelCatalogItem): boolean => {
      const group = item.variantGroup
      if (group === undefined) return true
      if (groups.has(group)) return false
      groups.add(group)
      return true
    })
    const columns = this.twoColumnCards() ? 2 : 1
    const rows: ModelCatalogItem[][] = []
    for (let index = 0; index < cards.length; index += columns) {
      rows.push(cards.slice(index, index + columns))
    }
    return rows
  }

  private variants(item: ModelCatalogItem): ModelCatalogItem[] {
    if (item.variantGroup === undefined) return []
    return this.variantGroups.get(item.variantGroup) ?? []
  }

  private catalogWarning(): string {
    if (this.viewModel.modelCatalogRefreshing) return ''
    const status = this.viewModel.modelMarketStatus()
    return /失败|不可用|无效|尚未获取/.test(status) ? status : ''
  }

  @Builder
  private FilterButton(label: string) {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ActionButtonStyle(
        this.viewModel.modelMarketCapabilityFilter === label ?
          $r('app.color.selected_background') : $r('app.color.input_background'),
        this.viewModel.modelMarketCapabilityFilter === label ?
          $r('app.color.nav_tab_selected') : $r('app.color.text_secondary')))
      .height(32).fontSize(12).padding({ left: 12, right: 12 })
      .fontWeight(this.viewModel.modelMarketCapabilityFilter === label ? FontWeight.Medium : FontWeight.Normal)
      .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
      .id(`model-market-filter-${label}`)
      .onClick(() => {
        this.viewModel.updateModelMarketCapabilityFilter(label)
      })
  }

  @Builder
  private EmptyResults() {
    Column({ space: 12 }) {
      Image($r('app.media.model_search_empty'))
        .width(48)
        .height(48)
        .fillColor($r('app.color.text_muted'))
        .accessibilityLevel('no')
      Text('没有匹配的模型')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_title'))
      Text('试试其他关键词，或切换分类筛选')
        .fontSize(13)
        .fontColor($r('app.color.text_muted'))
        .textAlign(TextAlign.Center)
      Button('清空筛选', { type: ButtonType.Normal })
        .attributeModifier(new ActionButtonStyle(
          $r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
        .onClick(() => {
          this.searchController.stopEditing()
          this.viewModel.updateModelMarketSearchText('')
          this.viewModel.updateModelMarketCapabilityFilter('全部')
        })
    }
    .width('100%')
    .padding({ top: 40, bottom: 40, left: 12, right: 12 })
  }

  @Builder
  private CapabilityTag(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor(text === '图像理解' ? $r('app.color.tag_green_text') : $r('app.color.tag_blue_text'))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(text === '图像理解' ? $r('app.color.tag_green_background') : $r('app.color.tag_blue_background'))
      .borderRadius(4)
  }

  @Builder
  private PresetTag() {
    Text('预置')
      .fontSize(10)
      .fontColor($r('app.color.tag_green_text'))
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor($r('app.color.tag_green_background'))
      .borderRadius(4)
  }

  @Builder
  private DownloadVersion(item: ModelCatalogItem) {
    Button(this.viewModel.isCatalogItemInstalled(item.id) ? '已安装' : '下载', { type: ButtonType.Normal })
      .attributeModifier(new CompactActionStyle())
      .enabled(!this.viewModel.isCatalogItemInstalled(item.id) &&
        this.viewModel.catalogCompatibilityMessage(item).length === 0 &&
        !this.viewModel.busy && !this.viewModel.modelLoading && !this.viewModel.modelImporting &&
        !this.viewModel.modelCatalogRefreshing)
      .accessibilityText(`${this.viewModel.isCatalogItemInstalled(item.id) ? '已安装' : '下载'} ${item.displayName}`)
      .id(`model-market-download-${item.id}`)
      .onClick(() => { this.viewModel.installCatalogItem(item.id) })
  }

  @Builder
  private CatalogItemCard(item: ModelCatalogItem) {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        Text(this.variants(item).length > 1 ? item.variantGroup : item.displayName)
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        if (item.recommended) {
          this.PresetTag()
        }
      }.width('100%')

      Column() {
        Text(item.description)
          .fontSize(12).lineHeight(17).fontColor($r('app.color.text_hint'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: this.twoColumnCards() ? 34 : 0 })

      if (this.viewModel.catalogCompatibilityMessage(item).length > 0) {
        Text(this.viewModel.catalogCompatibilityMessage(item))
          .fontSize(11).lineHeight(16).fontColor($r('app.color.text_hint')).width('100%')
      }

      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(this.variants(item).length > 1 ? `${item.provider} / ${item.sourceName}` :
            `${item.files.length === 0 ? '约 ' : ''}${formatBytes(item.totalBytes)}  ${item.provider} / ${item.sourceName}`)
            .fontSize(11).lineHeight(16).fontColor($r('app.color.text_muted'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Row({ space: 4 }) {
            ForEach(this.viewModel.catalogCapabilities(item), (capability: string) => {
              this.CapabilityTag(capability)
            }, (capability: string) => capability)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.variants(item).length > 1) {
          Button(this.expandedVariantGroup === item.variantGroup ? '收起版本' : '选择版本', { type: ButtonType.Normal })
            .attributeModifier(new CompactActionStyle())
            .id(`model-market-versions-${item.id}`)
            .onClick(() => {
              this.expandedVariantGroup = this.expandedVariantGroup === item.variantGroup ? '' : (item.variantGroup ?? '')
            })
        } else if (this.viewModel.isCatalogItemInstalled(item.id)) {
          Row({ space: 4 }) {
            Image($r('app.media.icon_message_check')).width(16).height(16)
              .fillColor($r('app.color.tag_green_text'))
            Text('已安装').fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.tag_green_text'))
          }.width(76).height(30).justifyContent(FlexAlign.Center)
            .padding({ left: 8, right: 8 })
            .backgroundColor($r('app.color.tag_green_background'))
            .borderRadius($r('app.float.button_radius'))
            .border({ width: 0.5, color: $r('app.color.border'), radius: $r('app.float.button_radius') })
            .id(`model-market-installed-${item.id}`)
        } else {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              Image($r('app.media.icon_download')).width(16).height(16)
                .fillColor($r('app.color.button_action_text'))
              Text('下载').fontSize(12).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.button_action_text'))
            }.justifyContent(FlexAlign.Center)
          }
            .attributeModifier(new ActionButtonStyle(
              $r('app.color.tag_blue_background'), $r('app.color.button_action_text')))
            .height(30).width(76).padding({ left: 8, right: 8 })
            .border({ width: 0.5, color: $r('app.color.border'), radius: $r('app.float.button_radius') })
            .responseRegion({ x: 0, y: -5, width: '100%', height: 40 })
            .accessibilityText(`下载 ${item.displayName}`)
            .id(`model-market-download-${item.id}`)
            .enabled(this.viewModel.catalogCompatibilityMessage(item).length === 0 &&
              !this.viewModel.busy && !this.viewModel.modelLoading && !this.viewModel.modelImporting &&
              !this.viewModel.builtinModelInstalling && !this.viewModel.modelCatalogRefreshing)
            .onClick(() => { this.viewModel.installCatalogItem(item.id) })
        }
      }.width('100%')
      if (this.variants(item).length > 1 && this.expandedVariantGroup === item.variantGroup) {
        ForEach(this.variants(item), (variant: ModelCatalogItem) => {
          Row({ space: 6 }) {
            Text(`${variant.variantLabel} · ${formatBytes(variant.totalBytes)}`)
              .fontSize(12).fontColor($r('app.color.text_body')).layoutWeight(1)
            this.DownloadVersion(variant)
          }.width('100%').padding({ top: 4 })
        }, (variant: ModelCatalogItem) => variant.id)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(10)
    .backgroundColor($r('app.color.input_background'))
    .borderRadius($r('app.float.card_radius')).id(`model-market-item-${item.id}`)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .focusable(false)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim_busy'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.viewModel.dismissTopDialogIfIdle()
        })

      Column({ space: 10 }) {
        Row() {
          Text('模型广场')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .layoutWeight(1)
          Button(this.viewModel.modelCatalogRefreshing ? '更新中' : '刷新', { type: ButtonType.Normal })
            .attributeModifier(new CompactActionStyle())
            .height($r('app.float.button_height'))
            .responseRegion({ x: 0, y: 0, width: '100%', height: '100%' })
            .constraintSize({ minWidth: 64 })
            .padding({ left: 8, right: 8 })
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

        ModelTypeSelector({ selected: this.viewModel.modelMarketCategory, showReranker: true,
          onChange: (type: ModelType): void => {
            this.searchController.stopEditing()
            if (type === 'chat' || type === 'decision' || type === 'rerank' || type === 'embedding') this.viewModel.updateModelMarketCategory(type)
          } })
          .width('100%')

        if (this.catalogWarning().length > 0) {
          Text(this.catalogWarning())
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.status_warning'))
            .width('100%')
        }

        TextInput({ text: this.viewModel.modelMarketSearchText, placeholder: '搜索模型名称或厂商',
          controller: this.searchController })
          .attributeModifier(new InputFieldStyle())
          .height(36)
          .fontSize(13)
          .onChange((value: string) => {
            this.viewModel.updateModelMarketSearchText(value)
          })

        if (this.viewModel.modelMarketCategory === 'chat' && this.viewModel.modelCatalogFilterTags().length > 1) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.viewModel.modelCatalogFilterTags(), (tag: string) => {
                this.FilterButton(tag)
              }, (tag: string) => tag)
            }
          }
          .width('100%')
          .height(40)
          .scrollable(ScrollDirection.Horizontal)
          .align(Alignment.Start)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)

        }

        List({ space: 8 }) {
          if (!this.hasRows) {
            ListItem() { this.EmptyResults() }
          }
          LazyForEach(this.rows, (row: ModelMarketRow) => {
            ListItem() {
              Row({ space: 8 }) {
                ForEach(row.items, (item: ModelCatalogItem) => {
                  Column() {
                    this.CatalogItemCard(item)
                  }.layoutWeight(1)
                }, (item: ModelCatalogItem) => item.id)
                if (this.twoColumnCards() && row.items.length === 1) {
                  Column().layoutWeight(1)
                }
              }.width('100%').alignItems(VerticalAlign.Top)
            }
          }, (row: ModelMarketRow) => row.key)
        }
        .cachedCount(1)
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
      .height(Math.max(1, Math.min(this.availableWidth < 600 ? 640 : 800,
        this.availableHeight * (this.availableWidth < 600 ? 0.78 : 0.85))))
      .padding({ top: 12, bottom: 12, left: 12, right: 12 })
      .id('model-market-panel')
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
      .shadow({
        radius: 24,
        color: $r('app.color.scrim_gallery'),
        offsetX: 0,
        offsetY: 10
      })
    }
    .width('100%')
    .height('100%')
    .transition(dialogFade())
  }
}
