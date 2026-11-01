# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'fileutils'

module N0JCG
  module BlenderMerge
    extend self

    PREF_KEY = 'N0JCG Blender Merge'.freeze
    LEGACY_PREF_KEY = 'N0JCG\BlenderMerge'.freeze
    STL_IMPORT_PREF_KEY = 'CommunityExtensions\STL\Importer'.freeze
    SCRIPT_PATH = File.join(File.dirname(__FILE__), 'merge_union.py').freeze

    def selected_solids(model = Sketchup.active_model)
      selection = model.selection.to_a
      return nil unless selection.length == 2
      return nil unless selection.all? { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
      # Entity#parent returns the Model for top-level instances, not Model#entities.
      return nil unless selection.all? { |entity| entity.parent == model }
      selection
    end

    def import_unit_name
      return 'Millimeters' unless defined?(CommunityExtensions::STL::Importer)
      importer = CommunityExtensions::STL::Importer
      units = Sketchup.read_default(STL_IMPORT_PREF_KEY, 'import_units', importer.const_get(:UNIT_MILLIMETERS))
      return 'Meters' if units == importer.const_get(:UNIT_METERS)
      return 'Centimeters' if units == importer.const_get(:UNIT_CENTIMETERS)
      return 'Millimeters' if units == importer.const_get(:UNIT_MILLIMETERS)
      return 'Feet' if units == importer.const_get(:UNIT_FEET)
      return 'Inches' if units == importer.const_get(:UNIT_INCHES)
      'Millimeters'
    rescue
      'Millimeters'
    end

    def blender_path
      [PREF_KEY, LEGACY_PREF_KEY].each do |key|
        saved = Sketchup.read_default(key, 'blender_path', '')
        if saved && !saved.empty? && File.file?(saved)
          remember_blender_path(saved)
          return saved
        end
      end

      roots = [ENV['ProgramFiles'], ENV['ProgramW6432'], ENV['ProgramFiles(x86)']].compact.uniq
      candidates = roots.inject([]) do |paths, root|
        paths.concat(Dir.glob(File.join(root, 'Blender Foundation', 'Blender *', 'blender.exe')))
        paths
      end
      candidates.select! { |path| File.file?(path) }
      unless candidates.empty?
        selected = candidates.max_by do |path|
          version = path[/Blender\s+([0-9.]+)/i, 1] || '0'
          version.split('.').map { |part| part.to_i }
        end
        remember_blender_path(selected)
        return selected
      end

      selected = UI.openpanel('Locate Blender', nil, 'blender.exe')
      return nil unless selected && File.file?(selected)
      remember_blender_path(selected)
      selected
    end

    def remember_blender_path(path)
      full_path = File.expand_path(path.to_s)
      Sketchup.write_default(PREF_KEY, 'blender_path', full_path)
      Sketchup.write_default(LEGACY_PREF_KEY, 'blender_path', full_path)
      full_path
    end

    def result_health(log)
      return nil unless File.file?(log)
      line = File.readlines(log).reverse.find { |entry| entry =~ /N0JCG_RESULT:/ }
      return nil unless line
      match = line.match(/N0JCG_RESULT:\s+invalid=(\d+)\s+boundary=(\d+)\s+wire=(\d+)\s+overused=(\d+)/)
      return nil unless match
      {
        :invalid => match[1].to_i,
        :boundary => match[2].to_i,
        :wire => match[3].to_i,
        :overused => match[4].to_i
      }
    end

    def quote_arg(value)
      '"' + value.to_s.gsub('"', '\\"') + '"'
    end

    def run_blender(executable, input_a, input_b, output, log)
      command = [
        quote_arg(executable), '--background', '--factory-startup',
        '--python', quote_arg(SCRIPT_PATH), '--',
        quote_arg(input_a), quote_arg(input_b), quote_arg(output)
      ].join(' ')
      command << ' > ' << quote_arg(log) << ' 2>&1'
      system(command)
    end

    def export_stl(path, entity, units)
      unless defined?(CommunityExtensions::STL::Exporter)
        raise 'Enable the SketchUp STL Import & Export extension first.'
      end
      exporter = CommunityExtensions::STL::Exporter
      options = {
        'selection_only' => true,
        'export_units' => units,
        'stl_format' => exporter::STL_BINARY
      }
      exporter.export(path, [entity], options)
      unless File.file?(path) && File.size(path) > 84
        raise "Could not export #{entity.name.empty? ? 'a selected object' : entity.name} to STL."
      end
    end

    def expected_bounds(entities)
      bounds = Geom::BoundingBox.new
      entities.each do |entity|
        8.times { |index| bounds.add(entity.bounds.corner(index)) }
      end
      bounds
    end

    def imported_mesh_health(entity, counts = nil)
      counts ||= { :boundary => 0, :wire => 0, :overused => 0 }
      if entity.is_a?(Sketchup::Edge)
        face_count = entity.faces.length
        counts[:boundary] += 1 if face_count == 1
        counts[:wire] += 1 if face_count == 0
        counts[:overused] += 1 if face_count > 2
      elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.entities.each do |child|
          imported_mesh_health(child, counts)
        end
      end
      counts
    end

    def invalid_edge_count(health)
      health[:boundary] + health[:wire] + health[:overused]
    end

    def downloads_folder
      profile = ENV['USERPROFILE'] || ENV['HOME']
      path = File.join(profile, 'Downloads')
      FileUtils.mkdir_p(path) unless File.directory?(path)
      path
    end

    def unique_output_paths
      stamp = Time.now.strftime('%Y%m%d_%H%M%S')
      directory = downloads_folder
      base = "N0JCG_Merged_#{stamp}"
      stl_path = File.join(directory, base + '.stl')
      suffix = 1
      while File.exist?(stl_path)
        stl_path = File.join(directory, "#{base}_#{suffix}.stl")
        suffix += 1
      end
      log_path = File.join(directory, File.basename(stl_path, '.stl') + '_blender.log')
      [stl_path, log_path]
    end

    SAFE_IMPORT_MIN_EDGE_INCHES = 0.01
    SAFE_IMPORT_MIN_SCALE = 100.0
    SAFE_IMPORT_MAX_SCALE = 10000.0
    SAFE_IMPORT_EDGE_MARGIN = 0.95

    def import_scale_for_stl(path, units)
      unit_scale = case units
      when 'Meters' then 100.0 / 2.54
      when 'Centimeters' then 1.0 / 2.54
      when 'Millimeters' then 0.1 / 2.54
      when 'Feet' then 12.0
      when 'Inches' then 1.0
      else 0.1 / 2.54
      end
      triangle = []
      shortest_edge = nil
      File.foreach(path) do |line|
        fields = line.strip.split
        next unless fields[0] == 'vertex'
        raise 'Invalid vertex record in Blender STL output.' unless fields.length == 4
        triangle << Geom::Point3d.new(fields[1].to_f * unit_scale, fields[2].to_f * unit_scale, fields[3].to_f * unit_scale)
        if triangle.length == 3
          3.times do |index|
            edge = triangle[index].distance(triangle[(index + 1) % 3])
            shortest_edge = edge if edge > 0.0 && (!shortest_edge || edge < shortest_edge)
          end
          triangle.clear
        end
      end
      raise 'Blender STL output contains no measurable triangles.' unless shortest_edge && shortest_edge > 0.0

      conservative_edge = shortest_edge * SAFE_IMPORT_EDGE_MARGIN
      scale_factor = [SAFE_IMPORT_MIN_EDGE_INCHES / conservative_edge, SAFE_IMPORT_MIN_SCALE].max
      scale_factor = [scale_factor, SAFE_IMPORT_MAX_SCALE].min
      if shortest_edge * scale_factor <= 0.001
        raise 'The merged STL contains edges too small for SketchUp to import safely.'
      end
      [scale_factor, shortest_edge]
    end

    def write_scaled_ascii_stl(source, destination, scale_factor)
      File.open(destination, 'w') do |output|
        File.foreach(source) do |line|
          fields = line.strip.split
          if fields[0] == 'vertex'
            raise 'Invalid vertex record in Blender STL output.' unless fields.length == 4
            indent = line[/\A\s*/]
            coords = fields[1..3].map { |value| format('%.9g', value.to_f * scale_factor) }
            output.puts(indent + 'vertex ' + coords.join(' '))
          else
            output.write(line)
          end
        end
      end
      raise 'Could not create the scaled STL for SketchUp import.' unless File.file?(destination) && File.size(destination) > 84
    end

    def import_union_stl(model, path, units)
      factor, shortest_edge = import_scale_for_stl(path, units)
      scaled_path = path.sub(/\.stl\z/i, '_scaled_for_import.stl')
      write_scaled_ascii_stl(path, scaled_path, factor)
      begin
        unless defined?(CommunityExtensions::STL::Importer)
          raise 'Enable SketchUp’s STL Import & Export extension first.'
        end

        before = model.entities.to_a
        Sketchup.status_text = 'Importing Blender union STL...'
        importer = CommunityExtensions::STL::Importer.new
        import_result = importer.load_file(scaled_path, nil)
        unless import_result == CommunityExtensions::STL::Importer::IMPORT_SUCCESS
          raise 'SketchUp’s STL importer did not complete the import.'
        end

        added = model.entities.to_a - before
        raise 'The STL importer did not add any geometry.' if added.empty?
        result = added.find { |entity| entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) }
        result ||= model.entities.add_group(added)
        result.name = 'Blender Union' if result.respond_to?(:name=)
        if factor != 1.0
          result.transform!(Geom::Transformation.scaling(Geom::Point3d.new(0, 0, 0), 1.0 / factor))
        end
        model.selection.clear
        model.selection.add(result)

        cleanup_note = if defined?(TT::Plugins::CleanUp) && TT::Plugins::CleanUp.respond_to?(:cleanup_last)
          begin
            TT::Plugins::CleanUp.cleanup_last
            'CleanUp³ was run on the imported group with its saved settings.'
          rescue => cleanup_error
            "CleanUp³ could not run: #{cleanup_error.message}"
          end
        else
          'CleanUp³ is not loaded; no cleanup was run.'
        end

        model.selection.clear
        model.selection.add(result) if result.valid?
        health = imported_mesh_health(result)
        problem_count = invalid_edge_count(health)
        status = if problem_count.zero?
          'The imported geometry has no boundary, loose, or overused edges.'
        else
          "SketchUp reports #{problem_count} problem edges (open boundaries: #{health[:boundary]}, " +
            "loose edges: #{health[:wire]}, edges with more than 2 faces: #{health[:overused]})."
        end
        Sketchup.active_model.active_view.zoom_extents
        [cleanup_note, status, factor, shortest_edge]
      ensure
        File.delete(scaled_path) if File.file?(scaled_path)
      end
    end

    def merge
      model = Sketchup.active_model
      unless model && model.active_path.nil?
        UI.messagebox('Close any open group/component edit context, then select two top-level groups or components.')
        return
      end
      objects = selected_solids(model)
      unless objects
        UI.messagebox('Select exactly two top-level groups or component instances to merge.')
        return
      end
      unless defined?(CommunityExtensions::STL::Exporter) && defined?(CommunityExtensions::STL::Importer)
        UI.messagebox('Enable the signed STL Import & Export extension before using Blender Merge.')
        return
      end

      blender = blender_path
      return unless blender
      unless File.file?(SCRIPT_PATH)
        UI.messagebox("The Blender merge helper is missing:\n#{SCRIPT_PATH}")
        return
      end

      temp_dir = File.join(ENV['TEMP'] || ENV['TMP'] || Sketchup.temp_dir, "n0jcg_blender_merge_#{Time.now.to_i}_#{rand(100000)}")
      Dir.mkdir(temp_dir)
      input_a = File.join(temp_dir, 'part_a.stl')
      input_b = File.join(temp_dir, 'part_b.stl')
      output = File.join(temp_dir, 'merged.stl')
      log = File.join(temp_dir, 'blender.log')
      units = import_unit_name

      begin
        export_stl(input_a, objects[0], units)
        export_stl(input_b, objects[1], units)
        Sketchup.status_text = 'Merging selected objects with Blender...'
        unless run_blender(blender, input_a, input_b, output, log) && File.file?(output) && File.size(output) > 84
          details = File.file?(log) ? File.readlines(log).last(12).join : 'Blender did not create an output STL.'
          raise "Blender union failed.\n\n#{details}\n\nDiagnostic log: #{log}"
        end

        health = result_health(log)
        raise "Blender did not report the merged mesh status. Diagnostic log: #{log}" unless health
        saved_stl, saved_log = unique_output_paths
        FileUtils.cp(output, saved_stl)
        FileUtils.cp(log, saved_log) if File.file?(log)
        Sketchup.status_text = 'Importing Blender union into SketchUp...'
        cleanup_note, import_status, import_scale, shortest_edge = import_union_stl(model, saved_stl, units)
        detail = if health[:invalid] > 0
          "Blender reports #{health[:invalid]} non-manifold edges (open boundaries: #{health[:boundary]}, " +
            "loose edges: #{health[:wire]}, edges with more than 2 faces: #{health[:overused]})."
        else
          'Blender reports a manifold result after its STL round trip.'
        end
        UI.messagebox(
          "Blender union was imported automatically at #{format('%.1f', import_scale)}x internal scale, then restored to its original size.\n" +
          "Shortest STL edge: #{format('%.8f', shortest_edge)} inches before compensation.\n" +
          "Saved STL: #{saved_stl}\n\n#{detail}\n" +
          "#{cleanup_note}\n#{import_status}\n\n" +
          "Original SketchUp objects were left unchanged; the new union group is selected.\n\nDiagnostic log:\n#{saved_log}"
        )
        FileUtils.remove_entry(temp_dir) if File.directory?(temp_dir)
      rescue => error
        Sketchup.status_text = ''
        UI.messagebox("Blender Merge failed:\n#{error.message}")
      ensure
        Sketchup.status_text = ''
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('N0JCG Blender Merge')
      menu.add_item('Merge Two Selected Objects (Union)') { merge }
      UI.add_context_menu_handler do |context_menu|
        context_menu.add_item('Merge Two Selected Objects (Union)') { merge } if selected_solids
      end
      file_loaded(__FILE__)
    end
  end
end
