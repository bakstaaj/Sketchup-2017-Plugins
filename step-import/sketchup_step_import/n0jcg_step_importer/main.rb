# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'fileutils'
require 'tmpdir'

module N0JCG
  module STEPImport
    extend self

    PREF_KEY = 'N0JCG STEP Import'.freeze
    CONVERTER_PATH = File.join(File.dirname(__FILE__), 'step_to_stl.py').freeze

    def blender_path
      saved = Sketchup.read_default(PREF_KEY, 'blender_path', '')
      if saved && !saved.empty? && File.file?(saved)
        return saved
      end

      roots = [ENV['ProgramFiles'], ENV['ProgramW6432'], ENV['ProgramFiles(x86)']].compact.uniq
      candidates = roots.inject([]) do |paths, root|
        paths.concat(Dir.glob(File.join(root, 'Blender Foundation', 'Blender *', 'blender.exe')))
        paths
      end
      candidates.select! { |path| File.file?(path) }
      unless candidates.empty?
        selected = candidates.max_by { |path| path[/Blender\s+([0-9.]+)/i, 1].to_s.split('.').map(&:to_i) }
        Sketchup.write_default(PREF_KEY, 'blender_path', selected)
        return selected
      end

      selected = UI.openpanel('Locate Blender', nil, 'blender.exe')
      unless selected && File.file?(selected)
        UI.messagebox('Blender was not located. Install Blender, then choose blender.exe when prompted.')
        return nil
      end
      Sketchup.write_default(PREF_KEY, 'blender_path', File.expand_path(selected))
      File.expand_path(selected)
    end

    def import_step
      source = UI.openpanel('Select STEP model', nil, 'STEP Files|*.step;*.stp||')
      return unless source
      unless File.file?(source)
        UI.messagebox('The selected STEP file could not be found.')
        return
      end
      ext = File.extname(source).downcase
      unless ['.step', '.stp'].include?(ext)
        UI.messagebox('Choose a .step or .stp file.')
        return
      end
      unless defined?(CommunityExtensions::STL::Importer)
        UI.messagebox('Enable SketchUp’s STL Import & Export extension before using N0JCG STEP Import.')
        return
      end

      blender = blender_path
      return unless blender

      work_dir = Dir.mktmpdir('n0jcg_step_import_')
      stl_path = File.join(work_dir, 'converted_model.stl')
      log_path = File.join(work_dir, 'blender_conversion.log')
      report_path = File.join(work_dir, 'conversion_report.txt')
      env = {
        'N0JCG_STEP_INPUT' => File.expand_path(source),
        'N0JCG_STEP_OUTPUT' => stl_path,
        'N0JCG_STEP_REPORT' => report_path,
        'N0JCG_STEP_EXPORT_SCALE' => '1000'
      }

      Sketchup.status_text = 'Converting STEP geometry with Blender...'
      success = system(env, blender, '--background', '--python', CONVERTER_PATH,
                       :out => log_path, :err => [:child, :out])
      unless success && File.file?(stl_path) && File.size(stl_path) > 84
        details = []
        details << File.read(report_path) if File.file?(report_path)
        details << File.readlines(log_path).last(18).join if File.file?(log_path)
        detail = details.empty? ? 'Blender did not create an STL file.' : details.join("\n")
        raise "Blender could not convert the STEP file.\n\n#{detail}"
      end

      Sketchup.status_text = 'Importing converted mesh into SketchUp...'
      importer = CommunityExtensions::STL::Importer
      pref_key = 'CommunityExtensions\\STL\\Importer'
      unit_key = 'import_units'
      # The STL extension defines unit constants on CommunityExtensions::STL,
      # not on its Importer class.
      millimeters = CommunityExtensions::STL::UNIT_MILLIMETERS
      old_units = Sketchup.read_default(pref_key, unit_key, millimeters)
      Sketchup.write_default(pref_key, unit_key, millimeters)
      begin
        # SketchUp STL Import & Export marks #main private; #load_file is its
        # public importer entry point and delegates to #main internally.
        status = importer.new.load_file(stl_path, nil)
      ensure
        Sketchup.write_default(pref_key, unit_key, old_units)
      end
      unless status == CommunityExtensions::STL::Importer::IMPORT_SUCCESS
        raise 'SketchUp’s STL importer did not complete the mesh import.'
      end
      Sketchup.active_model.active_view.zoom_extents
      UI.messagebox(
        "STEP model imported as a triangulated SketchUp mesh.\n\n" +
        "Blender prepared the mesh; SketchUp imported it using millimeter units and your saved STL repair/merge settings."
      )
    rescue => error
      UI.messagebox("STEP import failed:\n#{error.message}")
    ensure
      Sketchup.status_text = ''
      FileUtils.remove_entry(work_dir) if work_dir && File.directory?(work_dir)
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('N0JCG STEP Import')
      menu.add_item('Import STEP Model...') { import_step }
      file_loaded(__FILE__)
    end
  end
end
