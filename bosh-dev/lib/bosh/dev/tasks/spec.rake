require 'rspec'
require 'rspec/core/rake_task'
require 'tempfile'
require 'bosh/dev/bat_helper'

namespace :spec do
  desc 'Run BOSH integration tests against a local sandbox'
  task :integration do
    require 'parallel_tests/tasks'
    Rake::Task['parallel:spec'].invoke(ENV['TRAVIS'] ? 6 : nil, 'spec/integration/.*_spec.rb')
  end

  desc 'Run unit and functional tests for each BOSH component gem'
  task :parallel_unit do
    require 'common/thread_pool'
    trap('INT') { exit }

    builds = Dir['*'].select { |f| File.directory?(f) && File.exists?("#{f}/spec") }
    builds -= ['bat']

    spec_logs = Dir.mktmpdir

    puts "Logging spec results in #{spec_logs}"

    Bosh::ThreadPool.new(max_threads: 10, logger: Logger.new('/dev/null')).wrap do |pool|
      builds.each do |build|
        puts "-----Building #{build}-----"

        pool.process do
          log_file = "#{spec_logs}/#{build}.log"
          cmd = "cd #{build} && rspec --tty -c -f p spec > #{log_file} 2>&1"
          success = system(cmd)

          if success
            print File.read(log_file)
          else
            raise("#{build} failed to build unit tests: #{File.read(log_file)}")
          end
        end
      end

      pool.wait
    end
  end

  desc 'Run unit and functional tests linearly'
  task unit: %w(rubocop) do
    builds = Dir['*'].select { |f| File.directory?(f) && File.exists?("#{f}/spec") }
    builds -= ['bat']

    builds.each do |build|
      puts "-----#{build}-----"
      system("cd #{build} && rspec spec") || raise("#{build} failed to build unit tests")
    end
  end

  desc 'Run integration and unit tests in parallel'
  task :parallel_all do
    unit        = Thread.new { Rake::Task['spec:parallel_unit'].invoke }
    integration = Thread.new { Rake::Task['spec:integration'].invoke }
    [unit, integration].each(&:join)
  end

  namespace :external do
    desc 'AWS CPI can exercise the VM lifecycle'
    RSpec::Core::RakeTask.new(:aws_vm_lifecycle) do |t|
      t.pattern = 'spec/external/aws_cpi_spec.rb'
      t.rspec_opts = %w(--format documentation --color)
    end

    desc 'AWS bootstrap CLI can provision and destroy resources'
    RSpec::Core::RakeTask.new(:aws_bootstrap) do |t|
      t.pattern = 'spec/external/aws_bootstrap_spec.rb'
      t.rspec_opts = %w(--format documentation --color)
    end

    desc 'OpenStack CPI can exercise the VM lifecycle'
    RSpec::Core::RakeTask.new(:openstack_vm_lifecycle) do |t|
      t.pattern = 'spec/external/openstack_cpi_spec.rb'
      t.rspec_opts = %w(--format documentation --color)
    end

    desc 'vSphere CPI can exercise the VM lifecycle'
    RSpec::Core::RakeTask.new(:vsphere_vm_lifecycle) do |t|
      require 'bosh/dev/build'
      ENV['BOSH_VSPHERE_STEMCELL'] = Bosh::Dev::Build.candidate.download_stemcell(
        infrastructure:   Bosh::Stemcell::Infrastructure.for('vsphere'),
        operating_system: Bosh::Stemcell::OperatingSystem.for('ubuntu'),
        name: 'bosh-stemcell',
        light: false
      )
      t.pattern = 'spec/external/vsphere_cpi_spec.rb'
      t.rspec_opts = %w(--format documentation --color)
    end
  end

  namespace :system do
    task :micro, [:infrastructure_name, :operating_system_name, :net_type] do |_, args|
      require 'bosh/dev/aws/runner_builder'
      require 'bosh/dev/openstack/runner_builder'
      require 'bosh/dev/vsphere/runner_builder'

      runner_class = {
        'aws'       => Bosh::Dev::Aws::RunnerBuilder,
        'openstack' => Bosh::Dev::Openstack::RunnerBuilder,
        'vsphere'   => Bosh::Dev::VSphere::RunnerBuilder,
      }[args.infrastructure_name]

      bat_helper = Bosh::Dev::BatHelper.new(
        args.infrastructure_name,
        args.operating_system_name,
        args.net_type,
      )
      runner = runner_class.new.build(bat_helper, args.net_type)
      runner.deploy_microbosh_and_run_bats
    end
  end
end

desc 'Run unit and integration specs'
task :spec => ['spec:parallel_unit', 'spec:integration']
