# V76 canary runner mode

The canonical production canary runner is `scripts/test-production-canary-v76.mjs` and must remain the uninstrumented physical E2E journey.

Heavy runtime instrumentation is retained separately in `scripts/test-production-canary-v76-diagnostic.mjs` and must only be enabled deliberately for diagnostics. It replaces browser timing/observer primitives and therefore must not be used as evidence of normal WebKit timing without an uninstrumented control run.

The preserved `scripts/test-production-canary-v76-functional.mjs` remains a byte-identical reference for the restored functional runner at this stage of V76.
