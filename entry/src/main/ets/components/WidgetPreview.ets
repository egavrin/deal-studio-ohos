import { WidgetSession, LiveFrame, CardNode } from '../vera/VeraLiveWidget'
import { app } from './AppStyle'

/** A 2x2 home-screen card on this phone, in vp: the size the widget is written for. */
const CARD_SIDE: number = 172

/**
 * The program's widget(state) as the home-screen card will draw it: the same session (VeraLiveWidget) and the same
 * layout as LiveCard, over the state the app preview holds. Taps run the handlers here only; nothing is saved.
 */
@Component
export struct WidgetPreview {
  @Prop @Watch('restart') vbc2: string = ''
  @Prop @Watch('restart') seedState: string = ''
  @Prop title: string = 'App'
  @State frame: LiveFrame = new LiveFrame()
  @State error: string = ''
  private session: WidgetSession | null = null

  aboutToAppear(): void {
    this.restart()
  }

  /** A new program or a new state: draw it from the start. A state the program cannot draw falls back to init. */
  restart(): void {
    this.error = ''
    this.session = null
    this.frame = new LiveFrame()
    if (this.vbc2.length === 0) { return }
    let seeds = this.seedState.length > 0 ? [this.seedState, ''] : ['']
    for (let seed of seeds) {
      try {
        let session = new WidgetSession(this.vbc2, 'preview', seed)
        this.frame = session.frame('', this.title, '')
        this.session = session
        return
      } catch (e) {
        this.error = (e as Error).message
      }
    }
  }

  private tap(node: CardNode): void {
    if (this.session === null) { return }
    try {
      this.session.tap(this.frame, this.frame.token, node.action, node.value)
      this.frame = this.session.frame('', this.title, '')
      this.error = ''
    } catch (e) {
      this.error = (e as Error).message
    }
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Row() {
          Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#475569')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          Text('↗').fontSize(18).fontColor('#2563EB').padding(6)
        }.width('100%')
        if (this.frame.live) {
          ForEach(this.frame.nodes, (node: CardNode) => { this.level1(node) }, (node: CardNode) => node.key + this.frame.token)
        }
      }
      .width(CARD_SIDE)
      .height(CARD_SIDE)
      .padding(12)
      .backgroundColor(this.frame.background)
      .borderRadius(20)
      .clip(true)
      .shadow({ radius: 8, color: '#26000000', offsetY: 2 })

      Text(this.note())
        .fontSize(12).fontColor(this.error.length > 0 ? app.warningInk : app.inkMuted)
        .textAlign(TextAlign.Center).constraintSize({ maxWidth: 300 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(app.background)
  }

  private note(): string {
    if (this.error.length > 0) { return this.error }
    if (!this.frame.live) { return 'No widget yet. Say below what it should show.' }
    return 'The home-screen card, over the data in the preview. Taps here are not saved.'
  }

  @Builder
  leaf(node: CardNode) {
    if (node.kind === 'button') {
      Button(node.text).type(ButtonType.Normal).borderRadius(10).height(40)
        .backgroundColor(node.fill).fontColor(node.color).fontSize(14)
        .enabled(node.enabled).onClick(() => { this.tap(node) })
    } else if (node.kind === 'divider') {
      Divider().color('#CBD5E1')
    } else if (node.kind === 'spacer') {
      Blank().height(4)
    } else {
      Text(node.text).fontSize(node.size).fontColor(node.color).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  level1(node: CardNode) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child) }, (child: CardNode) => child.key)
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level2(child) }, (child: CardNode) => child.key)
      }.width('100%')
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level2(node: CardNode) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child) }, (child: CardNode) => child.key)
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level3(child) }, (child: CardNode) => child.key)
      }.width('100%')
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level3(node: CardNode) {
    if (node.kind === 'row') {
      Row({ space: 8 }) {
        ForEach(node.children, (child: CardNode) => { this.leaf(child) }, (child: CardNode) => child.key)
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.leaf(child) }, (child: CardNode) => child.key)
      }.width('100%')
    } else {
      this.leaf(node)
    }
  }
}
