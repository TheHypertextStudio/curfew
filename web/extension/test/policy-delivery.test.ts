import { describe, expect, it } from 'vitest';
import { BrowserPolicyController, type BrowserControllerDependencies } from '../src/controller';
import type { BrowserPolicySnapshot } from '../src/protocol';

const at = new Date('2026-09-08T18:00:00.000Z');
const policy: BrowserPolicySnapshot = {
  schemaVersion: 'browser-policy/1',
  sessionID: '334838bd-3160-4a2f-bb28-8b2d61a32f37',
  task: { id: 'task-1', title: 'Finish client work' },
  tracking: 'running',
  scopes: [{ kind: 'origin', origin: 'https://docket.example' }],
  grants: [],
  breakEndsAt: null,
  connectionIsHealthy: true,
  generatedAt: at.toISOString(),
};
const navigation = {
  tabId: 14,
  frameId: 0,
  error: 'net::ERR_BLOCKED_BY_CLIENT',
  url: 'https://research.example/notes',
};

function barrier() {
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((resolve) => {
    enter = resolve;
  });
  const pending = new Promise<void>((resolve) => {
    release = resolve;
  });
  return {
    entered,
    release,
    hold: async () => {
      enter();
      await pending;
    },
  };
}

function harness() {
  const data: Record<string, unknown> = {};
  const tabUpdates: Array<{ tabId: number; url: string }> = [];
  const delivery = barrier(),
    routeSchedule = barrier(),
    policyWrite = barrier();
  const control = { holdFinalDelivery: false, holdRouteSchedule: false, holdPolicyWrite: false };
  let policyReads = 0;
  const dependencies: BrowserControllerDependencies = {
    storage: {
      async get(keys) {
        const names = keys === null ? Object.keys(data) : typeof keys === 'string' ? [keys] : keys;
        // Capture Chrome's response data before delaying promise delivery.
        const snapshot = structuredClone(
          Object.fromEntries(names.filter((key) => key in data).map((key) => [key, data[key]])),
        );
        if (keys === 'browserPolicy' && ++policyReads === 2 && control.holdFinalDelivery) {
          await delivery.hold();
        }
        return snapshot;
      },
      async set(items) {
        if (items.browserPolicyTransition === true && control.holdPolicyWrite) {
          control.holdPolicyWrite = false;
          await policyWrite.hold();
        }
        Object.assign(data, structuredClone(items));
      },
      async remove(keys) {
        for (const key of typeof keys === 'string' ? [keys] : keys) delete data[key];
      },
    },
    dynamicRules: {
      get: async () => [],
      replace: async () => {},
      isRegexSupported: async () => ({ isSupported: true }),
    },
    tabs: {
      update: async (tabId, update) => {
        tabUpdates.push({ tabId, url: update.url });
      },
    },
    native: {
      send: async () => {
        throw new Error('No native call expected');
      },
    },
    expiry: {
      schedule: async () => {
        if (control.holdRouteSchedule) {
          control.holdRouteSchedule = false;
          await routeSchedule.hold();
        }
      },
    },
    refresh: { scheduleRecurring: async () => {} },
    extensionURL: (path) => `chrome-extension://extension-id/${path}`,
    now: () => new Date(at),
    randomID: () => 'review-request',
    nativeHostName: 'studio.hypertext.curfew.dev.browser',
  };
  return {
    controller: new BrowserPolicyController(dependencies),
    data,
    tabUpdates,
    control,
    delivery,
    routeSchedule,
    policyWrite,
  };
}

describe('pending navigation policy delivery', () => {
  it.each(['session ended', 'destination allowed'])(
    'rejects a captured old policy delivered after %s',
    async (change) => {
      const test = harness();
      await test.controller.cachePolicy(policy);
      test.control.holdFinalDelivery = true;
      const routing = test.controller.handleNavigationError(navigation);
      await test.delivery.entered;
      await test.controller.cachePolicy(
        change === 'session ended'
          ? null
          : {
              ...policy,
              scopes: [{ kind: 'origin', origin: 'https://research.example' }],
            },
      );
      test.delivery.release();
      await routing;
      expect(test.tabUpdates).toEqual([]);
      expect(test.data['browserRequest:review-request']).toBeUndefined();
    },
  );

  it('does not route from old storage while a policy update has started', async () => {
    const test = harness();
    await test.controller.cachePolicy(policy);
    test.control.holdRouteSchedule = true;
    const routing = test.controller.handleNavigationError(navigation);
    await test.routeSchedule.entered;
    test.control.holdPolicyWrite = true;
    const changing = test.controller.cachePolicy(null);
    await test.policyWrite.entered;
    test.routeSchedule.release();
    await routing;
    test.policyWrite.release();
    await changing;
    expect(test.tabUpdates).toEqual([]);
    expect(test.data['browserRequest:review-request']).toBeUndefined();
  });
});
