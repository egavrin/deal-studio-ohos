// The launcher only consumes binding DTOs. No VM, filesystem, or app imports here.
let liveStorage = new LocalStorage()

class CardNode {
  key: string = ''
  kind: string = ''
  text: string = ''
  action: string = ''
  value: number = 0
  enabled: boolean = true
  color: string = '#172033'
  fill: string = '#FFFFFF'
  size: number = 14
  children: CardNode[] = []
}

@Entry(liveStorage)
@Component
struct LiveCard {
  @LocalStorageProp('formId') formId: string = ''
  @LocalStorageProp('projectId') projectId: string = ''
  @LocalStorageProp('title') title: string = 'VERA app'
  @LocalStorageProp('icon') icon: string = '📱'
  @LocalStorageProp('token') token: string = ''
  @LocalStorageProp('status') status: string = ''
  @LocalStorageProp('live') live: boolean = false
  @LocalStorageProp('background') cardBackground: string = '#F8FAFC'
  @LocalStorageProp('nodes') nodes: CardNode[] = []

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#475569')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text('↗').fontSize(18).fontColor('#2563EB').padding(6)
      }.width('100%').onClick(() => {
        postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { projectId: this.projectId, veraRun: '1', veraFormId: this.projectId.length === 0 ? this.formId : '' } })
      })
      if (this.live) {
        ForEach(this.nodes, (node: CardNode) => { this.level1(node) }, (node: CardNode) => node.key + this.token)
      } else {
        Text(this.icon).fontSize(32)
      }
      if (this.status.length > 0) {
        Text(this.status).fontSize(11).fontColor('#64748B').maxLines(2)
      }
    }.width('100%').height('100%').padding(12).backgroundColor(this.cardBackground)
  }

  @Builder
  leaf(node: CardNode) {
    if (node.kind === 'button') {
      Button(node.text).type(ButtonType.Normal).borderRadius(10).height(40)
        .backgroundColor(node.fill).fontColor(node.color).fontSize(14)
        .enabled(node.enabled).onClick(() => {
          postCardAction(this, { action: 'message', params: { token: this.token, handler: node.action, value: node.value } })
        })
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
        ForEach(node.children, (child: CardNode) => { this.level4(child) }, (child: CardNode) => child.key)
      }.width('100%').justifyContent(FlexAlign.SpaceEvenly)
    } else if (node.kind === 'column') {
      Column({ space: 6 }) {
        ForEach(node.children, (child: CardNode) => { this.level4(child) }, (child: CardNode) => child.key)
      }.width('100%')
    } else {
      this.leaf(node)
    }
  }

  @Builder
  level4(node: CardNode) {
    this.leaf(node)
  }
}
