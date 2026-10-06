# Fetches the page behind a RecipeImport and records the result on it; the
# waiting page (RecipeImportsController#show) reads it from there.
#
# Runs on its own queue so a worker can be pointed at imports alone, with a
# memory cap: a hostile page can send an endless response header, which
# Net::HTTP buffers without limit until the fetch deadline (SA-12). One import
# per household at a time, so one household cannot occupy every worker thread
# (SA-13). Not retried: a page that failed once is not fetched again unasked.
class RecipeImportJob < ApplicationJob
  queue_as :imports

  limits_concurrency to: 1, key: ->(import) { import.household }

  # The import went away (its household was deleted, or it expired) while it waited.
  discard_on ActiveJob::DeserializationError

  def perform(import)
    return unless import.queued?

    import.start!
    result = RecipeScraper.fetch(import.url)
    result.success? ? import.succeed!(result.recipe) : import.fail!(result.error)
  rescue StandardError
    # A bug, not a bad link. Fail the import so the person is not left waiting,
    # and raise so the bug is not swallowed.
    import.fail!(:failed) if import.running?
    raise
  end
end
