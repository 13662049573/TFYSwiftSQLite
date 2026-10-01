# frozen_string_literal: true
#
#  publish_cocoapods.rb
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#

require_relative 'cocoapods_validation_support'
require 'open3'

abort('Build/import/test validation cannot be skipped') if ARGV.any? { |arg| arg.start_with?('--skip', '--quick', '--no-subspecs') }
repo_root = File.expand_path('..', __dir__)
Dir.chdir(repo_root) do
  spec = Pod::Specification.from_file('TFYSwiftSQLiteKit.podspec')
  version = spec.version.to_s
  remote_tags, status = Open3.capture2('git', 'ls-remote', '--tags', spec.source[:git], "refs/tags/#{version}", "refs/tags/#{version}^{}")
  abort("Cannot read remote tags for #{version}") unless status.success?
  tags = remote_tags.lines.to_h { |line| sha, name = line.split; [name, sha] }
  sha = tags["refs/tags/#{version}^{}"] || tags["refs/tags/#{version}"]
  abort("Create and push GitHub tag #{version} before publishing CocoaPods") unless sha
  head, status = Open3.capture2('git', 'rev-parse', 'HEAD')
  abort("Remote tag #{version} must point to this checkout's HEAD") unless status.success? && sha == head.strip
  changed, status = Open3.capture2('git', 'status', '--porcelain', '--untracked-files=all', '--', '.', ':!**/xcuserdata/**', ':!**/*.xcuserstate')
  abort('Commit release files before publishing CocoaPods') unless status.success? && changed.strip.empty?
  abort('Distribution layout validation failed') unless system(RbConfig.ruby, 'Scripts/validate_distribution_layout.rb')
  # Trunk validates the Git source/tag and all subspecs before uploading. The hook
  # only raises the upstream dependency's unsupported deployment targets.
  Pod::Command.run(['trunk', 'push', 'TFYSwiftSQLiteKit.podspec', '--allow-warnings'] + ARGV)
end
