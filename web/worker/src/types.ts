/** Runtime bindings. Secrets are uploaded separately and never committed. */
export interface Env extends Partial<Omit<LicenseWorkerBindings, "LICENSE_KV">> {
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string;
  LICENSE_KV: KVNamespace;
}
