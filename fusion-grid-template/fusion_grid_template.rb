# Fusion-inspired grid workspace template helper for SketchUp 2017.
# Adds a dark modeling style and a locked, edge-only reference grid to a blank model.
# Version 1.0.9

require 'sketchup.rb'

module N0JCG
  module FusionGridTemplate
    MENU_NAME = 'Prepare Fusion-style Grid Template'.freeze
    GRID_GROUP_NAME = 'Fusion Workplane Grid'.freeze
    GRID_LAYER_NAME = 'FUSION_GRID_REFERENCE'.freeze
    MINOR_MATERIAL = 'Fusion Grid - Minor'.freeze
    MAJOR_MATERIAL = 'Fusion Grid - Major'.freeze
    GRID_ATTRIBUTE_DICTIONARY = 'N0JCG_FusionGrid'.freeze
    GRID_ATTRIBUTE_KEY = 'reference_only'.freeze
    GRID_HALF_EXTENT_MM = 250
    MINOR_STEP_MM = 10
    MAJOR_STEP_MM = 50

    def self.prepare
      model = Sketchup.active_model
      existing_entities = model.entities.to_a
      existing_grids = existing_entities.select { |entity| workspace_grid?(entity) }
      other_entities = existing_entities.reject { |entity| workspace_grid?(entity) }
      unless other_entities.empty?
        UI.messagebox('Run this command in a blank model or a model containing only the Fusion Workplane Grid. Your other model geometry was left untouched.')
        return
      end

      model.start_operation('Prepare Fusion-style grid template', true)
      begin
        set_units_and_style(model)
        add_grid(model)
        set_camera(model)
        model.active_layer = model.layers[0]
        model.selection.clear
        model.commit_operation
        model.styles.update_selected_style
        model.active_view.invalidate
        UI.messagebox('Fusion-style four-quadrant workspace is ready. Save it with File > Save As Template. The grid extends 250 mm from the origin in both directions along X and Y.')
      rescue => error
        model.abort_operation
        UI.messagebox("Could not create the grid template:\n#{error.message}", MB_MULTILINE)
      end
    end

    def self.set_units_and_style(model)
      model.options['UnitsOptions']['LengthUnit'] = 2 # Millimeters
      options = model.rendering_options
      options['BackgroundColor'] = Sketchup::Color.new(39, 41, 45)
      options['SkyColor'] = Sketchup::Color.new(39, 41, 45)
      options['DrawGround'] = false
      options['DrawHorizon'] = false
      options['DisplaySketchAxes'] = true
      options['EdgeColorMode'] = 0
      options['ConstructionColor'] = Sketchup::Color.new(255, 232, 115)
      options['FaceFrontColor'] = Sketchup::Color.new(190, 194, 200)
      options['FaceBackColor'] = Sketchup::Color.new(105, 110, 117)
    end

    def self.apply_grid_appearance
      model = Sketchup.active_model
      model.rendering_options['ConstructionColor'] = Sketchup::Color.new(255, 232, 115)
      model.styles.update_selected_style
      model.active_view.invalidate
      UI.messagebox('Construction lines and points are now light yellow in this model style.')
    rescue => error
      UI.messagebox("Could not update the construction line color:\n#{error.message}")
    end

    def self.select_all_except_grid
      model = Sketchup.active_model
      entities = model.active_entities.to_a
      selection = model.selection
      selection.clear
      selectable = entities.reject do |entity|
        workspace_grid?(entity) || reference_entity?(entity)
      end
      selection.add(selectable) unless selectable.empty?
    rescue => error
      UI.messagebox("Could not select model geometry:\n#{error.message}")
    end

    def self.zoom_to_drawing
      model = Sketchup.active_model
      drawing_entities = model.entities.to_a.select do |entity|
        next false if workspace_grid?(entity) || reference_entity?(entity)
        next false unless entity.respond_to?(:visible?) && entity.visible?
        next false if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
        next false if entity.is_a?(Sketchup::ConstructionLine)
        next false if entity.is_a?(Sketchup::ConstructionPoint)

        true
      end

      if drawing_entities.empty?
        UI.messagebox('No visible drawing objects were found to zoom to. The Fusion Workplane Grid was ignored.')
        return
      end

      model.active_view.zoom(drawing_entities)
    rescue => error
      UI.messagebox("Could not zoom to drawing objects:\n#{error.message}")
    end

    def self.create_toolbar
      icon_path = File.join(File.dirname(__FILE__), 'fusion_grid_zoom.svg')
      command = UI::Command.new('Zoom to Drawing') { zoom_to_drawing }
      command.tooltip = 'Zoom Extents to Drawing (Ignore Fusion Grid)'
      command.status_bar_text = 'Frame visible model objects without including the Fusion Workplane Grid.'
      command.small_icon = icon_path
      command.large_icon = icon_path

      @toolbar = UI::Toolbar.new('Fusion Grid')
      @toolbar.add_item(command)
      @toolbar.show
    end

    def self.add_grid(model)
      model.entities.to_a.each do |entity|
        next unless workspace_grid?(entity)
        entity.locked = false if entity.locked?
        entity.erase!
      end

      layer = model.layers[GRID_LAYER_NAME] || model.layers.add(GRID_LAYER_NAME)
      layer.visible = true
      materials = model.materials
      minor_material = materials[MINOR_MATERIAL] || materials.add(MINOR_MATERIAL)
      major_material = materials[MAJOR_MATERIAL] || materials.add(MAJOR_MATERIAL)
      # Half the previous contrast against the #27292D background.
      minor_material.color = Sketchup::Color.new(57, 60, 65)
      major_material.color = Sketchup::Color.new(76, 79, 85)

      grid = model.entities.add_group
      grid.name = GRID_GROUP_NAME
      grid.layer = layer
      grid.set_attribute(GRID_ATTRIBUTE_DICTIONARY, GRID_ATTRIBUTE_KEY, true)

      size = mm(GRID_HALF_EXTENT_MM)
      step = mm(MINOR_STEP_MM)
      count = GRID_HALF_EXTENT_MM / MINOR_STEP_MM
      (-count..count).each do |index|
        next if index == 0 # Let SketchUp's colored axes represent the zero grid lines.
        offset = index * step
        material = (index * MINOR_STEP_MM) % MAJOR_STEP_MM == 0 ? major_material : minor_material
        add_isolated_line(grid.entities, Geom::Point3d.new(offset, -size, 0), Geom::Point3d.new(offset, size, 0), material)
        add_isolated_line(grid.entities, Geom::Point3d.new(-size, offset, 0), Geom::Point3d.new(size, offset, 0), material)
      end
      grid.locked = true
    end

    def self.workspace_grid?(entity)
      entity.is_a?(Sketchup::Group) && entity.name == GRID_GROUP_NAME
    end

    def self.add_isolated_line(entities, start_point, end_point, material)
      line_group = entities.add_group
      line_group.set_attribute(GRID_ATTRIBUTE_DICTIONARY, GRID_ATTRIBUTE_KEY, true)
      edge = line_group.entities.add_line(start_point, end_point)
      edge.material = material
      edge.set_attribute(GRID_ATTRIBUTE_DICTIONARY, GRID_ATTRIBUTE_KEY, true)
    end

    def self.reference_entity?(entity)
      return false unless entity && entity.valid?
      return true if entity.get_attribute(GRID_ATTRIBUTE_DICTIONARY, GRID_ATTRIBUTE_KEY, false)
      @reference_entity_ids && @reference_entity_ids[entity.entityID]
    rescue
      false
    end

    def self.set_camera(model)
      target = Geom::Point3d.new(0, 0, 0)
      eye = Geom::Point3d.new(mm(300), mm(-300), mm(350))
      model.active_view.camera.set(eye, target, Geom::Vector3d.new(0, 0, 1))
      model.active_view.camera.perspective = true
    end

    def self.mm(value)
      value.to_f / 25.4
    end

    unless file_loaded?(__FILE__)
      UI.menu('Tools').add_item(MENU_NAME) { prepare }
      UI.menu('Tools').add_item('Apply Fusion Grid Appearance') { apply_grid_appearance }
      UI.menu('Edit').add_item('Select All Except Fusion Grid') { select_all_except_grid }
      UI.menu('Camera').add_item('Zoom Extents to Drawing (Ignore Fusion Grid)') { zoom_to_drawing }
      create_toolbar
      file_loaded(__FILE__)
    end
  end
end
