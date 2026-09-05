# frozen_string_literal: true

require "test_helper"
require "rake"

class ScaleValidationTaskTest < ActiveSupport::TestCase
  setup do
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/scale_validation.rake")
  end

  test "scale:validate task is defined" do
    assert Rake::Task.task_defined?("scale:validate")
  end
end
