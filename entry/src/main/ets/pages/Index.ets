import { common } from '@kit.AbilityKit';
import { AppHeader } from '../components/AppHeader';
import { BottomTabs } from '../components/BottomTabs';
import { ChatTab } from '../components/ChatTab';
import { LaunchScreen } from '../components/LaunchScreen';
import { ModelLoadDialog } from '../components/ModelLoadDialog';
import { ModelTab } from '../components/ModelTab';
import { MonitorTab } from '../components/MonitorTab';
import { ChatViewModel } from '../state/ChatViewModel';

@Entry
@Component
struct Index {
  @State private viewModel: ChatViewModel = new ChatViewModel();
  @State private showLaunch: boolean = true;
  @State private activeTab: number = 0;
  @State private stateVersion: number = 0;
  private monitorTimer: number = -1;

  aboutToAppear(): void {
    this.viewModel.bindNotify(() => {
      this.stateVersion++;
    });
    const context = getContext(this) as common.UIAbilityContext;
    this.viewModel.initialize(context);
    setTimeout(() => {
      this.showLaunch = false;
      if (!this.viewModel.loaded) {
        this.viewModel.openModelLoadDialog(true);
      }
    }, 1200);
    this.monitorTimer = setInterval(() => {
      this.viewModel.refreshStats();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.monitorTimer >= 0) {
      clearInterval(this.monitorTimer);
      this.monitorTimer = -1;
    }
    this.viewModel.dispose();
  }

  private changeTab(index: number): void {
    this.activeTab = index;
    if (index === 0) {
      this.viewModel.scrollToBottom();
    }
  }

  private newChat(): void {
    this.viewModel.newChat();
    this.activeTab = 0;
  }

  @Builder
  private MainScreen() {
    Stack() {
      Column({ space: 10 }) {
        AppHeader({
          viewModel: this.viewModel,
          renderVersion: this.stateVersion,
          onNewChat: () => {
            this.newChat();
          }
        });
        if (this.activeTab === 0) {
          ChatTab({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion
          });
        } else if (this.activeTab === 1) {
          ModelTab({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion
          });
        } else {
          MonitorTab({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion
          });
        }
        BottomTabs({
          activeTab: this.activeTab,
          renderVersion: this.stateVersion,
          onTabChange: (index: number) => {
            this.changeTab(index);
          }
        });
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, top: 42, bottom: 12 });

      if (this.viewModel.showModelLoadDialog) {
        ModelLoadDialog({
          viewModel: this.viewModel,
          renderVersion: this.stateVersion
        });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]);
  }

  build() {
    Stack() {
      if (this.showLaunch) {
        LaunchScreen();
      } else {
        this.MainScreen();
      }
    }
    .width('100%')
    .height('100%');
  }
}
