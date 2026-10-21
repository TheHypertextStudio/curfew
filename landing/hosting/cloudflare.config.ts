import { bindings, defineConfig, triggers } from 'cf/config';
import deployment from '../../deployment/generated/environments.mjs';

export default defineConfig((ctx) => {
  switch (ctx.mode) {
    case 'staging': {
      return {
        accountId: '2500680a3b2b0fe6a011c1c25fed5008',
        worker: {
          name: 'curfew-site-staging',
          compatibilityDate: '2026-10-10',
          entrypoint: '../worker.mjs',
          workersDev: false,
          previewUrls: false,
          triggers: [
            triggers.fetch({
              pattern: `${new URL(deployment.staging.siteOrigin).host}/*`,
              zone: new URL(deployment.production.siteOrigin).host,
            }),
            triggers.fetch({
              pattern: `${new URL(deployment.staging.legacySiteOrigin).host}/*`,
              zone: 'hypertext.studio',
            }),
          ],
          assets: {
            htmlHandling: 'auto-trailing-slash',
            notFoundHandling: '404-page',
            runWorkerFirst: true,
          },
          env: {
            ACCOUNT_PORTAL: bindings.text(deployment.staging.accountPortal),
            STAGING_ACCOUNT_SERVICE: bindings.worker({ worker: 'curfew-account-platform-staging' }),
            DOCS_MODE: bindings.text('mintlify'),
            DOCS_UPSTREAM: bindings.text('https://curfew.mintlify.site'),
            ASSETS: bindings.assets(),
          },
        },
      };
    }
    case 'production': {
      return {
        accountId: '2500680a3b2b0fe6a011c1c25fed5008',
        worker: {
          name: 'curfew-site-production',
          compatibilityDate: '2026-10-10',
          entrypoint: '../worker.mjs',
          workersDev: false,
          previewUrls: false,
          assets: {
            htmlHandling: 'auto-trailing-slash',
            notFoundHandling: '404-page',
            runWorkerFirst: true,
          },
          env: {
            ACCOUNT_PORTAL: bindings.text(deployment.production.accountPortal),
            DOCS_MODE: bindings.text('mintlify'),
            DOCS_UPSTREAM: bindings.text('https://curfew.mintlify.site'),
            ASSETS: bindings.assets(),
          },
        },
      };
    }
    case 'local':
    default: {
      return {
        accountId: '2500680a3b2b0fe6a011c1c25fed5008',
        worker: {
          name: 'curfew-site-local',
          workersDev: false,
          previewUrls: false,
          compatibilityDate: '2026-10-10',
          entrypoint: '../worker.mjs',
          assets: {
            htmlHandling: 'auto-trailing-slash',
            notFoundHandling: '404-page',
            runWorkerFirst: true,
          },
          env: {
            DOCS_MODE: bindings.text('html-guide'),
            ASSETS: bindings.assets(),
          },
        },
      };
    }
  }
});
