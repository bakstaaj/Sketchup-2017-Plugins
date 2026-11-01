# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'extensions'

module N0JCG
  module STLImportCleanUp3
    ROOT = File.dirname(__FILE__).freeze
    EXTENSION = SketchupExtension.new(
      'STL Import + CleanUp³',
      File.join(ROOT, 'zz_stl_cleanup3', 'main.rb')
    )
    EXTENSION.description = 'Selects newly imported STL geometry and runs CleanUp³ with its saved settings.'
    EXTENSION.version = '1.0.0'
    EXTENSION.creator = 'N0JCG'
    EXTENSION.copyright = '2026 N0JCG, MIT License'
    Sketchup.register_extension(EXTENSION, true)
  end
end
