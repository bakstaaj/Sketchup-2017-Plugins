# Copyright 2026 N0JCG. Released under the MIT License.
# SketchUp 2017 compatible companion to SketchUp STL Import & Export.
require 'sketchup'
require 'extensions'

module N0JCG
  module STLManifoldCheck
    ROOT = File.dirname(__FILE__).freeze
    EXTENSION = SketchupExtension.new('STL Manifold Check', File.join(ROOT, 'stl_manifold_check', 'main.rb'))
    EXTENSION.description = 'Checks selected geometry for open and non-manifold edges and highlights their locations.'
    EXTENSION.version = '0.1.6'
    EXTENSION.creator = 'N0JCG'
    EXTENSION.copyright = '2026 N0JCG, MIT License'
    Sketchup.register_extension(EXTENSION, true)
  end
end
