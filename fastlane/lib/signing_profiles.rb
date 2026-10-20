# frozen_string_literal: true

require "open3"

module SigningProfiles
  APP_GROUPS = "com.apple.security.application-groups"

  def self.validate!(profile, bundle_identifier:, team_id:, required_app_groups:, now: Time.now)
    entitlements = profile.fetch("Entitlements", {})
    expected_identifier = "#{team_id}.#{bundle_identifier}"
    unless entitlements["application-identifier"] == expected_identifier
      raise ArgumentError, "#{bundle_identifier}: installed profile has the wrong application identifier"
    end
    expiration = profile["ExpirationDate"]
    unless expiration.respond_to?(:to_time) && expiration.to_time > now
      raise ArgumentError, "#{bundle_identifier}: installed profile is expired or has no expiration date"
    end
    missing = required_app_groups - Array(entitlements[APP_GROUPS])
    return if missing.empty?

    raise ArgumentError, "#{bundle_identifier}: installed profile is missing App Groups: #{missing.join(', ')}. " \
                         "Regenerate the affected profiles with repair_profiles=true on a manual Nightly run."
  end

  def self.verify!(project_path:, signing_targets:, team_id:)
    require "xcodeproj"
    require "plist"

    root = File.dirname(project_path)
    project = Xcodeproj::Project.open(project_path)
    signing_targets.each do |target_name, signing|
      target = project.targets.find { |item| item.name == target_name }
      raise ArgumentError, "Signing target is missing: #{target_name}" unless target

      config = target.build_configurations.find { |item| item.name == "Release" }
      raise ArgumentError, "Release configuration is missing: #{target_name}" unless config

      entitlement_file = config.resolve_build_setting("CODE_SIGN_ENTITLEMENTS").to_s
      groups = []
      unless entitlement_file.empty?
        entitlement_file = entitlement_file.gsub(/\$\((SRCROOT|PROJECT_DIR)\)/, root)
        path = File.expand_path(entitlement_file, root)
        raise ArgumentError, "#{target_name}: source entitlements file is missing" unless File.file?(path)

        groups = Array(Plist.parse_xml(path).fetch(APP_GROUPS, []))
      end

      identifier = signing.fetch(:bundle_identifier)
      profile_path = ENV["sigh_#{identifier}_appstore_profile-path"].to_s
      unless File.file?(profile_path)
        raise ArgumentError, "#{identifier}: match did not install a provisioning profile"
      end
      xml, _error, status = Open3.capture3("security", "cms", "-D", "-i", profile_path)
      raise ArgumentError, "#{identifier}: could not decode the installed profile" unless status.success?

      validate!(Plist.parse_xml(xml), bundle_identifier: identifier, team_id: team_id,
                required_app_groups: groups)
    end
  end
end
