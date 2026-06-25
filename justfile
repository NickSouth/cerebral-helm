bootstrap:
  node ./scripts/bootstrap.mjs

check-toolchain:
  node ./scripts/check-toolchain.mjs

validate-config:
  node ./scripts/validate-config.mjs

db-reset:
  node ./scripts/db-reset.mjs

dashboard-dev:
  node ./scripts/dashboard-dev.mjs

simulate fixture="successful-developer-mode":
  node ./scripts/simulate.mjs {{fixture}}

events-tail lines="20":
  node ./scripts/events-tail.mjs {{lines}}

test:
  node ./scripts/test.mjs
