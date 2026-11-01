# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'extensions'

module N0JCG
  module BooleanTools
    ROOT = File.dirname(__FILE__).freeze
    EXTENSION = SketchupExtension.new(
      'N0JCG Boolean Tools',
      File.join(ROOT, 'boolean_tools', 'main.rb')
    )
    EXTENSION.description = 'Subtract one solid from another or keep both non-common solid portions.'
    EXTENSION.version = '1.1.0'
    EXTENSION.creator = 'N0JCG'
    EXTENSION.copyright = '2026 N0JCG, MIT License'
    Sketchup.register_extension(EXTENSION, true)
  end
end
