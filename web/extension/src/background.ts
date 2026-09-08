import { BrowserPolicyController, type NavigationError } from "./controller";
import { nativeHostName } from "./config";
import { PolicyChangeWatcher } from "./policy-watch";
import type { DynamicRule } from "./rules";

const expiryAlarmName = "curfew-policy-expiry";
const refreshAlarmName = "curfew-policy-refresh";

interface ChromeAPI {
  storage: {
    local: {
      get(keys: string | string[] | null): Promise<Record<string, unknown>>;
      set(items: Record<string, unknown>): Promise<void>;
      remove(keys: string | string[]): Promise<void>;
    };
  };
  declarativeNetRequest: {
    getDynamicRules(): Promise<Array<{ id: number }>>;
    isRegexSupported(options: {
      regex: string;
      isCaseSensitive: boolean;
    }): Promise<{ isSupported: boolean }>;
    updateDynamicRules(update: {
      removeRuleIds: number[];
      addRules: DynamicRule[];
    }): Promise<void>;
  };
  tabs: {
    update(tabId: number, update: { url: string }): Promise<unknown>;
    onUpdated: {
      addListener(listener: (tabId: number, changeInfo: { url?: string }) => void): void;
    };
    onRemoved: {
      addListener(listener: (tabId: number) => void): void;
    };
  };
  runtime: {
    getURL(path: string): string;
    sendNativeMessage(hostName: string, request: Record<string, unknown>): Promise<unknown>;
    onMessage: {
      addListener(listener: (
        message: unknown,
        sender: unknown,
        sendResponse: (response: unknown) => void,
      ) => boolean): void;
    };
  };
  webNavigation: {
    onErrorOccurred: {
      addListener(listener: (details: NavigationError) => void): void;
    };
  };
  alarms: {
    clear(name: string): Promise<boolean>;
    create(name: string, info: {
      when?: number;
      delayInMinutes?: number;
      periodInMinutes?: number;
    }): Promise<void>;
    onAlarm: {
      addListener(listener: (alarm: { name: string }) => void): void;
    };
  };
}

const chromeAPI = chrome as ChromeAPI;
const controller = new BrowserPolicyController({
  storage: chromeAPI.storage.local,
  dynamicRules: {
    get: () => chromeAPI.declarativeNetRequest.getDynamicRules(),
    replace: (update) => chromeAPI.declarativeNetRequest.updateDynamicRules(update),
    isRegexSupported: (options) =>
      chromeAPI.declarativeNetRequest.isRegexSupported(options),
  },
  tabs: {
    update: async (tabId, update) => {
      await chromeAPI.tabs.update(tabId, update);
    },
  },
  native: {
    send: (hostName, request) => chromeAPI.runtime.sendNativeMessage(hostName, request),
  },
  expiry: {
    schedule: async (date) => {
      await chromeAPI.alarms.clear(expiryAlarmName);
      if (date !== null) {
        await chromeAPI.alarms.create(expiryAlarmName, { when: date.getTime() });
      }
    },
  },
  refresh: {
    scheduleRecurring: async (periodMinutes) => {
      await chromeAPI.alarms.create(refreshAlarmName, {
        delayInMinutes: periodMinutes,
        periodInMinutes: periodMinutes,
      });
    },
  },
  extensionURL: (path) => chromeAPI.runtime.getURL(path),
  now: () => new Date(),
  randomID: () => crypto.randomUUID(),
  nativeHostName,
});
const policyWatcher = new PolicyChangeWatcher(() => controller.waitForPolicyChange());

chromeAPI.webNavigation.onErrorOccurred.addListener((details) => {
  void controller.handleNavigationError(details);
});

chromeAPI.tabs.onRemoved.addListener((tabId) => {
  void controller.handleTabClosed(tabId);
});

chromeAPI.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.url !== undefined) {
    void controller.handleTabURLChanged(tabId, changeInfo.url);
  }
});

chromeAPI.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === expiryAlarmName) {
    void controller.rebuildForExpiry();
  } else if (alarm.name === refreshAlarmName) {
    void controller.refreshPolicy().then(() => policyWatcher.start());
  }
});

chromeAPI.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (typeof message !== "object" || message === null) {
    return false;
  }
  const request = message as Record<string, unknown>;
  if (request.type === "get_blocker_context" && typeof request.requestID === "string") {
    void controller.getBlockerContext(request.requestID).then(sendResponse);
    return true;
  }
  if (request.type === "review_destination" && typeof request.requestID === "string" &&
      (request.justification === undefined || typeof request.justification === "string") &&
      (request.challengeAnswer === undefined || typeof request.challengeAnswer === "string")) {
    void controller.reviewDestination({
      requestID: request.requestID,
      justification: request.justification,
      challengeAnswer: request.challengeAnswer,
    }).then(sendResponse);
    return true;
  }
  return false;
});

void controller.initialize().then(() => policyWatcher.start());
