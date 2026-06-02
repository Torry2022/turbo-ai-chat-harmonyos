import { ChatViewModel } from '../state/ChatViewModel';

@Component
export struct AppHeader {
  @ObjectLink viewModel: ChatViewModel;
  @Prop renderVersion: number;
  onNewChat: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Image($r('app.media.app_icon'))
        .width(38)
        .height(38)
        .borderRadius(10);
      Column({ space: 2 }) {
        Text('Turbo AI Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF');
        Text(this.viewModel.status)
          .fontSize(12)
          .fontColor(this.viewModel.loaded ? '#45D6A4' : '#F2B35D')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Button('新对话')
        .enabled(!this.viewModel.busy)
        .height(34)
        .onClick(() => {
          this.onNewChat();
        });
    }
    .width('100%')
    .height(50);
  }
}
