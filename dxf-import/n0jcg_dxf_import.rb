# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'extensions'

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('N0JCG DXF Import', 'n0jcg_dxf_importer/main')
  extension.description = 'Import ASCII DXF geometry and preserve DXF layers as SketchUp tags.'
  extension.version = '0.1.0'
  extension.creator = 'N0JCG'
  extension.copyright = '2026 N0JCG'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
