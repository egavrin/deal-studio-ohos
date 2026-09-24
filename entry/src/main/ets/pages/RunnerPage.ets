import router from '@ohos.router'
import { VeraPreview } from '../components/VeraPreview'
import { store } from '../vera/ProjectStore'
import { consent } from '../vera/VeraConsentStore'

@Entry
@Component
struct RunnerPage {
  @State vbc2: string = ''
  @State error: string = ''
  // projectId and versionId were already being passed here and ignored; they are
  // what lets a program opened from the library remember its state.
  @State persistKey: string = ''

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, string>
    if (params === null || params === undefined) { this.error = 'No parameters'; return }
    let vbc2 = params['vbc2'] || ''
    if (vbc2.length === 0) { this.error = 'No VBC2 bytecode'; return }
    this.vbc2 = vbc2
    let projectId = params['projectId'] || ''
    let versionId = params['versionId'] || ''
    if (projectId.length > 0 && versionId.length > 0) {
      this.persistKey = projectId + '/' + versionId
      store.init(getContext(this).filesDir)
      consent.init(getContext(this).filesDir)
    }
  }

  build() {
    Navigation() {
      Column() {
        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(14)
            .fontColor('#CC0000')
            .padding(16)
            .width('100%')
            .backgroundColor('#FFECEC')
        }
        if (this.vbc2.length > 0) {
          VeraPreview({ vbc2: this.vbc2, persistKey: this.persistKey })
        }
      }.width('100%').height('100%')
    }
    .title('App')
    .titleMode(NavigationTitleMode.Mini)
  }
}
