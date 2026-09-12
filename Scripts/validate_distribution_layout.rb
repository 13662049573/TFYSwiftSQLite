# frozen_string_literal: true

repo_root = File.expand_path("..", __dir__)
library_root = "TFYSwiftSQLite/TFYSwiftSQLiteKit"

read = ->(path) { File.read(File.join(repo_root, path)) }
abort_with = ->(message) { abort("Distribution validation failed: #{message}") }

podspec = read.call("TFYSwiftSQLiteKit.podspec")
package = read.call("Package.swift")
project = read.call("TFYSwiftSQLite.xcodeproj/project.pbxproj")
readme = read.call("README.md")

source_files = Dir.glob(File.join(repo_root, library_root, "**", "*.swift"))
                  .map { |path| path.delete_prefix("#{repo_root}/") }
                  .sort
relative_source_files = source_files.map { |path| path.delete_prefix("#{library_root}/") }
resource_files = Dir.glob(File.join(repo_root, library_root, "**", "*"))
                    .select { |path| File.file?(path) && File.extname(path) != ".swift" }
                    .map { |path| path.delete_prefix("#{repo_root}/#{library_root}/") }
                    .sort

package_source_block = package[/let librarySources = \[(.*?)\]/m, 1]
pod_source_block = podspec[/library_sources = \[(.*?)\]/m, 1]
abort_with.call("Package.swift is missing librarySources") unless package_source_block
abort_with.call("Podspec is missing library_sources") unless pod_source_block

package_sources = package_source_block.scan(/"([^"]+)"/).flatten.sort
pod_sources = pod_source_block.scan(/'([^']+)'/).flatten.sort
unless package_sources == relative_source_files
  abort_with.call("SwiftPM sources differ: expected #{relative_source_files}, got #{package_sources}")
end
unless pod_sources == relative_source_files
  abort_with.call("CocoaPods sources differ: expected #{relative_source_files}, got #{pod_sources}")
end

package_resource_block = package[/let libraryResources = \[(.*?)\]/m, 1]
pod_resource_block = podspec[/library_resources = \[(.*?)\]/m, 1]
abort_with.call("Package.swift is missing libraryResources") unless package_resource_block
abort_with.call("Podspec is missing library_resources") unless pod_resource_block

package_resources = package_resource_block.scan(/"([^"]+)"/).flatten.sort
pod_resources = pod_resource_block.scan(/'([^']+)'/).flatten.sort
unless package_resources == resource_files
  abort_with.call("SwiftPM resources differ: expected #{resource_files}, got #{package_resources}")
end
unless pod_resources == resource_files
  abort_with.call("CocoaPods resources differ: expected #{resource_files}, got #{pod_resources}")
end

unless package.include?("resources: libraryResources.map { .process($0) }")
  abort_with.call("SwiftPM target is not connected to libraryResources")
end
unless podspec.include?("s.source_files = library_sources.map") &&
       podspec.include?("library_resources.map")
  abort_with.call("Podspec source/resource lists are not connected to the pod target")
end

expected_project_files = (source_files + resource_files.map { |path| "#{library_root}/#{path}" }).sort
project_library_files = project.scan(/path = (#{Regexp.escape(library_root)}\/[^;]+);/).flatten.sort
unless project_library_files == expected_project_files
  abort_with.call("Xcode library files differ: expected #{expected_project_files}, got #{project_library_files}")
end

version = podspec[/s\.version\s*=\s*'([^']+)'/, 1]
abort_with.call("Podspec version is missing") unless version
abort_with.call("README current version does not match #{version}") unless readme.include?("**当前版本：`#{version}`**")

project_versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.uniq
unless project_versions == [version]
  abort_with.call("Xcode marketing versions differ: expected #{version}, got #{project_versions}")
end

puts "Distribution layout is aligned: #{source_files.count} sources, #{resource_files.count} resources, version #{version}."
