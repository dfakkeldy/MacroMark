# frozen_string_literal: true

# Run the real signing lane, with only the external Match/Apple actions replaced.
class SigningLaneHarness
  class << self
    attr_accessor :lanes
    def default_platform(*); end
    def skip_docs; end
    def desc(*); end
    def platform(*) = yield
    def before_all; end
    def lane(name, &block) = (@lanes ||= {})[name] = block
    alias private_lane lane
  end

  attr_reader :profile_requests

  def initialize(option_validator: nil)
    @option_validator = option_validator
    @api_key = {key_id: "fixture"}
    @profile_requests = []
  end

  def setup_ci; end

  def match(**options)
    raise "Match storage key is read-only" unless options[:readonly]

    options.fetch(:app_identifier).each do |identifier|
      ENV["sigh_#{identifier}_appstore_profile-path"] = "/stale/#{identifier}"
      ENV["sigh_#{identifier}_appstore_profile-name"] = "match AppStore #{identifier}"
    end
  end

  def get_provisioning_profile(**options)
    @option_validator.call(options) if @option_validator
    # Fastlane checks presence, including false values, for these conflicts.
    raise "Fastlane rejects force and readonly together" if options.key?(:force) && options.key?(:readonly)

    @profile_requests << options
    ENV["SIGH_NAME"] = "current #{options.fetch(:app_identifier)}"
    "current-uuid-#{options.fetch(:app_identifier)}"
  end

  def update_code_signing_settings(**); end

  class_eval(File.read(File.expand_path("../../Fastfile", __dir__)), File.expand_path("../../Fastfile", __dir__), 1)

  def run(repair_profiles: false)
    instance_exec({repair_profiles: repair_profiles}, &self.class.lanes.fetch(:prepare_app_store_signing))
  end
end

