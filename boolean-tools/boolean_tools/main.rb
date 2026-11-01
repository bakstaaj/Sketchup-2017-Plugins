# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'

module N0JCG
  module BooleanTools
    extend self

    class PickTool
      def initialize(mode)
        @mode = mode
        @input_point = Sketchup::InputPoint.new
        @operands = []
      end

      def activate
        prompt
      end

      def deactivate(view)
        view.invalidate
        Sketchup.status_text = ''
      end

      def onMouseMove(_flags, x, y, view)
        @input_point.pick(view, x, y)
        view.invalidate
      end

      def draw(view)
        @input_point.draw(view) if @input_point.valid?
      end

      def onLButtonDown(_flags, x, y, view)
        @input_point.pick(view, x, y)
        entity = picked_solid
        unless entity
          Sketchup.status_text = 'Pick a group or component instance.'
          return
        end

        if @operands.empty?
          @operands << entity
          prompt
          return
        end

        first = @operands.first
        if entity == first
          Sketchup.status_text = 'Pick a different second solid.'
          return
        end
        unless entity.parent == first.parent
          Sketchup.status_text = 'Both solids must be in the same editing context.'
          return
        end

        Sketchup.active_model.select_tool(nil)
        BooleanTools.perform(@mode, first, entity)
      end

      def onKeyDown(key, _repeat, _flags, view)
        if key == VK_ESCAPE
          Sketchup.active_model.select_tool(nil)
          view.invalidate
        end
      end

      private

      def picked_solid
        return nil unless @input_point.valid?
        path = @input_point.instance_path
        return nil unless path
        entities = path.to_a
        active_entities = Sketchup.active_model.active_entities
        entities.find do |entity|
          (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
            entity.parent == active_entities
        end
      end

      def prompt
        message = if @operands.empty?
          'Click the TARGET solid first.'
        elsif [:subtract_ab, :subtract_ba].include?(@mode)
          'Now click solid B. The selected menu command determines the subtraction direction.'
        else
          'Now click solid B. The selected menu command determines which Boolean region is kept.'
        end
        Sketchup.status_text = "N0JCG Boolean Tools: #{message}  Esc cancels."
      end
    end

    def start(mode)
      model = Sketchup.active_model
      unless model && model.active_path.nil?
        UI.messagebox('Close the current group/component editing context before using Boolean Tools.')
        return
      end
      model.select_tool(PickTool.new(mode))
    end

    def copy_instance(entity)
      entity.parent.entities.add_instance(entity.definition, entity.transformation)
    end

    def perform(mode, target, cutter)
      unless target.respond_to?(:subtract) && target.respond_to?(:split)
        UI.messagebox('This SketchUp edition does not provide the Solid Tools Boolean API. Boolean Tools requires SketchUp Pro 2017; SketchUp Make 2017 does not expose these operations.')
        return
      end

      model = Sketchup.active_model
      operation_name = {
        :subtract_ab => 'Boolean A minus B',
        :subtract_ba => 'Boolean B minus A',
        :intersection => 'Boolean Intersection',
        :non_overlapping => 'Boolean Non-Overlapping Parts'
      }[mode]
      model.start_operation(operation_name, true)
      operation_open = true
      outputs = []

      if [:subtract_ab, :subtract_ba].include?(mode)
        target_copy = copy_instance(target)
        cutter_copy = copy_instance(cutter)
        result = if mode == :subtract_ab
          target_copy.subtract(cutter_copy)
        else
          cutter_copy.subtract(target_copy)
        end
        unless result
          model.abort_operation
          operation_open = false
          UI.messagebox('Subtract failed. Both inputs must be closed manifold solids and SketchUp must be able to resolve the operation.')
          return
        end
        result.name = mode == :subtract_ab ? 'A minus B' : 'B minus A'
        outputs << result
      else
        # split returns [cutter-target, target-cutter, intersection]. Copies
        # protect both original objects because Solid Tools consumes operands.
        target_for_split = copy_instance(target)
        cutter_for_split = copy_instance(cutter)
        parts = target_for_split.split(cutter_for_split)
        unless parts && parts.length >= 3
          model.abort_operation
          operation_open = false
          UI.messagebox('The Boolean split failed. Both inputs must be closed manifold solids.')
          return
        end
        if mode == :intersection
          keep_result(parts[2], 'A overlapping B', outputs)
          erase_result(parts[0])
          erase_result(parts[1])
        else
          keep_result(parts[0], 'B minus A', outputs)
          keep_result(parts[1], 'A minus B', outputs)
          erase_result(parts[2])
        end
      end

      model.commit_operation
      operation_open = false
      model.selection.clear
      outputs.each { |entity| model.selection.add(entity) }
      model.active_view.invalidate
      Sketchup.status_text = outputs.empty? ? 'Boolean operation completed with no remaining volume.' : 'Boolean operation complete.'
    rescue => error
      model.abort_operation if operation_open
      UI.messagebox("Boolean operation failed:\n#{error.message}")
    end

    def keep_result(part, name, outputs)
      return unless part && part.valid?
      if part.entities.grep(Sketchup::Face).empty?
        part.erase!
      else
        part.name = name
        outputs << part
      end
    end

    def erase_result(part)
      part.erase! if part && part.valid?
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu('N0JCG Boolean Tools')
      menu.add_item('Subtract B from A (A - B)') { start(:subtract_ab) }
      menu.add_item('Subtract A from B (B - A)') { start(:subtract_ba) }
      menu.add_item('Keep Overlapping Space (A intersection B)') { start(:intersection) }
      menu.add_item('Keep Non-Overlapping Space (A XOR B)') { start(:non_overlapping) }
      file_loaded(__FILE__)
    end
  end
end
