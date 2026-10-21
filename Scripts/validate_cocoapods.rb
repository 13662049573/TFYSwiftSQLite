# frozen_string_literal: true
#
#  validate_cocoapods.rb
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#

require_relative 'cocoapods_validation_support'

backend = ARGV.shift || 'All'
# CocoaPods ships only the Standard backend since 1.1.2 (SQLCipher is SwiftPM-only).
abort('Choose All or Standard') unless %w[All Standard].include?(backend)
remote = ARGV.delete('--remote')
# Publication checks must actually compile, import and run the available tests.
abort('Build/import/test validation cannot be skipped') if ARGV.any? { |arg| arg.start_with?('--skip', '--quick', '--no-subspecs') }
repo_root = File.expand_path('..', __dir__)
Dir.chdir(repo_root) do
  command = [remote ? 'spec' : 'lib', 'lint', 'TFYSwiftSQLiteKit.podspec', '--allow-warnings']
  command << "--subspec=#{backend}" unless backend == 'All'
  Pod::Command.run(command + ARGV)
end
