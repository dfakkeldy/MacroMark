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

  def test_hosted_ci_runs_the_signing_regression
    workflow = File.read(CI_WORKFLOW)

    assert_includes workflow, "ruby fastlane/tests/fastfile_signing_test.rb"
  end
end
