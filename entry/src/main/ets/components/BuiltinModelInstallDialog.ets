import { ChatViewModel } from '../state/ChatViewModel';
import { formatBytes } from '../models/BuiltinModelDownloadTypes';

@Component
export struct BuiltinModelInstallDialog {
  @ObjectLink viewModel: ChatViewModel;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000099');

      Column({ space: 14 }) {
        Row({ space: 10 }) {
          Image($r('app.media.app_icon'))
            .width(42)
            .height(42)
            .borderRadius(12);
          Column({ space: 2 }) {
            Text('安装内置模型')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F4FBFF');
            Text(`${this.viewModel.builtinModelInstallModelName} · ${this.viewModel.builtinModelInstallSourceName}`)
              .fontSize(12)
              .fontColor('#8DE4C3');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%');

        Text(this.viewModel.builtinModelInstallMessage)
          .fontSize(14)
          .lineHeight(21)
          .fontColor('#B7CDE1')
          .width('100%');

        if (this.viewModel.builtinModelInstallError.length > 0) {
          Text(this.viewModel.builtinModelInstallError)
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#FF9A9A')
            .width('100%');
        }

        Progress({ value: this.viewModel.builtinModelInstallProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color('#45D6A4')
          .style({ strokeWidth: 8, strokeRadius: 4, enableScanEffect: this.viewModel.builtinModelInstalling });

        Row() {
          Text(`${Math.round(this.viewModel.builtinModelInstallProgress)}%`)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .layoutWeight(1);
          Text(`${formatBytes(this.viewModel.builtinModelInstallDownloadedBytes)} / ${formatBytes(this.viewModel.builtinModelInstallTotalBytes)}`)
            .fontSize(12)
            .fontColor('#8CA2B8');
        }
        .width('100%');

        Text(this.viewModel.builtinModelInstallFileName)
          .fontSize(12)
          .fontColor('#6F86A0')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        Row({ space: 10 }) {
          Button(this.viewModel.builtinModelInstalling ? '下载中...' : '下载并安装')
            .height(46)
            .layoutWeight(1)
            .enabled(!this.viewModel.builtinModelInstalling)
            .fontColor('#F7FCFF')
            .backgroundColor('#1466F4')
            .borderRadius(8)
            .onClick(() => {
              this.viewModel.startBuiltinModelInstall();
            });

          Button('稍后')
            .height(46)
            .layoutWeight(1)
            .enabled(!this.viewModel.builtinModelInstalling)
            .fontColor('#B7CDE1')
            .backgroundColor('#132338')
            .borderRadius(8)
            .onClick(() => {
              this.viewModel.closeBuiltinModelInstallDialog();
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
