Pod::Spec.new do |s|
  s.name             = 'TFYSwiftSQLiteKit'

  s.version          = '1.0.1'

  s.summary          = 'Swift ORM layer on SQLite3 with property-wrapper schema and migrations.'

  s.description      = <<-DESC
    TFYSwiftSQLiteKit maps Codable models to SQLite via reflection, supports @TFYPrimaryKey / @TFYColumn /
    indexes / JSON columns, lightweight schema migration (TFYSwiftAutoTable), and WAL-backed connections.
  DESC
  s.homepage         = 'https://github.com/13662049573/TFYSwiftSQLite'

  s.license          = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { '田风有' => '420144542@qq.com' }

  s.source           = { :git => 'https://github.com/13662049573/TFYSwiftSQLite.git', :tag => s.version.to_s }

  s.swift_version    = '5.0'

  s.requires_arc     = true

  s.module_name      = 'TFYSwiftSQLiteKit'

  s.ios.deployment_target      = '15.0'
  s.osx.deployment_target      = '13.5'
  s.tvos.deployment_target     = '15.0'
  s.watchos.deployment_target  = '8.0'

  s.frameworks       = 'Foundation'
  s.libraries        = 'sqlite3'

  kit = 'TFYSwiftSQLite/TFYSwiftSQLiteKit'

  # Folder layout kept 1:1 with the library source tree.
  # Internal dependency graph (code-level, documented here for maintenance):
  # - Annotation -> Utils
  # - Manager -> Core
  # - Reflection -> Annotation/Core/ORM/Utils
  # - Schema -> Core/Manager/ORM/Reflection
  # - Utils -> Core/ORM
  # - ORM -> Core/Manager/Reflection/Schema/Utils
  #
  # The runtime currently contains circular references across ORM/Utils/Reflection/Schema,
  # so CocoaPods integration ships the full kit as one pod while preserving folder-based globs.
  s.source_files = [
    "#{kit}/Annotation/**/*.swift",
    "#{kit}/Core/**/*.swift",
    "#{kit}/Manager/**/*.swift",
    "#{kit}/ORM/**/*.swift",
    "#{kit}/Reflection/**/*.swift",
    "#{kit}/Schema/**/*.swift",
    "#{kit}/Utils/**/*.swift"
  ]
end
