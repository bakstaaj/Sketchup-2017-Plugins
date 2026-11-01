# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'extensions'

module N0JCG
  module BlenderMerge
  end
end

unless file_loaded?(__FILE__)
  extension = SketchupExtension.new('N0JCG Blender Merge', 'n0jcg_blender_merge/main')
  extension.description = 'Union two selected SketchUp groups using Blender and the installed STL extension.'
  extension.version = '1.2.3'
  extension.creator = 'N0JCG'
  extension.copyright = '2026 N0JCG'
  Sketchup.register_extension(extension, true)
  file_loaded(__FILE__)
end
