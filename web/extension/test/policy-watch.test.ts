import { describe, expect, it } from "vitest";

import { PolicyChangeWatcher } from "../src/policy-watch";

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((accept) => {
    resolve = accept;
  });
  return { promise, resolve };
}

describe("PolicyChangeWatcher", () => {
  it("restarts after host recovery without opening duplicate long polls", async () => {
    const first = deferred<boolean>();
    const second = deferred<boolean>();
    let calls = 0;
    const watcher = new PolicyChangeWatcher(() => {
      calls += 1;
      return calls === 1 ? first.promise : second.promise;
    });

    watcher.start();
    watcher.start();
    expect(calls).toBe(1);

    first.resolve(false);
    await first.promise;
    await Promise.resolve();
    expect(watcher.isRunning).toBe(false);

    watcher.start();
    watcher.start();
    expect(calls).toBe(2);
    expect(watcher.isRunning).toBe(true);

    second.resolve(false);
    await second.promise;
  });
});
