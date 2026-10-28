# frozen_string_literal: true

# Run with bundle exec. This validates the real pinned Fastlane schema without
# contacting Apple, accessing a keychain, or generating a profile.
require "fastlane"
require "sigh"
require_relative "support/signing_lane_harness"

raise "Signing mode builder is missing" unless SigningProfiles.respond_to?(:provisioning_mode)

validator = lambda do |options|
  config = FastlaneCore::Configuration.create(Sigh::Options.available_options, options)
  raise "Wrong provisioning mode" unless config[:readonly] != config[:force]
end

original = SigningProfiles.method(:verify!)
SigningProfiles.define_singleton_method(:verify!) { |**_| }
begin
  [false, true].each do |repair|
    runner = SigningLaneHarness.new(option_validator: validator)
    runner.run(repair_profiles: repair)
    raise "Expected all three profiles" unless runner.profile_requests.length == 3
  end
ensure
  SigningProfiles.define_singleton_method(:verify!, original)
end

puts "Normal and repair signing lanes passed Fastlane's real option validation"
