/** Runtime bindings. Secrets are uploaded separately and never committed. */
export interface Env extends Partial<Omit<LicenseWorkerBindings, 'LICENSE_KV'>> {
  CONFIGURATION_SHA256?: string;
  CONFIGURATION_COMMIT?: string;
  LICENSE_ORIGIN?: string;
  RETIRED_LICENSE_HOSTS?: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string;
  LICENSE_KV: LicenseStore;
  LICENSE_DB?: D1Database;
}

export interface LicenseStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
  list(options?: {
    prefix?: string;
    limit?: number;
  }): Promise<{ keys: Array<{ name: string }>; list_complete: boolean }>;
}

export type LicenseRequest = Pick<Request, 'url' | 'method' | 'headers' | 'body'>;
