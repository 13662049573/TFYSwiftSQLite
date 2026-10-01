# frozen_string_literal: true
#
#  sqlcipher_platforms.rb
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#


# SQLCipher 4.10.0 is the final upstream CocoaPods release. Its original deployment
# targets are below the simulator SDK minimums in Xcode 27. Align ONLY SQLCipher
# and its privacy resource bundle with this library's supported platform floors.
module TFYSQLCipherPlatforms
  MINIMUMS = {
    'IPHONEOS_DEPLOYMENT_TARGET' => '16.0',
    'MACOSX_DEPLOYMENT_TARGET' => '13.0',
    'TVOS_DEPLOYMENT_TARGET' => '16.0',
    'WATCHOS_DEPLOYMENT_TARGET' => '9.0'
  }.freeze

  def self.apply(installer)
    installer.pods_project.targets.each do |target|
      next unless target.name == 'SQLCipher' || target.name.start_with?('SQLCipher-')

      target.build_configurations.each do |configuration|
        MINIMUMS.each do |setting, minimum|
          current = configuration.build_settings[setting]
          next unless current && Gem::Version.new(current) < Gem::Version.new(minimum)

          configuration.build_settings[setting] = minimum
        end
      end
    end
  end
end
