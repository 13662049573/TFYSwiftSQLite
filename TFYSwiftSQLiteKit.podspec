#
#  TFYSwiftSQLiteKit.podspec
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#

Pod::Spec.new do |s|
  s.name             = 'TFYSwiftSQLiteKit'

  s.version          = '1.1.0'

  s.summary          = 'Swift SQLite ORM with model migrations and optional SQLCipher encryption.'

  s.description      = <<-DESC
    TFYSwiftSQLiteKit maps Codable models to SQLite via reflection, supports @TFYPrimaryKey / @TFYColumn /
    indexes / JSON columns, type-safe and prepared queries, Date/Data/Bool scalar round-trips,
    transactional schema migration, serialized connections and transactions, WAL checkpoints,
    consistent backups, optional SQLCipher encryption, key rotation and file-format exports,
    and an App Store Privacy Manifest. CocoaPods and Swift Package Manager ship the same runtime.
  DESC
  s.homepage         = 'https://github.com/13662049573/TFYSwiftSQLite'

  s.license          = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { '田风有' => '420144542@qq.com' }

  s.source           = { :git => 'https://github.com/13662049573/TFYSwiftSQLite.git', :tag => s.version.to_s }

  s.swift_version    = '5.9'

  s.requires_arc     = true

  s.module_name      = 'TFYSwiftSQLiteKit'

  s.platforms        = {
    :ios     => '16.0',
    :osx     => '13.0',
    :tvos    => '16.0',
    :watchos => '9.0'
  }

  s.frameworks       = 'Foundation'

  kit = 'TFYSwiftSQLite/TFYSwiftSQLiteKit'
  library_sources = [
    'Annotation/TFYSwiftColumnAnnotations.swift',
    'Core/TFYSwiftDBConnection.swift',
    'Core/TFYSwiftDBError.swift',
    'Core/TFYSwiftDBEncryption.swift',
    'Core/TFYSwiftDBLogging.swift',
    'Core/TFYSwiftDBStatement.swift',
    'Manager/TFYSwiftDatabaseCenter.swift',
    'ORM/TFYSwiftColumn.swift',
    'ORM/TFYSwiftDBModel.swift',
    'ORM/TFYSwiftORM.swift',
    'ORM/TFYSwiftQuery.swift',
    'ORM/TFYSwiftTableBuilder.swift',
    'Reflection/TFYSwiftModelMirror.swift',
    'Schema/TFYSwiftAutoTable.swift',
    'Schema/TFYSwiftIndexBuilder.swift',
    'Schema/TFYSwiftSchemaMigrator.swift',
    'Utils/TFYSwiftBenchmark.swift',
    'Utils/TFYSwiftTypeMapper.swift'
  ]
  library_resources = [
    'PrivacyInfo.xcprivacy'
  ]
  runtime_tests = [
    'TFYSwiftSQLiteTests/TestModels.swift',
    'TFYSwiftSQLiteTests/TFYSwiftSQLiteKitTests.swift',
    'TFYSwiftSQLiteTests/TFYSwiftSQLiteHardeningTests.swift',
    'TFYSwiftSQLiteTests/TFYSwiftSQLiteEncryptionTests.swift'
  ]

  # Keep CocoaPods aligned file-for-file with the SwiftPM target.
  s.default_subspecs = 'Standard'
  s.subspec 'Standard' do |ss|
    ss.source_files = library_sources.map { |path| "#{kit}/#{path}" }
    ss.libraries = 'sqlite3'
    ss.test_spec 'RuntimeTests' do |ts|
      ts.platforms = { :osx => '13.0' }
      ts.source_files = runtime_tests
      ts.frameworks = 'XCTest'
    end
  end
  s.subspec 'SQLCipher' do |ss|
    ss.source_files = library_sources.map { |path| "#{kit}/#{path}" }
    ss.dependency 'SQLCipher', '~> 4.10.0'
    ss.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) TFY_SQLCIPHER',
      'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SQLITE_HAS_CODEC=1',
      'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc -DSQLITE_HAS_CODEC=1'
    }
    ss.test_spec 'RuntimeTests' do |ts|
      ts.platforms = { :osx => '13.0' }
      ts.source_files = runtime_tests
      ts.frameworks = 'XCTest'
    end
  end

  s.resource_bundles = {
    'TFYSwiftSQLiteKit_Privacy' => library_resources.map { |path| "#{kit}/#{path}" }
  }
end
