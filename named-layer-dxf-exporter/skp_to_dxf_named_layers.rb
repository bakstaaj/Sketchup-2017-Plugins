# SketchUp DXF exporter with SketchUp tag names preserved as DXF layers.
# Duplicate of the installed SketchUp to DXF/STL converter, isolated in its
# own module so it can run beside the original plugin.
# Version 1.4.3
# Targets SketchUp 2017 / Ruby 2.2.

require 'sketchup.rb'

module N0JCG
  module NamedDXFExporter
    MENU_NAME = 'Export DXF with Named Layers'.freeze
    UNTAGGED = 'Untagged'.freeze
    DXF_DEFAULT_LAYER = '0'.freeze
    WIRE_MODE = 'circles and polylines'.freeze
    WORKSPACE_GRID_GROUP = 'Fusion Workplane Grid'.freeze

    MODES = ['polyface mesh', 'polylines', 'triangular mesh', 'lines', WIRE_MODE].freeze
    ORIGIN_CHOICES = ['Model origin', 'Select point'].freeze
    UNITS = ['Meters', 'Centimeters', 'Millimeters', 'Inches', 'Feet'].freeze

    def self.export
      model = Sketchup.active_model
      selection = model.selection

      if selection.empty?
        answer = UI.messagebox('No objects selected. Export the entire model?', MB_YESNOCANCEL)
        return unless answer == 6
        entities = model.entities.to_a
      else
        entities = selection.to_a
      end
      return if entities.empty?

      unit = choose_units(model)
      return unless unit
      options = choose_mode(entities)
      return unless options
      mode, origin_choice = options

      if origin_choice == 'Select point'
        Sketchup.status_text = 'Click the point to use as DXF origin (0,0,0). Press Esc to cancel.'
        callback = proc do |origin|
          run_export(model, entities, unit, mode, origin)
        end
        model.select_tool(OriginPicker.new(callback))
      else
        run_export(model, entities, unit, mode, Geom::Point3d.new(0, 0, 0))
      end
    rescue => error
      UI.messagebox("Named-layer DXF export failed:\n#{error.message}", MB_MULTILINE)
    end

    def self.run_export(model, entities, unit, mode, origin)
      started = false
      return if @run_export_active
      @run_export_active = true
      started = true

      base_name = File.basename(model.path.to_s, File.extname(model.path.to_s))
      base_name = 'untitled' if base_name.empty?
      path = UI.savepanel('DXF file location', '', "#{base_name}.dxf")
      return unless path
      path += '.dxf' if File.extname(path).empty?

      @scale = unit_scale(unit)
      @mode = mode
      @face_count = 0
      @line_count = 0
      @polyline_count = 0
      @circle_count = 0
      @ignored_count = 0
      @scan_count = 0
      @container_count = 0
      @scan_types = Hash.new(0)
      @face_entities_count = 0
      @edge_entities_count = 0
      @automatic_wire_mode = false
      @layer_names = {}
      @layer_name_lookup = {}
      @used_dxf_names = { DXF_DEFAULT_LAYER.downcase => nil }

      collect_layers(entities, DXF_DEFAULT_LAYER)
      if @mode != 'lines' && @mode != WIRE_MODE && @face_entities_count == 0 && @edge_entities_count > 0
        @mode = WIRE_MODE
        @automatic_wire_mode = true
        @layer_names = {}
        @layer_name_lookup = {}
        @used_dxf_names = { DXF_DEFAULT_LAYER.downcase => nil }
        @face_entities_count = 0
        @edge_entities_count = 0
        collect_layers(entities, DXF_DEFAULT_LAYER)
      end

      File.open(path, 'w') do |file|
        @file = file
        write_document_header
        origin_offset = Geom::Vector3d.new(-origin.x, -origin.y, -origin.z)
        export_transform = Geom::Transformation.translation(origin_offset)
        export_entities(entities, export_transform, DXF_DEFAULT_LAYER)
        write_document_footer
      end
      @file = nil

      if @face_count == 0 && @line_count == 0 && @polyline_count == 0 && @circle_count == 0
        type_summary = @scan_types.map { |type, count| "#{type}: #{count}" }.join(', ')
        type_summary = 'none' if type_summary.empty?
        UI.messagebox("No DXF geometry was written.\n\nEntities scanned: #{@scan_count}\nGroups/components opened: #{@container_count}\nEntity types: #{type_summary}\n\nSelect faces, edges, groups, or components containing geometry and retry.")
        return
      end

      notice = @automatic_wire_mode ? "\nThe selection contained edges only, so circles and connected edges were exported as DXF circles and polylines.\n" : ''
      geometry_summary = if @mode == WIRE_MODE
                           "#{@circle_count} circles exported\n#{@polyline_count} polylines exported"
                         else
                           "#{@face_count} faces exported\n#{@line_count} lines exported"
                         end
      UI.messagebox("DXF export complete.\n#{notice}\n#{geometry_summary}\n#{@ignored_count} objects ignored\n\nExport origin: #{origin.x}, #{origin.y}, #{origin.z} inches (SketchUp internal coordinates)\nSketchUp tags are written as DXF layers.")
    rescue => error
      @file = nil
      UI.messagebox("Named-layer DXF export failed:\n#{error.message}", MB_MULTILINE)
    ensure
      @run_export_active = false if started
    end

    def self.choose_units(model)
      current = model.options['UnitsOptions']['LengthUnit']
      current_unit = case current
                     when 4 then 'Meters'
                     when 3 then 'Centimeters'
                     when 2 then 'Millimeters'
                     when 1 then 'Feet'
                     else 'Inches'
                     end
      result = UI.inputbox(['Export unit:'], [current_unit], [UNITS.join('|')], 'DXF export units')
      result && result[0]
    end

    def self.choose_mode(entities)
      result = UI.inputbox(
        ['Export geometry as:', 'Export origin:'],
        ['polylines', 'Select point'],
        [MODES.join('|'), ORIGIN_CHOICES.join('|')],
        'DXF export options'
      )
      result
    end

    def self.geometry_counts(entities, counts = { :faces => 0, :edges => 0 })
      entities.each do |entity|
        next if workspace_grid?(entity)
        type = entity_type(entity)
        if type == 'Group' || type == 'ComponentInstance'
          definition_entities = type == 'Group' ? entity.entities : entity.definition.entities
          geometry_counts(definition_entities, counts)
        elsif type == 'Face'
          counts[:faces] += 1
        elsif type == 'Edge'
          counts[:edges] += 1
        end
      end
      counts
    end

    def self.unit_scale(unit)
      case unit
      when 'Meters' then 0.0254
      when 'Centimeters' then 2.54
      when 'Millimeters' then 25.4
      when 'Feet' then 1.0 / 12.0
      else 1.0
      end
    end

    # A tagged group/component supplies the inherited layer for its contents.
    # Explicit tags on nested entities override that inherited tag. Untagged
    # top-level geometry is sent to DXF layer 0.
    def self.effective_layer(entity, inherited)
      name = entity.layer.name
      name == UNTAGGED ? inherited : name
    end

    def self.entity_type(entity)
      entity.typename
    rescue
      entity.class.name.to_s.split('::').last
    end

    def self.workspace_grid?(entity)
      entity_type(entity) == 'Group' && entity.name == WORKSPACE_GRID_GROUP
    rescue
      false
    end

    def self.collect_layers(entities, inherited)
      entities.each do |entity|
        next if workspace_grid?(entity)
        type = entity_type(entity)
        if type == 'Group' || type == 'ComponentInstance'
          layer = effective_layer(entity, inherited)
          definition_entities = type == 'Group' ? entity.entities : entity.definition.entities
          collect_layers(definition_entities, layer)
        elsif type == 'Face'
          @face_entities_count += 1
          if @mode != 'lines' && @mode != WIRE_MODE
            register_layer(effective_layer(entity, inherited))
          end
        elsif type == 'Edge'
          @edge_entities_count += 1
          if @mode == 'lines' || @mode == WIRE_MODE || entity.faces.empty?
            register_layer(effective_layer(entity, inherited))
          end
        end
      end
    end

    def self.register_layer(sketchup_name)
      return DXF_DEFAULT_LAYER if sketchup_name == UNTAGGED || sketchup_name.to_s.empty?
      return @layer_name_lookup[sketchup_name] if @layer_name_lookup[sketchup_name]

      dxf_name = safe_layer_name(sketchup_name)
      key = dxf_name.downcase
      if @used_dxf_names.key?(key) && @used_dxf_names[key] != sketchup_name
        suffix = 2
        base = dxf_name
        while @used_dxf_names.key?("#{base}_#{suffix}".downcase)
          suffix += 1
        end
        dxf_name = "#{base}_#{suffix}"
        key = dxf_name.downcase
      end
      @used_dxf_names[key] = sketchup_name
      @layer_name_lookup[sketchup_name] = dxf_name
      @layer_names[sketchup_name] = dxf_name
    end

    def self.safe_layer_name(name)
      # AutoCAD disallows these characters in layer names. Keep ordinary names
      # and spaces intact, replacing unsupported characters with underscores.
      cleaned = name.to_s.encode('ASCII', :invalid => :replace, :undef => :replace, :replace => '_')
      cleaned = cleaned.gsub(/[<>\\\/";:?*|=']/, '_').strip
      cleaned = 'Layer' if cleaned.empty?
      cleaned[0, 255]
    end

    def self.dxf_layer(sketchup_name)
      return DXF_DEFAULT_LAYER if sketchup_name == UNTAGGED || sketchup_name.to_s.empty?
      @layer_names[sketchup_name] || register_layer(sketchup_name)
    end

    def self.write_document_header
      @file.puts("0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC")
      @file.puts("0\nSECTION\n2\nTABLES")
      @file.puts("0\nTABLE\n2\nLTYPE\n70\n1")
      @file.puts("0\nLTYPE\n2\nCONTINUOUS\n70\n0\n3\nSolid line\n72\n65\n73\n0\n40\n0.0")
      @file.puts("0\nENDTAB")
      names = [DXF_DEFAULT_LAYER] + @layer_names.values.uniq
      @file.puts("0\nTABLE\n2\nLAYER\n70\n#{names.length}")
      names.each do |name|
        @file.puts("0\nLAYER\n2\n#{name}\n70\n0\n62\n7\n6\nCONTINUOUS")
      end
      @file.puts("0\nENDTAB\n0\nENDSEC")
      @file.puts("0\nSECTION\n2\nBLOCKS\n0\nENDSEC")
      @file.puts("0\nSECTION\n2\nENTITIES")
    end

    def self.write_document_footer
      @file.puts("0\nENDSEC\n0\nEOF")
    end

    def self.export_entities(entities, transformation, inherited_layer)
      wire_edges = []
      entities.each do |entity|
        next if workspace_grid?(entity)
        type = entity_type(entity)
        @scan_count += 1
        @scan_types[type] += 1
        layer = effective_layer(entity, inherited_layer)
        if type == 'Group' || type == 'ComponentInstance'
          @container_count += 1
          definition_entities = type == 'Group' ? entity.entities : entity.definition.entities
          export_entities(definition_entities, transformation * entity.transformation, layer)
        elsif type == 'Face'
          if @mode == 'polylines'
            write_face_polylines(entity, transformation, dxf_layer(layer))
          elsif @mode == 'triangular mesh'
            write_face_mesh(entity, transformation, dxf_layer(layer), false)
          elsif @mode == 'polyface mesh'
            write_face_mesh(entity, transformation, dxf_layer(layer), true)
          end
        elsif type == 'Edge'
          if @mode == WIRE_MODE
            wire_edges << [entity, layer]
          elsif @mode == 'lines' || entity.faces.empty?
            write_line(entity, transformation, dxf_layer(layer))
          end
        else
          @ignored_count += 1
        end
      end
      write_edge_paths(wire_edges, transformation) if @mode == WIRE_MODE
    end

    def self.transformed(point, transformation)
      result = Geom::Point3d.new(point.x, point.y, point.z)
      result.transform!(transformation)
      result
    end

    def self.write_line(edge, transformation, layer)
      start_point = transformed(edge.start.position, transformation)
      end_point = transformed(edge.end.position, transformation)
      @file.puts("0\nLINE\n8\n#{layer}")
      write_point(10, start_point)
      write_point(11, end_point)
      @line_count += 1
    end

    def self.write_edge_paths(items, transformation)
      items.group_by { |edge, layer| dxf_layer(layer) }.each do |layer, layer_items|
        edges = layer_items.map { |item| item[0] }
        remaining = edges.dup

        edges.each do |edge|
          next unless remaining.include?(edge)
          curve = edge.curve
          next unless curve

          curve_edges = curve.edges.select { |curve_edge| remaining.include?(curve_edge) }
          next unless curve_edges.length == curve.edges.length

          if full_circle_curve?(curve) && write_circle(curve, transformation, layer)
            remaining -= curve_edges
          else
            @polyline_count += write_chained_polylines(curve_edges, transformation, layer)
            remaining -= curve_edges
          end
        end

        @polyline_count += write_chained_polylines(remaining, transformation, layer)
      end
    end

    def self.full_circle_curve?(curve)
      return false unless curve.typename == 'ArcCurve'
      edges = curve.edges
      return false if edges.length < 3

      endpoint_count = Hash.new(0)
      edges.each do |edge|
        endpoint_count[edge.start.entityID] += 1
        endpoint_count[edge.end.entityID] += 1
      end
      endpoint_count.values.all? { |count| count == 2 }
    end

    def self.transformed_vector(vector, transformation)
      origin = transformed(Geom::Point3d.new(0, 0, 0), transformation)
      tip = transformed(Geom::Point3d.new(vector.x, vector.y, vector.z), transformation)
      Geom::Vector3d.new(tip.x - origin.x, tip.y - origin.y, tip.z - origin.z)
    end

    def self.write_circle(curve, transformation, layer)
      x_axis = transformed_vector(curve.xaxis, transformation)
      y_axis = transformed_vector(curve.yaxis, transformation)
      x_length = x_axis.length
      y_length = y_axis.length
      return false if x_length <= 0.0 || y_length <= 0.0
      tolerance = [x_length, y_length].max * 1.0e-6
      return false if (x_length - y_length).abs > tolerance
      return false if x_axis.dot(y_axis).abs > x_length * y_length * 1.0e-6

      normal = x_axis.cross(y_axis)
      return false if normal.length <= 0.0
      normal.normalize!
      center = transformed(curve.center, transformation)
      world_y = Geom::Vector3d.new(0, 1, 0)
      world_z = Geom::Vector3d.new(0, 0, 1)
      ocs_x = if normal.x.abs < (1.0 / 64.0) && normal.y.abs < (1.0 / 64.0)
                world_y.cross(normal)
              else
                world_z.cross(normal)
              end
      return false if ocs_x.length <= 0.0
      ocs_x.normalize!
      ocs_y = normal.cross(ocs_x)
      ocs_y.normalize!

      write_dxf_circle(center, (x_length + y_length) / 2.0, normal, ocs_x, ocs_y, layer)
    end

    def self.write_dxf_circle(center, radius, normal, ocs_x, ocs_y, layer)
      center_x = center.x * ocs_x.x + center.y * ocs_x.y + center.z * ocs_x.z
      center_y = center.x * ocs_y.x + center.y * ocs_y.y + center.z * ocs_y.z
      center_z = center.x * normal.x + center.y * normal.y + center.z * normal.z

      @file.puts("0\nCIRCLE\n8\n#{layer}")
      @file.puts("10\n#{center_x.to_f * @scale}")
      @file.puts("20\n#{center_y.to_f * @scale}")
      @file.puts("30\n#{center_z.to_f * @scale}")
      @file.puts("40\n#{radius.to_f * @scale}")
      @file.puts("210\n#{normal.x}\n220\n#{normal.y}\n230\n#{normal.z}")
      @circle_count += 1
      true
    end

    def self.write_fitted_circle(points, layer)
      return false if points.length < 12
      origin = points[0]
      center_data = nil

      (1...points.length - 1).each do |first_index|
        first = subtract_points(points[first_index], origin)
        ((first_index + 1)...points.length).each do |second_index|
          second = subtract_points(points[second_index], origin)
          normal_data = vector_cross(first, second)
          normal_length = vector_length(normal_data)
          next if normal_length <= 1.0e-12
          denominator = 2.0 * normal_length * normal_length
          first_term = vector_scale(vector_cross(second, normal_data), vector_dot(first, first))
          second_term = vector_scale(vector_cross(normal_data, first), vector_dot(second, second))
          offset = vector_scale(vector_add(first_term, second_term), 1.0 / denominator)
          center_data = [origin.x + offset[0], origin.y + offset[1], origin.z + offset[2], normal_data, normal_length]
          break
        end
        break if center_data
      end
      return false unless center_data

      center = Geom::Point3d.new(center_data[0], center_data[1], center_data[2])
      normal = Geom::Vector3d.new(*center_data[3])
      normal.normalize!
      radius = center.distance(origin)
      return false if radius <= 0.0

      tolerance = [radius * 1.0e-3, 1.0e-6].max
      points.each do |point|
        offset = subtract_points(point, origin)
        planar_error = vector_dot(offset, [normal.x, normal.y, normal.z]).abs
        radial_error = (center.distance(point) - radius).abs
        return false if planar_error > tolerance || radial_error > tolerance
      end

      world_y = Geom::Vector3d.new(0, 1, 0)
      world_z = Geom::Vector3d.new(0, 0, 1)
      ocs_x = if normal.x.abs < (1.0 / 64.0) && normal.y.abs < (1.0 / 64.0)
                world_y.cross(normal)
              else
                world_z.cross(normal)
              end
      return false if ocs_x.length <= 0.0
      ocs_x.normalize!
      ocs_y = normal.cross(ocs_x)
      ocs_y.normalize!
      write_dxf_circle(center, radius, normal, ocs_x, ocs_y, layer)
    end

    def self.subtract_points(a, b)
      [a.x - b.x, a.y - b.y, a.z - b.z]
    end

    def self.vector_dot(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def self.vector_cross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end

    def self.vector_add(a, b)
      [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
    end

    def self.vector_scale(vector, factor)
      [vector[0] * factor, vector[1] * factor, vector[2] * factor]
    end

    def self.vector_length(vector)
      Math.sqrt(vector_dot(vector, vector))
    end

    def self.write_chained_polylines(edges, transformation, layer)
      paths = chained_edge_paths(edges)
      polyline_count = 0
      paths.each do |points, closed|
        next if points.length < 2
        world_points = points.map { |point| transformed(point, transformation) }
        next if closed && write_fitted_circle(world_points, layer)

        flags = closed ? 9 : 8
        @file.puts("0\nPOLYLINE\n8\n#{layer}\n66\n1\n70\n#{flags}\n10\n0.0\n20\n0.0\n30\n0.0")
        world_points.each do |world_point|
          @file.puts("0\nVERTEX\n8\n#{layer}\n70\n32")
          write_point(10, world_point)
        end
        @file.puts("0\nSEQEND\n8\n#{layer}")
        polyline_count += 1
      end
      polyline_count
    end

    def self.chained_edge_paths(edges)
      adjacency = Hash.new { |hash, key| hash[key] = [] }
      vertices = {}
      edges.each do |edge|
        start_vertex = edge.start
        end_vertex = edge.end
        start_id = start_vertex.entityID
        end_id = end_vertex.entityID
        adjacency[start_id] << edge
        adjacency[end_id] << edge
        vertices[start_id] = start_vertex
        vertices[end_id] = end_vertex
      end
      original_degree = {}
      adjacency.each { |vertex_id, connected| original_degree[vertex_id] = connected.length }

      remaining = edges.dup
      paths = []
      until remaining.empty?
        start_id = nil
        remaining.each do |edge|
          [edge.start.entityID, edge.end.entityID].each do |vertex_id|
            if original_degree[vertex_id] != 2
              start_id = vertex_id
              break
            end
          end
          break if start_id
        end
        start_id ||= remaining.first.start.entityID

        points = [vertices[start_id].position]
        current_id = start_id
        closed = false
        loop do
          edge = adjacency[current_id].find { |candidate| remaining.include?(candidate) }
          break unless edge
          remaining.delete(edge)
          next_vertex = edge.start.entityID == current_id ? edge.end : edge.start
          next_id = next_vertex.entityID
          if next_id == start_id
            closed = true
            break
          end
          points << next_vertex.position
          current_id = next_id
          break if original_degree[current_id] != 2
        end
        paths << [points, closed]
      end
      paths
    end

    def self.write_point(code, point)
      @file.puts("#{code}\n#{point.x.to_f * @scale}")
      @file.puts("#{code + 10}\n#{point.y.to_f * @scale}")
      @file.puts("#{code + 20}\n#{point.z.to_f * @scale}")
    end

    def self.write_face_polylines(face, transformation, layer)
      face.loops.each do |loop|
        vertices = loop.vertices
        next if vertices.length < 2
        flags = 9 # 3D polyline and closed polyline
        @file.puts("0\nPOLYLINE\n8\n#{layer}\n66\n1\n70\n#{flags}\n10\n0.0\n20\n0.0\n30\n0.0")
        vertices.each do |vertex|
          point = transformed(vertex.position, transformation)
          @file.puts("0\nVERTEX\n8\n#{layer}\n70\n32")
          write_point(10, point)
        end
        @file.puts("0\nSEQEND\n8\n#{layer}")
        @face_count += 1
      end
    end

    def self.write_face_mesh(face, transformation, layer, polyface)
      mesh = face.mesh(0)
      mesh.transform!(transformation)
      polygons = mesh.polygons.select { |polygon| polygon.length >= 3 }
      return if polygons.empty?

      if polyface
        write_polyface(mesh.points, polygons, layer)
      else
        polygons.each do |polygon|
          indices = polygon.map { |index| index.abs }
          triangles = indices.length == 3 ? [indices] : [[indices[0], indices[1], indices[2]], [indices[0], indices[2], indices[3]]]
          triangles.each do |triangle|
            points = triangle.map { |index| mesh.point_at(index) }
            write_3dface(points, layer)
          end
        end
      end
      @face_count += 1
    end

    def self.write_3dface(points, layer)
      points = points.dup
      points << points.last while points.length < 4
      points = points[0, 4]
      @file.puts("0\n3DFACE\n8\n#{layer}")
      points.each_with_index { |point, index| write_point(10 + index, scaled_point(point)) }
      @file.puts("70\n0")
    end

    def self.write_polyface(points, polygons, layer)
      @file.puts("0\nPOLYLINE\n8\n#{layer}\n66\n1\n70\n64\n10\n0.0\n20\n0.0\n30\n0.0")
      points.each do |point|
        @file.puts("0\nVERTEX\n8\n#{layer}\n70\n192")
        write_point(10, scaled_point(point))
      end
      polygons.each do |polygon|
        indices = polygon.map { |index| index < 0 ? -index.abs : index.abs }
        indices = indices[0, 4]
        @file.puts("0\nVERTEX\n8\n#{layer}\n70\n128")
        indices.each_with_index do |index, position|
          @file.puts("#{71 + position}\n#{index}")
        end
      end
      @file.puts("0\nSEQEND\n8\n#{layer}")
    end

    def self.scaled_point(point)
      Geom::Point3d.new(point.x.to_f * @scale, point.y.to_f * @scale, point.z.to_f * @scale)
    end

    class OriginPicker
      def initialize(callback)
        @callback = callback
        @input_point = Sketchup::InputPoint.new
        @completed = false
      end

      def onMouseMove(flags, x, y, view)
        @input_point.pick(view, x, y)
        if @input_point.valid?
          Sketchup.status_text = "Click to set export origin: #{@input_point.tooltip}"
        else
          Sketchup.status_text = 'Click the point to use as DXF origin (0,0,0). Press Esc to cancel.'
        end
        view.invalidate
      end

      def draw(view)
        @input_point.draw(view) if @input_point.valid?
      end

      def onLButtonDown(flags, x, y, view)
        return if @completed
        @input_point.pick(view, x, y)
        return unless @input_point.valid?

        @completed = true
        origin = @input_point.position
        callback = @callback
        @callback = nil
        Sketchup.active_model.select_tool(nil)
        Sketchup.status_text = ''
        UI.start_timer(0.1, false) { callback.call(origin) if callback }
      end

      def onCancel(reason, view)
        Sketchup.status_text = ''
      end
    end

    unless file_loaded?(__FILE__)
      UI.menu('File').add_item(MENU_NAME) { export }
      UI.menu('Tools').add_item(MENU_NAME) { export }
      file_loaded(__FILE__)
    end
  end
end
