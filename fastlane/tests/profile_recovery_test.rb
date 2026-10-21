# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

require_relative "support/signing_lane_harness"

class ProfileRecoveryTest < Minitest::Test
  def setup
    @environment = ENV.to_h
    ENV["CI"] = "true"
    @runner = SigningLaneHarness.new
  end

  def teardown
    ENV.replace(@environment)
  end

  def run_lane(repair: false)
    error = nil
    original = SigningProfiles.method(:verify!)
    SigningProfiles.define_singleton_method(:verify!) { |**_| }
    begin
      @runner.run(repair_profiles: repair)
    rescue StandardError => caught
      error = caught
    ensure
      SigningProfiles.define_singleton_method(:verify!, original)
    end
    assert_nil error, "Signing must work with the existing read-only Match key: #{error}"
  end

  def test_repair_renews_only_watch_profiles_without_writing_to_match
    run_lane(repair: true)
    renewed = @runner.profile_requests.select { |row| row[:force] }.map { |row| row[:app_identifier] }
    assert_equal ["com.danfakkeldy.macromark.watchkitapp",
                  "com.danfakkeldy.macromark.watchkitapp.MacroMarkWidget"], renewed
    assert @runner.profile_requests.reject { |row| row[:force] }.all? { |row| row[:readonly] }
    assert @runner.profile_requests.select { |row| row[:force] }.none? { |row| row.key?(:readonly) }
  end

  def test_normal_runs_fetch_current_profiles_read_only
    run_lane
    assert_equal 3, @runner.profile_requests.length
    assert @runner.profile_requests.all? { |row| row[:readonly] && !row[:force] }
    assert @runner.profile_requests.none? { |row| row.key?(:force) }
  end

  def test_downloaded_profile_replaces_stale_match_path_and_name
    Dir.mktmpdir do |directory|
      ENV["RUNNER_TEMP"] = directory
      run_lane
      identifier = "com.danfakkeldy.macromark.watchkitapp"
      assert_equal File.join(directory, "macromark-profiles", "#{identifier}.mobileprovision"),
                   ENV["sigh_#{identifier}_appstore_profile-path"]
      assert_equal "current #{identifier}", ENV["sigh_#{identifier}_appstore_profile-name"]
    end
  end

  def test_export_uses_the_downloaded_profile_uuid
    run_lane
    identifier = "com.danfakkeldy.macromark.watchkitapp"
    assert_equal "current-uuid-#{identifier}", @runner.app_store_profile_mapping.fetch(identifier)
  end
end
