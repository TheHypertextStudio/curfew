import { bindings, defineConfig } from 'cf/config';

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
          assets: {
            htmlHandling: 'auto-trailing-slash',
            notFoundHandling: '404-page',
            runWorkerFirst: true,
          },
          env: {
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
            DOCS_MODE: bindings.text('html-guide'),
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
