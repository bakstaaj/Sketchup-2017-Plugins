# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'extensions'

module N0JCG
  module STEPImport
  end
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('N0JCG STEP Import', 'n0jcg_step_importer/main')
  extension.description = 'Convert STEP models with Blender and import them into SketchUp.'
  extension.version = '0.3.3'
  extension.creator = 'N0JCG'
  extension.copyright = '2026 N0JCG'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
