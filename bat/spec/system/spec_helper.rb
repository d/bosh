require 'spec_helper'

require 'yaml'
require 'fileutils'
require 'tempfile'
require 'resolv'

require 'common/exec'

require 'bat/stemcell'
require 'bat/release'
require 'bat/deployment'
require 'bat/bosh_helper'
require 'bat/deployment_helper'

ASSETS_DIR = File.join(SPEC_ROOT, 'system', 'assets')
BAT_RELEASE_DIR = File.join(ASSETS_DIR, 'bat-release')

RSpec.configure do |config|
  config.include(Bat::BoshHelper)
  config.include(Bat::DeploymentHelper)

  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # bosh helper isn't available, so it has to be rolled by hand
  config.before(:suite) do
    director = Bat::BoshHelper.read_environment('BAT_DIRECTOR')
    director.should_not be_nil

    output = %x{bosh --config #{Bat::BoshHelper.bosh_cli_config_path} --user admin --password admin target #{director} 2>&1}
    output.should match /Target \w*\s*set/
    $?.exitstatus.should == 0
  end

  config.before(:each) do
    requirement :no_tasks_processing unless example.metadata[:skip_task_check]
  end
end

RSpec::Matchers.define :succeed do |expected|
  match do |actual|
    actual.exit_status == 0
  end
end

RSpec::Matchers.define :succeed_with do |expected|
  match do |actual|
    if actual.exit_status != 0
      false
    elsif expected.instance_of?(String)
      actual.output == expected
    elsif expected.instance_of?(Regexp)
      !!actual.output.match(expected)
    else
      raise ArgumentError, "don't know what to do with a #{expected.class}"
    end
  end
  failure_message_for_should do |actual|
    if expected.instance_of?(Regexp)
      what = 'match'
      exp = "/#{expected.source}/"
    else
      what = 'be'
      exp = expected
    end
    "expected\n#{actual.output}to #{what}\n#{exp}"
  end
end
