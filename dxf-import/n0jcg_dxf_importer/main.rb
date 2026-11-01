# Copyright 2026 N0JCG. Released under the MIT License.
# ASCII DXF importer for SketchUp 2017 / Ruby 2.2.
require 'sketchup.rb'

module N0JCG
  module DXFImport
    extend self

    PREF_KEY = 'N0JCG DXF Import'.freeze
    UNIT_CHOICES = ['Millimeters', 'Inches', 'Centimeters', 'Meters', 'Feet', 'Model Units'].freeze
    DEFAULT_SEGMENTS = 48

    def import_dxf
      path = UI.openpanel('Import DXF file', nil, 'DXF Files|*.dxf||')
      return unless path
      unless File.file?(path)
        UI.messagebox('The selected DXF file could not be found.')
        return
      end

      default_unit = Sketchup.read_default(PREF_KEY, 'units', 'Millimeters')
      default_unit = 'Millimeters' unless UNIT_CHOICES.include?(default_unit)
      result = UI.inputbox(['DXF units:'], [default_unit], [UNIT_CHOICES.join('|')], 'DXF import options')
      return unless result
      unit = result[0]
      Sketchup.write_default(PREF_KEY, 'units', unit)

      model = Sketchup.active_model
      pairs = read_pairs(path)
      records = entity_records(pairs)
      raise 'No supported entities were found in the DXF ENTITIES section.' if records.empty?

      model.start_operation('Import DXF', true)
      begin
        @model = model
        @scale = unit_scale(unit, model)
        @layer_groups = {}
        @counts = Hash.new(0)
        records.each { |record| import_record(record) }
        groups = @layer_groups.values
        imported_count = @counts.values.inject(0) { |sum, count| sum + count }
        if groups.empty? || imported_count == 0
          model.abort_operation
          UI.messagebox('No supported geometry could be imported from this DXF file.')
          return
        end
        model.selection.clear
        groups.each { |group| model.selection.add(group) }
        model.commit_operation
        model.active_view.invalidate
        summary = @counts.keys.sort.map { |type| "#{type}: #{@counts[type]}" }.join("\n")
        UI.messagebox("DXF import complete.\n\n#{summary}\n\nDXF layers were imported as SketchUp tags.")
      rescue
        model.abort_operation
        raise
      ensure
        @model = nil
        @layer_groups = nil
        @counts = nil
      end
    rescue => error
      UI.messagebox("DXF import failed:\n#{error.message}", MB_MULTILINE)
    end

    def read_pairs(path)
      lines = File.open(path, 'rb') { |file| file.readlines }
      raise 'This importer requires an ASCII DXF file.' if lines.length < 2
      raise 'The DXF file has an incomplete group-code/value pair.' if lines.length.odd?
      pairs = []
      index = 0
      while index < lines.length
        code = lines[index].to_s.strip.to_i
        pairs << [code, lines[index + 1].to_s.strip]
        index += 2
      end
      pairs
    end

    def entity_records(pairs)
      start = nil
      pairs.each_with_index do |pair, index|
        if pair[0] == 0 && pair[1].upcase == 'SECTION' && pairs[index + 1] && pairs[index + 1][0] == 2 && pairs[index + 1][1].upcase == 'ENTITIES'
          start = index + 2
          break
        end
      end
      raise 'The DXF file has no ENTITIES section.' unless start

      finish = start
      finish += 1 while finish < pairs.length && !(pairs[finish][0] == 0 && pairs[finish][1].upcase == 'ENDSEC')
      section = pairs[start...finish]
      records = []
      index = 0
      while index < section.length
        unless section[index][0] == 0
          index += 1
          next
        end
        type = section[index][1].upcase
        index += 1
        data = []
        while index < section.length && section[index][0] != 0
          data << section[index]
          index += 1
        end
        record = { :type => type, :data => data, :vertices => [] }
        if type == 'POLYLINE'
          while index < section.length && section[index][0] == 0 && section[index][1].upcase == 'VERTEX'
            index += 1
            vertex_data = []
            while index < section.length && section[index][0] != 0
              vertex_data << section[index]
              index += 1
            end
            record[:vertices] << vertex_data
          end
          if index < section.length && section[index][0] == 0 && section[index][1].upcase == 'SEQEND'
            index += 1
            index += 1 while index < section.length && section[index][0] != 0
          end
        end
        records << record
      end
      records
    end

    def import_record(record)
      type = record[:type]
      data = record[:data]
      layer_name = value(data, 8, '0')
      case type
      when 'LINE'
        entities = layer_entities(layer_name)
        a = point(data, 10)
        b = point(data, 11)
        add_line(entities, a, b)
      when 'CIRCLE'
        entities = layer_entities(layer_name)
        center, normal, x_axis = ocs(data)
        radius = number(data, 40, 0.0) * @scale
        return if radius <= 0.0
        entities.add_circle(center, normal, radius, DEFAULT_SEGMENTS)
        @counts['Circles'] += 1
      when 'ARC'
        entities = layer_entities(layer_name)
        import_arc(entities, data)
      when 'LWPOLYLINE'
        entities = layer_entities(layer_name)
        import_lwpolyline(entities, data)
      when 'POLYLINE'
        entities = layer_entities(layer_name)
        import_polyline(entities, record)
      when '3DFACE'
        entities = layer_entities(layer_name)
        import_3dface(entities, data)
      else
        @counts['Skipped entities'] += 1
      end
    end

    def layer_entities(name)
      key = name.to_s.empty? ? '0' : name.to_s
      return @layer_groups[key].entities if @layer_groups[key]

      tag = @model.layers[key] || @model.layers.add(key)
      group = @model.entities.add_group
      group.name = "DXF - #{key}"
      group.layer = tag
      @layer_groups[key] = group
      group.entities
    end

    def import_polyline(entities, record)
      header = record[:data]
      flags = number(header, 70, 0).to_i
      vertices = record[:vertices]
      if (flags & 64) != 0
        import_polyface(entities, vertices)
        return
      end
      points = vertices.map { |data| point(data, 10) }.compact
      return if points.length < 2
      closed = (flags & 1) != 0
      points << points.first if closed && points.last.distance(points.first) > 1.0e-8
      entities.add_curve(points)
      @counts['Polylines'] += 1
    end

    def import_lwpolyline(entities, data)
      elevation = number(data, 38, 0.0) * @scale
      vertices = []
      current = nil
      data.each do |code, text|
        if code == 10
          vertices << current if current
          current = { :x => text.to_f, :y => 0.0, :bulge => 0.0 }
        elsif code == 20 && current
          current[:y] = text.to_f
        elsif code == 42 && current
          current[:bulge] = text.to_f
        end
      end
      vertices << current if current
      return if vertices.length < 2
      flags = number(data, 70, 0).to_i
      closed = (flags & 1) != 0
      points = []
      segment_count = closed ? vertices.length : vertices.length - 1
      segment_count.times do |index|
        first = vertices[index]
        second = vertices[(index + 1) % vertices.length]
        points << Geom::Point3d.new(first[:x] * @scale, first[:y] * @scale, elevation)
        append_bulge_points(points, first, second, elevation) if first[:bulge].abs > 1.0e-10
      end
      points << Geom::Point3d.new(vertices.last[:x] * @scale, vertices.last[:y] * @scale, elevation) unless closed
      entities.add_curve(points) if points.length >= 2
      @counts['Polylines'] += 1
    end

    def append_bulge_points(points, first, second, elevation)
      bulge = first[:bulge]
      x1 = first[:x]
      y1 = first[:y]
      x2 = second[:x]
      y2 = second[:y]
      dx = x2 - x1
      dy = y2 - y1
      chord = Math.sqrt(dx * dx + dy * dy)
      return if chord <= 1.0e-12
      theta = 4.0 * Math.atan(bulge)
      radius = chord / (2.0 * Math.sin(theta.abs / 2.0))
      midpoint_x = (x1 + x2) / 2.0
      midpoint_y = (y1 + y2) / 2.0
      offset = chord * (1.0 - bulge * bulge) / (4.0 * bulge)
      center_x = midpoint_x - dy / chord * offset
      center_y = midpoint_y + dx / chord * offset
      start_angle = Math.atan2(y1 - center_y, x1 - center_x)
      steps = [[(theta.abs / (Math::PI / 18.0)).ceil, 1].max, 180].min
      1.upto(steps - 1) do |step|
        angle = start_angle + theta * step.to_f / steps
        points << Geom::Point3d.new((center_x + radius * Math.cos(angle)) * @scale,
                                    (center_y + radius * Math.sin(angle)) * @scale, elevation)
      end
    end

    def import_arc(entities, data)
      center, normal, x_axis = ocs(data)
      radius = number(data, 40, 0.0) * @scale
      return if radius <= 0.0
      start_angle = number(data, 50, 0.0) * Math::PI / 180.0
      end_angle = number(data, 51, 0.0) * Math::PI / 180.0
      end_angle += Math::PI * 2.0 while end_angle <= start_angle
      segments = [[((end_angle - start_angle) / (Math::PI / 18.0)).ceil, 1].max, 180].min
      entities.add_arc(center, x_axis, normal, radius, start_angle, end_angle, segments)
      @counts['Arcs'] += 1
    end

    def import_3dface(entities, data)
      points = [10, 11, 12, 13].map { |code| point(data, code) }.compact
      points.pop if points.length == 4 && points[2].distance(points[3]) <= 1.0e-8
      return if points.length < 3
      face = entities.add_face(points)
      @counts['3D faces'] += 1 if face
    end

    def import_polyface(entities, vertices)
      mesh_points = []
      face_indices = []
      vertices.each do |data|
        flags = number(data, 70, 0).to_i
        if (flags & 64) != 0
          mesh_points << point(data, 10)
        else
          indices = [71, 72, 73, 74].map { |code| number(data, code, 0).to_i }.reject { |index| index == 0 }.map(&:abs)
          face_indices << indices if indices.length >= 3
        end
      end
      face_indices.each do |indices|
        points = indices.map { |index| mesh_points[index - 1] }.compact
        face = entities.add_face(points) if points.length >= 3
        @counts['Polyface faces'] += 1 if face
      end
    end

    def point(data, base)
      x = optional_number(data, base)
      y = optional_number(data, base + 10)
      return nil if x.nil? || y.nil?
      z = optional_number(data, base + 20) || 0.0
      Geom::Point3d.new(x * @scale, y * @scale, z * @scale)
    end

    def ocs(data)
      normal = Geom::Vector3d.new(number(data, 210, 0.0), number(data, 220, 0.0), number(data, 230, 1.0))
      normal = Geom::Vector3d.new(0, 0, 1) if normal.length <= 1.0e-12
      normal.normalize!
      world_y = Geom::Vector3d.new(0, 1, 0)
      world_z = Geom::Vector3d.new(0, 0, 1)
      x_axis = if normal.x.abs < (1.0 / 64.0) && normal.y.abs < (1.0 / 64.0)
                 world_y.cross(normal)
               else
                 world_z.cross(normal)
               end
      x_axis.normalize!
      y_axis = normal.cross(x_axis)
      y_axis.normalize!
      ox = number(data, 10, 0.0)
      oy = number(data, 20, 0.0)
      oz = number(data, 30, 0.0)
      center = Geom::Point3d.new((ox * x_axis.x + oy * y_axis.x + oz * normal.x) * @scale,
                                 (ox * x_axis.y + oy * y_axis.y + oz * normal.y) * @scale,
                                 (ox * x_axis.z + oy * y_axis.z + oz * normal.z) * @scale)
      [center, normal, x_axis]
    end

    def add_line(entities, first, second)
      return unless first && second && first.distance(second) > 1.0e-8
      entities.add_line(first, second)
      @counts['Lines'] += 1
    end

    def number(data, code, default)
      found = optional_number(data, code)
      found.nil? ? default : found
    end

    def optional_number(data, code)
      pair = data.find { |item| item[0] == code }
      pair ? Float(pair[1]) : nil
    rescue ArgumentError, TypeError
      nil
    end

    def value(data, code, default)
      pair = data.find { |item| item[0] == code }
      pair ? pair[1] : default
    end

    def unit_scale(unit, model)
      case unit
      when 'Millimeters' then 1.0 / 25.4
      when 'Centimeters' then 1.0 / 2.54
      when 'Meters' then 1000.0 / 25.4
      when 'Feet' then 12.0
      when 'Model Units'
        length_unit = model.options['UnitsOptions']['LengthUnit']
        return 12.0 if length_unit == 1
        return 1.0 / 25.4 if length_unit == 2
        return 1.0 / 2.54 if length_unit == 3
        return 1000.0 / 25.4 if length_unit == 4
        1.0
      else
        1.0
      end
    end

    unless file_loaded?(__FILE__)
      file_menu = UI.menu('File')
      file_menu.add_item('Import DXF with Layers...') { import_dxf }
      tools_menu = UI.menu('Tools')
      tools_menu.add_item('Import DXF with Layers...') { import_dxf }
      file_loaded(__FILE__)
    end
  end
end
