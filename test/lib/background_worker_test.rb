require "test_helper"

# Recipe imports run in a memory-limited worker, in both editions (SA-12): a
# hostile page can send endless response headers, which Net::HTTP buffers
# without limit until the fetch deadline, so the process that fetches must be
# one a memory cap can kill without taking the web server with it. These read
# the real config files; the hosted Kamal role is checked in
# saas/test/lib/kamal_destinations_test.rb.
class BackgroundWorkerTest < ActiveSupport::TestCase
  COMPOSE_FILE = Rails.root.join("docker-compose.yml")
  QUEUE_FILE = Rails.root.join("config/queue.yml")
  RECURRING_FILE = Rails.root.join("config/recurring.yml")

  test "the appliance compose file runs the jobs in their own capped container" do
    web, worker = compose.values_at("familyplates", "worker")

    assert worker, "docker-compose.yml needs a worker service"
    assert_equal web["image"], worker["image"], "same image, so the same code and edition"
    assert_equal [ "./bin/jobs" ], Array(worker["command"])
    assert_equal "unless-stopped", worker["restart"]
    assert_equal "512m", worker["mem_limit"]
    assert_equal worker["mem_limit"], worker["memswap_limit"], "no swap, or a runaway fetch swaps instead of being stopped"
    assert_nil worker["ports"], "nothing connects to the worker"
  end

  test "the worker shares the web container's databases and settings" do
    web, worker = compose.values_at("familyplates", "worker")

    assert_equal [ "familyplates_data:/rails/storage" ], web["volumes"]
    assert_equal web["volumes"], worker["volumes"]
    assert_equal web["environment"], worker["environment"]
  end

  test "the worker starts only once the web container has prepared the databases" do
    web, worker = compose.values_at("familyplates", "worker")

    # The entrypoint's db:prepare runs only for `rails server`, so the worker
    # never prepares a database and the two cannot race; it waits for web.
    assert_equal({ "familyplates" => { "condition" => "service_healthy" } }, worker["depends_on"])
    assert web["healthcheck"], "the web container needs a health check to wait for"
    assert_includes Array(web["healthcheck"]["test"]).join(" "), "/up"
  end

  test "exactly one container runs jobs, and the web server does not" do
    job_runners = compose.select { |_name, service| Array(service["command"]).join(" ").include?("bin/jobs") }

    assert_equal [ "worker" ], job_runners.keys
    assert_no_match(/SOLID_QUEUE_IN_PUMA/, Array(compose["familyplates"]["environment"]).join("\n"))
  end

  test "one dispatcher and one worker definition, and the worker takes the imports queue once" do
    config = YAML.safe_load(ERB.new(QUEUE_FILE.read).result, aliases: true).fetch("production")
    workers = Array(config["workers"])
    queue_lists = workers.map { |worker| Array(worker["queues"]).flat_map { |queues| queues.to_s.split(",").map(&:strip) } }

    assert_equal 1, Array(config["dispatchers"]).size
    assert_equal 1, workers.size
    # "*" is every queue, imports included; naming it as well would run it twice.
    assert_equal 1, queue_lists.count { |queues| queues.include?("*") || queues.include?("imports") }
    assert_equal 1, queue_lists.flatten.size, "a single queue list, not a * plus names"
    assert_equal "imports", RecipeImportJob.queue_name
  end

  test "the scheduler runs the recurring tasks, including the import cleanup, from the one supervisor" do
    tasks = YAML.safe_load(ERB.new(RECURRING_FILE.read).result, aliases: true).fetch("production")

    assert_includes tasks.dig("clear_recipe_imports", "command"), "RecipeImport.expired"
    # Solid Queue starts the scheduler inside `bin/jobs` unless told to skip it,
    # so a second supervisor (Puma's plugin) would schedule every task twice.
    assert_no_match(/skip_recurring|only_recurring|only_work|only_dispatch/i, QUEUE_FILE.read)
  end

  private

  def compose
    @compose ||= YAML.safe_load(COMPOSE_FILE.read, aliases: true).fetch("services")
  end
end
