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

  # TFYSwiftSQLiteKit/
  #   Annotation/
  #   Core/
  #   Manager/
  #   ORM/
  #   Reflection/
  #   Schema/
  #   Utils/
  # 源码按上述目录存放；编译入口为 Base（整包同一模块）。各目录名 subspec 依赖 Base，避免按目录拆编译时的交叉引用与 CocoaPods subspec 循环依赖。

  s.subspec 'Base' do |ss|
    ss.source_files = "#{kit}/**/*.swift"
    ss.libraries    = 'sqlite3'
  end

  folders = %w[Annotation Core Manager ORM Reflection Schema Utils]

  folders.each do |folder|
    s.subspec folder do |ss|
      ss.dependency 'TFYSwiftSQLiteKit/Base'
    end
  end

  s.default_subspecs = 'Base'
end
