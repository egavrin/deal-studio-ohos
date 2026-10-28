import { store } from '../vera/ProjectStore'
import { versionCountText } from '../vera/ProjectText'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { projectIconResource } from '../vera/ProjectIcons'
import { app, DangerButton } from '../components/AppStyle'
import { ProjectNavParams, ProjectRow, RowSource, loadProjectRows, confirmDeleteProject, tileTint } from '../components/ProjectRows'
import { refreshForms } from '../vera/FormUpdater'
import { compileVeraSource } from '../vera/VeraCompiler'
import { loadRawfileText } from '../vera/LlamaEngine'

/** Every app made so far, one row each. Swipe or long press to delete. */
@Entry
@Component
struct AppsPage {
  @State projects: ProjectRow[] = []
  private source: RowSource = new RowSource()

  aboutToAppear(): void {
    let context = this.getUIContext().getHostContext()
    if (context === undefined) { throw new Error('Project library host context is unavailable') }
    store.init(context.filesDir)
    this.reload()
  }

  onPageShow(): void {
    this.reload()
  }

  private reload(): void {
    this.projects = loadProjectRows()
    this.source.replace(this.projects)
  }

  build() {
    Navigation() {
      List({ space: 12 }) {
        LazyForEach(this.source, (row: ProjectRow) => {
          ListItem() {
            this.projectRow(row)
          }
          .swipeAction({
            end: {
              builder: () => { this.deleteAction(row.project.id) }
            }
          })
        // Keyed by what a row shows, so a rename, a new picture or a saved version redraws it.
        }, (row: ProjectRow) => row.project.id + '|' + row.project.name + '|' + row.project.icon + '|' +
          row.summary.versions.toString() + '|' + row.summary.updatedAt.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .scrollBar(BarState.Off)
    }
    .title('My apps (' + this.projects.length.toString() + ')')
    .titleMode(NavigationTitleMode.Mini)
    .backgroundColor(app.background)
    .menus([{
      value: 'Widget example',
      action: () => { this.createWidgetExample() }
    }])
  }

  /** An explicit, separate fixture: never rewrites an existing generated program. */
  private async createWidgetExample(): Promise<void> {
    try {
      let context = this.getUIContext().getHostContext()
      if (context === undefined) { return }
      let source = await loadRawfileText(context.resourceManager, 'widget-counter.vera')
      let compiled = compileVeraSource(source)
      let project = store.createProject('Widget counter', '🔢')
      store.createVersion(project.id, source, compiled.vbc2, 'Live widget counter example')
      this.reload()
      refreshForms()
      let nav = new ProjectNavParams()
      nav.projectId = project.id
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/ProjectPage', params: nav })
    } catch (e) { console.error('Widget example failed: ' + (e as Error).message) }
  }

  /** One project: its icon, what it is (the request it began as), how much work is in it, and when it was last worked on. */
  @Builder
  projectRow(row: ProjectRow) {
    Column() {
      Row() {
        Image(projectIconResource(row.project.icon)).objectFit(ImageFit.Contain)
          .width(48).height(48).padding(10).borderRadius(14).backgroundColor(tileTint(row.project.id))
          .margin({ right: 14 })
        Column({ space: 2 }) {
          Text(row.project.name).fontSize(17).fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.summary.request.length > 0) {
            Text(row.summary.request).fontSize(13).fontColor(app.inkSoft).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(versionCountText(row.summary.versions) + ' · ' + new Date(row.summary.updatedAt).toLocaleDateString())
            .fontSize(12).fontColor(app.inkMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(18).fontColor([app.inkDisabled])
      }
      .width('100%')
      .padding(14)
    }
    .width('100%')
    .backgroundColor(app.surface)
    .borderRadius(12)
    .clip(true)
    .shadow({ radius: 2, color: '#10000000', offsetY: 1 })
    .onClick(() => {
      let nav = new ProjectNavParams()
      nav.projectId = row.project.id
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ProjectPage', params: nav })
        .catch((e: Error): void => { console.error('Navigate to project failed: ' + e.message) })
    })
    .bindContextMenu(this.rowMenu(row.project.id), ResponseType.LongPress)
  }

  @Builder
  rowMenu(id: string) {
    Menu() {
      MenuItem({ content: 'Delete project', symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')) })
        .onClick(() => { confirmDeleteProject(this.getUIContext(), id, (deleted: boolean): void => { this.reload() }) })
    }
  }

  @Builder
  deleteAction(id: string) {
    Row() {
      Button('Delete')
        .attributeModifier(new DangerButton())
        .height('100%')
        .onClick(() => { confirmDeleteProject(this.getUIContext(), id, (deleted: boolean): void => { this.reload() }) })
    }.height('100%').padding({ left: 8 })
  }
}
