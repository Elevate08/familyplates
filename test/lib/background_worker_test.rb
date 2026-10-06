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

  test "imports have a worker of their own with one thread, and no other worker takes the queue" do
    workers = queue_config.fetch("workers")
    imports, others = workers.partition { |worker| queue_names(worker) == [ "imports" ] }

    assert_equal 1, Array(queue_config["dispatchers"]).size
    assert_equal 1, imports.size, "exactly one worker for the imports queue"
    assert_equal 1, imports.first["threads"], "one fetch at a time can grow this process"
    assert_equal 1, imports.first["processes"]
    assert_equal 1, others.size
    # "*" is every queue, imports included, so it would run them in the other worker too.
    assert_not_includes queue_names(others.first), "*"
    assert_not_includes queue_names(others.first), "imports"
    assert_equal "imports", RecipeImportJob.queue_name
  end

  test "every job runs on a queue some worker takes" do
    Rails.application.eager_load!
    taken = queue_config.fetch("workers").flat_map { |worker| queue_names(worker) }
    used = ActiveJob::Base.descendants.reject { |job| job.name.nil? || job <= ActionMailer::MailDeliveryJob }
                          .map { |job| job.new.queue_name } + [ ActionMailer::Base.deliver_later_queue_name.presence || ActiveJob::Base.default_queue_name ]

    assert_empty used.uniq - taken, "a job on a queue no worker takes would never run; add the queue to config/queue.yml"
  end

  test "Solid Queue accepts the worker blocks" do
    configuration = SolidQueue::Configuration.new(config_file: QUEUE_FILE, recurring_schedule_file: RECURRING_FILE)
    workers = configuration.configured_processes.select { |process| process.kind == :worker }

    assert configuration.valid?, configuration.errors.full_messages.to_sentence
    assert_equal [ [ "imports" ], %w[default solid_queue_recurring] ], workers.map { |worker| Array(worker.attributes[:queues]).flat_map { |q| q.to_s.split(",").map(&:strip) } }
  end

  test "the scheduler runs the recurring tasks, including the import cleanup, from the one supervisor" do
    tasks = YAML.safe_load(ERB.new(RECURRING_FILE.read).result, aliases: true).fetch("production")

    assert_includes tasks.dig("clear_recipe_imports", "command"), "RecipeImport.expired"
    # Solid Queue starts the scheduler inside `bin/jobs` unless told to skip it,
    # so a second supervisor (Puma's plugin) would schedule every task twice.
    assert_no_match(/skip_recurring|only_recurring|only_work|only_dispatch/i, QUEUE_FILE.read)
  end

  private

  def queue_config
    @queue_config ||= YAML.safe_load(ERB.new(QUEUE_FILE.read).result, aliases: true).fetch("production")
  end

  def queue_names(worker)
    Array(worker["queues"]).flat_map { |queues| queues.to_s.split(",").map(&:strip) }
  end

  def compose
    @compose ||= YAML.safe_load(COMPOSE_FILE.read, aliases: true).fetch("services")
  end
end
