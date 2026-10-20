# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "open3"
require "tempfile"

class ReleaseWorkflowTest < Minitest::Test
  WORKFLOW = YAML.load_file(File.expand_path("../../.github/workflows/release-trains.yml", __dir__))

  def test_missing_credentials_fail_instead_of_reporting_a_successful_ship
    step = WORKFLOW.fetch("jobs").fetch("ship").fetch("steps").find do |row|
      row.fetch("run", "").include?("has_api_key_json=false")
    end
    env = step.fetch("env").transform_values { "" }
    _out, _err, status = Open3.capture3(env, "bash", "-c", step.fetch("run"))
    refute status.success?, "A ship run with no credentials must fail, without emitting a receipt"
  end

  def resolve(channel:, ref: "main", event: "workflow_dispatch")
    step = WORKFLOW.fetch("jobs").fetch("resolve").fetch("steps").first
    Tempfile.create("release-resolve") do |file|
      env = {"EVENT_NAME" => event, "REQUESTED_CHANNEL" => channel,
             "WORKFLOW_REF_NAME" => ref, "GITHUB_OUTPUT" => file.path}
      out, err, status = Open3.capture3(env, "bash", "-c", step.fetch("run"))
      return [File.read(file.path), status, out + err]
    end
  end

  def test_schedule_selects_nightly_without_a_clock_window
    output, status, = resolve(channel: "", event: "schedule")
    assert status.success?
    assert_includes output, "branch=nightly\n"
    assert_includes output, "channel=nightly\n"
  end

  def test_weekly_dispatch_cannot_ship_an_arbitrary_feature_branch
    _output, status, = resolve(channel: "weekly", ref: "feature/unaccepted")
    refute status.success?
  end

  def test_weekly_dispatch_selects_weekly
    output, status, = resolve(channel: "weekly", ref: "weekly")
    assert status.success?
    assert_includes output, "branch=weekly\n"
  end

  def test_weekly_dispatch_uses_default_controller_and_weekly_payload
    output, status, = resolve(channel: "weekly", ref: "main")
    assert status.success?
    assert_includes output, "branch=weekly\n"
  end

  def test_macos_delivery_waits_for_the_input_comparison
    ship = WORKFLOW.fetch("jobs").fetch("ship")
    assert_includes Array(ship.fetch("needs")), "changes",
                    "The default-branch controller must run the delivery guard before allocating macOS"
  end
end
