Pod::Spec.new do |s|
  s.name             = 'TFYSwiftSQLiteKit'

  s.version          = '1.0.6'

  s.summary          = 'Swift ORM layer on SQLite3 with property-wrapper schema and migrations.'

  s.description      = <<-DESC
    TFYSwiftSQLiteKit maps Codable models to SQLite via reflection, supports @TFYPrimaryKey / @TFYColumn /
    indexes / JSON columns, type-safe and prepared queries, Date/Data/Bool scalar round-trips,
    safe schema migration, WAL-backed connections, Swift concurrency support, and an App Store
    Privacy Manifest. CocoaPods and Swift Package Manager ship the same complete runtime sources.
  DESC
  s.homepage         = 'https://github.com/13662049573/TFYSwiftSQLite'

  s.license          = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { '田风有' => '420144542@qq.com' }

  s.source           = { :git => 'https://github.com/13662049573/TFYSwiftSQLite.git', :tag => s.version.to_s }

  s.swift_version    = '5.9'

  s.requires_arc     = true

  s.module_name      = 'TFYSwiftSQLiteKit'

  s.platforms        = {
    :ios     => '15.0',
    :osx     => '13.0',
    :tvos    => '13.0',
    :watchos => '6.0'
  }

  s.frameworks       = 'Foundation'
  s.libraries        = 'sqlite3'

  kit = 'TFYSwiftSQLite/TFYSwiftSQLiteKit'
  library_sources = [
    'Annotation/TFYSwiftColumnAnnotations.swift',
    'Core/TFYSwiftDBConnection.swift',
    'Core/TFYSwiftDBError.swift',
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

  # Keep CocoaPods aligned file-for-file with the SwiftPM target.
  s.source_files = library_sources.map { |path| "#{kit}/#{path}" }

  s.resource_bundles = {
    'TFYSwiftSQLiteKit_Privacy' => library_resources.map { |path| "#{kit}/#{path}" }
  }
end
