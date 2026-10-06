# Fetches the page behind a RecipeImport, saves the recipe it finds into the
# household's recipe box and records the result on the import; the waiting page
# (RecipeImportsController#show) reads it from there.
#
# Jobs run on a memory-capped worker (bin/jobs: the `worker` service in
# docker-compose.yml, the `job` role in the Kamal deploy files), never inside Puma,
# because a hostile page can send an endless response header, which Net::HTTP
# buffers without limit until the fetch deadline (SA-12). That one worker runs
# every queue; the `imports` queue name stays so imports can be given a worker of
# their own. One import per household at a time, so one household cannot occupy
# every worker thread (SA-13). Not retried: a page that failed once is not fetched
# again unasked. An import already failed as stalled is not started
# (RecipeImport#claim!).
class RecipeImportJob < ApplicationJob
  queue_as :imports

  limits_concurrency to: 1, key: ->(import) { import.household }

  # The import went away (its household was deleted, or it expired) while it waited.
  discard_on ActiveJob::DeserializationError

  def perform(import)
    return unless import.claim!

    result = RecipeScraper.fetch(import.url)
    result.success? ? import.succeed!(result.recipe) : import.fail!(result.error)
  rescue StandardError
    # A bug, not a bad link. Fail the import so the person is not left waiting,
    # and raise so the bug is not swallowed.
    import.reload # a rolled-back save leaves the status changed in memory only
    import.fail!(:failed) if import.running?
    raise
  end
end
