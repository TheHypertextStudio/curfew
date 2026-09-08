export class PolicyChangeWatcher {
  private task: Promise<void> | undefined;

  constructor(private readonly waitForPolicyChange: () => Promise<boolean>) {}

  get isRunning(): boolean {
    return this.task !== undefined;
  }

  start(): void {
    if (this.task !== undefined) {
      return;
    }
    const task = this.watch();
    this.task = task;
    void task.finally(() => {
      if (this.task === task) {
        this.task = undefined;
      }
    });
  }

  private async watch(): Promise<void> {
    while (await this.waitForPolicyChange()) {
      // A successful bounded wait starts the next wait. A host failure stops
      // this task until the refresh alarm explicitly restarts it.
    }
  }
}
