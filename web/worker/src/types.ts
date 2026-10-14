/** Runtime bindings. Secrets are uploaded separately and never committed. */
export interface Env {
  LICENSE_ORIGIN?: string;
  RETIRED_LICENSE_HOSTS?: string;
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string;
  LICENSE_KV: KVNamespace;
}
