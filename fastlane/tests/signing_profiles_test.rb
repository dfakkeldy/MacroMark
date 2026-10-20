# frozen_string_literal: true

require "minitest/autorun"
require "date"

class SigningProfilesTest < Minitest::Test
  HELPER = File.expand_path("../lib/signing_profiles.rb", __dir__)
  GROUP = "group.com.danfakkeldy.macromark"
  BUNDLE_ID = "com.danfakkeldy.macromark.watchkitapp"

  def setup
    assert File.file?(HELPER), "Release signing must validate installed profiles against source entitlements"
    require HELPER
    @profile = {
      "ExpirationDate" => Time.utc(2027, 1, 1),
      "Entitlements" => {
        "application-identifier" => "8AXNA5B37R.#{BUNDLE_ID}",
        "com.apple.security.application-groups" => [GROUP]
      }
    }
  end

  def validate(profile = @profile, groups: [GROUP])
    SigningProfiles.validate!(profile, bundle_identifier: BUNDLE_ID,
                              team_id: "8AXNA5B37R", required_app_groups: groups,
                              now: Time.utc(2026, 10, 20))
  end

  def test_current_profile_with_required_group_passes
    validate
  end

  def test_watch_profile_without_app_groups_fails_before_archive
    @profile["Entitlements"].delete("com.apple.security.application-groups")
    error = assert_raises(ArgumentError) { validate }
    assert_includes error.message, BUNDLE_ID
    assert_includes error.message, GROUP
  end

  def test_profile_for_another_group_cannot_sign_the_app
    @profile["Entitlements"]["com.apple.security.application-groups"] = ["group.another.app"]
    assert_raises(ArgumentError) { validate }
  end

  def test_every_source_group_must_be_in_the_profile
    assert_raises(ArgumentError) { validate(groups: [GROUP, "group.second"]) }
  end

  def test_existing_iphone_source_without_app_groups_still_passes
    @profile["Entitlements"].delete("com.apple.security.application-groups")
    validate(groups: [])
  end

  def test_expired_profile_is_rejected
    @profile["ExpirationDate"] = Time.utc(2026, 10, 19)
    assert_raises(ArgumentError) { validate }
  end

  def test_plist_parser_datetime_expiration_passes
    @profile["ExpirationDate"] = DateTime.parse("2027-01-01T00:00:00Z")
    validate
  end

  def test_wrong_bundle_identity_is_rejected
    @profile["Entitlements"]["application-identifier"] = "8AXNA5B37R.another.app"
    assert_raises(ArgumentError) { validate }
  end
end
