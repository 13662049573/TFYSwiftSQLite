Pod::Spec.new do |s|
  s.name             = 'TFYSwiftSQLiteKit'

  s.version          = '1.0.0'

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

  kit = 'TFYSwiftSQLite/TFYSwiftSQLiteKit'

  s.default_subspecs = 'Annotation', 'Core', 'Manager', 'ORM', 'Reflection', 'Schema', 'Utils'

  s.subspec 'Annotation' do |ss|
    ss.source_files = "#{kit}/Annotation/**/*.swift"
  end

  s.subspec 'Core' do |ss|
    ss.source_files = "#{kit}/Core/**/*.swift"
    ss.libraries    = 'sqlite3'
  end

  s.subspec 'Manager' do |ss|
    ss.source_files = "#{kit}/Manager/**/*.swift"
  end

  s.subspec 'ORM' do |ss|
    ss.source_files = "#{kit}/ORM/**/*.swift"
  end

  s.subspec 'Reflection' do |ss|
    ss.source_files = "#{kit}/Reflection/**/*.swift"
  end

  s.subspec 'Schema' do |ss|
    ss.source_files = "#{kit}/Schema/**/*.swift"
  end

  s.subspec 'Utils' do |ss|
    ss.source_files = "#{kit}/Utils/**/*.swift"
  end
end
