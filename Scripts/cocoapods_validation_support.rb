# frozen_string_literal: true
#
#  cocoapods_validation_support.rb
#  TFYSwiftSQLiteKit
#
#  Created by 田风有 on 2021/5/9.
#

require 'cocoapods'
require_relative 'sqlcipher_platforms'

# Match the documented host post_install settings in the temporary lint app.
# Never change upstream SQLCipher source or bypass compilation/import validation.
module TFYSQLCipherLintPlatforms
  def configure_pod_targets(results)
    super
    TFYSQLCipherPlatforms.apply(@installer)
  end
end
Pod::Validator.prepend(TFYSQLCipherLintPlatforms)

