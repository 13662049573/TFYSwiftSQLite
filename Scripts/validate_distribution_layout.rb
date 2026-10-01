# frozen_string_literal: true
#
#  validate_distribution_layout.rb
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#


repo_root = File.expand_path("..", __dir__)
library_root = "TFYSwiftSQLite/TFYSwiftSQLiteKit"

read = ->(path) { File.read(File.join(repo_root, path)) }
abort_with = ->(message) { abort("Distribution validation failed: #{message}") }

podspec = read.call("TFYSwiftSQLiteKit.podspec")
package = read.call("Package.swift")
modern_package = read.call("Package@swift-6.1.swift")
project = read.call("TFYSwiftSQLite.xcodeproj/project.pbxproj")
readme = read.call("README.md")

header_paths = Dir.glob(File.join(repo_root, '{TFYSwiftSQLite,TFYSwiftSQLiteTests,TFYSwiftSQLiteBenchmarks,Examples,Sources}', '**', '*.{swift,h,m}')) +
               Dir.glob(File.join(repo_root, 'Package*.swift')) +
               Dir.glob(File.join(repo_root, 'Scripts', '*.rb')) +
               [File.join(repo_root, 'TFYSwiftSQLiteKit.podspec')]
header_paths.each do |path|
  prefix = File.read(path)[0, 600]
  marker = %w[.rb .podspec].include?(File.extname(path)) ? '#' : '//'
  unless prefix.include?("#{marker}  #{File.basename(path)}") &&
         prefix.include?("#{marker}  TFYSwiftSQLiteKit") &&
         prefix.include?("#{marker}  Created by 田风有 on 2021/5/9.")
    abort_with.call("Missing or incorrect file header: #{path.delete_prefix(repo_root + '/')}")
  end
end

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
modern_sources = modern_package[/let librarySources = \[(.*?)\]/m, 1]&.scan(/"([^"]+)"/)&.flatten&.sort
unless modern_sources == relative_source_files
  abort_with.call("SwiftPM 6.1 sources differ from complete runtime")
end
unless package_sources == relative_source_files
  abort_with.call("SwiftPM sources differ: expected #{relative_source_files}, got #{package_sources}")
end
unless pod_sources == relative_source_files
  abort_with.call("CocoaPods sources differ: expected #{relative_source_files}, got #{pod_sources}")
end
test_files = Dir.glob(File.join(repo_root, 'TFYSwiftSQLiteTests', '*.swift')).map { |path| File.basename(path) }.sort
[package, modern_package].each do |manifest|
  listed = manifest[/path: "TFYSwiftSQLiteTests",\s*sources: \[(.*?)\]/m, 1]&.scan(/"([^"]+)"/)&.flatten&.sort
  abort_with.call('SwiftPM test source list differs from complete test suite') unless listed == test_files
end
pod_tests = podspec[/runtime_tests = \[(.*?)\]/m, 1]&.scan(/'TFYSwiftSQLiteTests\/([^']+)'/)&.flatten&.sort
unless pod_tests == test_files && podspec.scan("ss.test_spec 'RuntimeTests'").count == 2
  abort_with.call('Each CocoaPods backend must include the complete runtime test suite')
end

package_resource_block = package[/let libraryResources = \[(.*?)\]/m, 1]
pod_resource_block = podspec[/library_resources = \[(.*?)\]/m, 1]
abort_with.call("Package.swift is missing libraryResources") unless package_resource_block
abort_with.call("Podspec is missing library_resources") unless pod_resource_block

package_resources = package_resource_block.scan(/"([^"]+)"/).flatten.sort
pod_resources = pod_resource_block.scan(/'([^']+)'/).flatten.sort
modern_resources = modern_package[/let libraryResources = \[(.*?)\]/m, 1]&.scan(/"([^"]+)"/)&.flatten&.sort
unless modern_resources == resource_files
  abort_with.call("SwiftPM 6.1 resources differ from complete runtime")
end
unless modern_package.include?('.product(name: "SQLCipher", package: "SQLCipher.swift", condition: .when(traits: ["SQLCipher"]))') &&
       modern_package.include?('.target(name: "CTFYSQLCipher", condition: .when(traits: ["SQLCipher"]))') &&
       modern_package.include?('.define("TFY_SQLCIPHER", .when(traits: ["SQLCipher"]))') &&
       !modern_package.include?('.linkedLibrary("sqlite3")') &&
       !modern_package.include?('.unsafeFlags')
  abort_with.call("Modern SwiftPM must select SQLCipher explicitly without system SQLite or unsafe flags")
end
unless podspec.include?("s.default_subspecs = 'Standard'") &&
       podspec.include?("ss.dependency 'SQLCipher', '~> 4.10.0'") &&
       podspec.scan('ss.source_files = library_sources.map').count == 2
  abort_with.call("CocoaPods must include both complete, mutually exclusive backend subspecs")
end
unless package_resources == resource_files
  abort_with.call("SwiftPM resources differ: expected #{resource_files}, got #{package_resources}")
end
unless pod_resources == resource_files
  abort_with.call("CocoaPods resources differ: expected #{resource_files}, got #{pod_resources}")
end

unless package.include?("resources: libraryResources.map { .process($0) }")
  abort_with.call("SwiftPM target is not connected to libraryResources")
end
unless podspec.include?("ss.source_files = library_sources.map") &&
       podspec.include?("library_resources.map")
  abort_with.call("Podspec source/resource lists are not connected to the pod target")
end

expected_project_files = (source_files + resource_files.map { |path| "#{library_root}/#{path}" }).sort
project_library_files = project.scan(/path = (#{Regexp.escape(library_root)}\/[^;]+);/).flatten.sort
unless project_library_files == expected_project_files
  abort_with.call("Xcode library files differ: expected #{expected_project_files}, got #{project_library_files}")
end

excluded_library_files = project.scan(/TFYSwiftSQLiteKit\/[^,;\n]+/).map { |path| path.delete_suffix('"') }
relative_source_files.each do |path|
  unless excluded_library_files.include?("TFYSwiftSQLiteKit/#{path}")
    abort_with.call("Demo must consume the package instead of recompiling #{path}")
  end
end

version = podspec[/s\.version\s*=\s*'([^']+)'/, 1]
abort_with.call("Podspec version is missing") unless version
abort_with.call("README current version does not match #{version}") unless readme.include?("**当前版本：`#{version}`**")

project_versions = project.scan(/MARKETING_VERSION = ([^;]+);/).flatten.uniq
unless project_versions == [version]
  abort_with.call("Xcode marketing versions differ: expected #{version}, got #{project_versions}")
end
abort_with.call("Release notes are missing for #{version}") unless File.file?(File.join(repo_root, "docs/Release-#{version}.md"))
unless [package, modern_package].all? { |manifest| manifest.include?("release #{version}.") }
  abort_with.call("Both manifests must describe release #{version}")
end
unless readme.include?("from: \"#{version}\"") && readme.include?("'~> #{version}'")
  abort_with.call("README installation examples must use #{version}")
end

expected_platforms = {
  "ios" => "16.0",
  "macos" => "13.0",
  "tvos" => "16.0",
  "watchos" => "9.0"
}
pod_platform_keys = {
  "ios" => "ios",
  "macos" => "osx",
  "tvos" => "tvos",
  "watchos" => "watchos"
}
package_platform_versions = package.scan(/\.(iOS|macOS|tvOS|watchOS)\(\.v(\d+)\)/).to_h do |name, value|
  [name.downcase, "#{value}.0"]
end
modern_platform_versions = modern_package.scan(/\.(iOS|macOS|tvOS|watchOS)\(\.v(\d+)\)/).to_h do |name, value|
  [name.downcase, "#{value}.0"]
end
pod_platform_versions = pod_platform_keys.to_h do |name, key|
  [name, podspec[/\:#{key}\s*=>\s*'(\d+\.\d+)'/, 1]]
end

unless package_platform_versions == expected_platforms
  abort_with.call("SwiftPM platforms differ: expected #{expected_platforms}, got #{package_platform_versions}")
end
unless modern_platform_versions == expected_platforms
  abort_with.call("SwiftPM 6.1 platforms differ: #{modern_platform_versions}")
end
unless project.scan(/IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);/).flatten.uniq == [expected_platforms['ios']]
  abort_with.call("Xcode iOS targets must use #{expected_platforms['ios']}")
end
demo_platforms = read.call('Examples/SQLCipherDemo/Package.swift').scan(/\.(iOS|macOS|tvOS|watchOS)\(\.v(\d+)\)/).to_h do |name, value|
  [name.downcase, "#{value}.0"]
end
abort_with.call('SQLCipher demo platform floors are inconsistent') unless demo_platforms == expected_platforms
hook = read.call('Scripts/sqlcipher_platforms.rb')
{ 'ios' => 'IPHONEOS', 'macos' => 'MACOSX', 'tvos' => 'TVOS', 'watchos' => 'WATCHOS' }.each do |platform, setting|
  unless hook.include?("'#{setting}_DEPLOYMENT_TARGET' => '#{expected_platforms[platform]}'")
    abort_with.call("SQLCipher hook #{platform} floor is inconsistent")
  end
end
test_macos_versions = podspec.scan(/ts\.platforms\s*=\s*\{\s*:osx\s*=>\s*'([^']+)'\s*\}/).flatten
unless test_macos_versions == [expected_platforms['macos']] * 2
  abort_with.call('Both CocoaPods RuntimeTests must match the library macOS floor')
end
unless pod_platform_versions == expected_platforms
  abort_with.call("CocoaPods platforms differ: expected #{expected_platforms}, got #{pod_platform_versions}")
end

puts "Distribution layout is aligned: #{source_files.count} sources, #{resource_files.count} resources, version #{version}, platforms #{expected_platforms}."
