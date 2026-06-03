import { ChatViewModel } from '../state/ChatViewModel';

@Component
export struct DeleteImportedModelDialog {
  @ObjectLink viewModel: ChatViewModel;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000099');

      Column({ space: 14 }) {
        Text('删除导入模型')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
          .width('100%');

        Text('删除后会移除该模型在 App 沙箱中的文件，当前对话不会被删除。')
          .fontSize(14)
          .lineHeight(21)
          .fontColor('#B7CDE1')
          .width('100%');

        Row({ space: 10 }) {
          Button('取消')
            .height(38)
            .layoutWeight(1)
            .onClick(() => {
              this.viewModel.cancelDeleteImportedModel();
            });
          Button('删除')
            .height(38)
            .layoutWeight(1)
            .backgroundColor('#B43B3B')
            .onClick(() => {
              this.viewModel.confirmDeleteImportedModel();
            });
        }
        .width('100%');
      }
      .width('86%')
      .padding(18)
      .backgroundColor('#0D1A28')
      .borderRadius(10);
    }
    .width('100%')
    .height('100%');
  }
}
