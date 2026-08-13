# frozen_string_literal: true

require "minitest/autorun"

class FastfileSigningTest < Minitest::Test
  FASTFILE = File.expand_path("../Fastfile", __dir__)
  CI_WORKFLOW = File.expand_path("../../.github/workflows/ci.yml", __dir__)

  def test_ci_keychain_is_configured_before_match
    signing_lane = File.read(FASTFILE)[
      /private_lane :prepare_app_store_signing do(?<body>.*?)^  end$/m,
      :body
    ]

    refute_nil signing_lane, "prepare_app_store_signing lane was not found"

    setup_ci_offset = signing_lane.index("setup_ci if ci_environment?")
    match_offset = signing_lane.index("match(")

    refute_nil setup_ci_offset, "CI signing must create Fastlane's temporary keychain"
    refute_nil match_offset, "prepare_app_store_signing must install signing material with match"
    assert_operator setup_ci_offset, :<, match_offset,
                    "setup_ci must run before match installs signing certificates"
  end

  def test_signing_lane_helpers_are_defined_in_the_fastfile
    # The lane calls `ci_environment?`; if the helper is only defined on
    # another branch, fastlane aborts at runtime with
    # "Could not find action, lane or variable 'ci_environment?'".
    # Asserting the call exists is not enough — assert the definition does too.
    fastfile = File.read(FASTFILE)

    called = fastfile.scan(/^\s*setup_ci if (\w+\??)$/).flatten.uniq

    refute_empty called, "expected the signing lane to guard setup_ci with a helper"

    called.each do |helper|
      # No \b here: helper names may end in `?`, and `?` followed by a
      # newline is two non-word characters, so a word boundary never matches.
      assert fastfile.match?(/^def #{Regexp.escape(helper)}(\s|\(|$)/),
             "Fastfile calls `#{helper}` but never defines it"
    end
  end

  def test_hosted_ci_runs_the_signing_regression
    workflow = File.read(CI_WORKFLOW)

    assert_includes workflow, "ruby fastlane/tests/fastfile_signing_test.rb"
  end

  def test_internal_testflight_does_not_pass_groups
    fastfile = File.read(FASTFILE)
    upload_lane = fastfile[
      /private_lane :upload_testflight_train do \|options\|(?<body>.*?)^  end$/m,
      :body
    ]

    refute_nil upload_lane, "upload_testflight_train lane was not found"
    assert_match(/if external.*upload_options\[:groups\]/m, upload_lane)
    assert_equal 1, upload_lane.scan(/upload_options\[:groups\]/).length,
                 "only the external path may pass a group to Fastlane"
    refute_includes fastfile, "testflight_internal_groups"
  end
end
