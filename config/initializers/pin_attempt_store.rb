# PIN attempt counters must be shared across Puma workers or the effective limit
# is multiplied by the worker count, so they use the configured cache — which is
# solid_cache in production, and therefore database-backed and shared.
#
# The test environment runs a :null_store, whose #increment always returns nil.
# Rails' rate limiter treats that as "under the limit", which would silently
# disable throttling in exactly the tests written to prove it works, so tests get
# a real in-memory store. test_helper clears it between tests.
Rails.application.config.pin_attempt_store =
  if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    Rails.cache
  end
