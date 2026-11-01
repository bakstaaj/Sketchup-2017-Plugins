# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'
require 'json'

module N0JCG
  module STLManifoldCheck
    extend self
    ASSET_ROOT = File.dirname(__FILE__).freeze

    RED = Sketchup::Color.new(255, 35, 35)

    def edge_key(edge, transform)
      [edge.entityID, transform.to_a]
    end

    def record_edge(edge, transform, path, results, seen)
      return unless edge.valid?
      return if edge.hidden? || (edge.respond_to?(:layer) && !edge.layer.visible?)
      key = edge_key(edge, transform)
      return if seen[key]
      seen[key] = true

      face_count = edge.faces.length
      if face_count != 2
        a = edge.start.position.transform(transform)
        b = edge.end.position.transform(transform)
        results << { :a => a, :b => b, :faces => face_count, :path => path }
      end
    end

    # Recursively scan only the contents of selected groups/components.
    def scan_entities(entities, transform, path, results, seen)
      entities.each do |entity|
        next unless entity.valid?
        next if entity.hidden? || (entity.respond_to?(:layer) && !entity.layer.visible?)

        if entity.is_a?(Sketchup::Edge)
          record_edge(entity, transform, path, results, seen)
        elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          child_path = path.empty? ? entity.definition.name : path + ' / ' + entity.definition.name
          scan_entities(entity.definition.entities, transform * entity.transformation, child_path, results, seen)
        end
      end
    end

    def find_issues
      model = Sketchup.active_model
      selection = model.selection.to_a
      raise 'Select one or more objects, groups, components, faces, or edges first.' if selection.empty?

      issues = []
      seen = {}
      base_transform = model.edit_transform
      selection.each do |entity|
        next unless entity.valid?
        next if entity.hidden? || (entity.respond_to?(:layer) && !entity.layer.visible?)

        if entity.is_a?(Sketchup::Edge)
          record_edge(entity, base_transform, '', issues, seen)
        elsif entity.is_a?(Sketchup::Face)
          entity.edges.each { |edge| record_edge(edge, base_transform, '', issues, seen) }
        elsif entity.is_a?(Sketchup::Curve)
          entity.edges.each { |edge| record_edge(edge, base_transform, '', issues, seen) }
        elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          path = entity.definition.name
          scan_entities(entity.definition.entities, base_transform * entity.transformation, path, issues, seen)
        end
      end
      issues
    end

    def highlight(issues)
      return if issues.empty?
      model = Sketchup.active_model
      model.select_tool(HighlightTool.new(issues))
      # select_tool invalidates asynchronously. Force the first paint before a
      # modal confirmation dialog can block SketchUp's normal redraw cycle.
      model.active_view.refresh
    end

    class HighlightTool
      def initialize(issues)
        @issues = issues
      end

      def draw(view)
        points = []
        @issues.each { |issue| points << issue[:a] << issue[:b] }
        view.drawing_color = RED
        view.line_width = 4
        view.draw(GL_LINES, points) unless points.empty?
      end

      def onKeyDown(key, repeat, flags, view)
        if key == VK_ESCAPE
          Sketchup.active_model.select_tool(nil)
          view.invalidate
        end
      end

      def deactivate(view)
        view.invalidate
      end
    end

    def report(issues)
      boundaries = issues.count { |issue| issue[:faces] == 1 }
      loose = issues.count { |issue| issue[:faces] == 0 }
      overused = issues.count { |issue| issue[:faces] > 2 }
      "Selected Geometry Manifold Check\n\n" +
        "Problem edges: #{issues.length}\n" +
        "Open boundary edges (1 face): #{boundaries}\n" +
        "Loose edges (0 faces): #{loose}\n" +
        "Non-manifold edges (>2 faces): #{overused}\n\n" +
        (issues.empty? ? 'No edge problems found.' : 'Problem edges are highlighted in red. Press Esc to clear the highlight.')
    end

    def check
      return if @check_export_pending
      if Sketchup.active_model.selection.empty?
        UI.messagebox('Select the objects or geometry you want to check first.')
        return
      end
      issues = find_issues
      highlight(issues)
      if issues.empty?
        UI.messagebox(report(issues))
      else
        @check_export_pending = true
        timer_id = nil
        timer_id = UI.start_timer(0.2, false) do
          # SketchUp 2017 can re-fire a non-repeating timer while a modal
          # message box blocks its callback. Stop it before opening the box.
          UI.stop_timer(timer_id)
          begin
            UI.messagebox(report(issues))
          ensure
            @check_export_pending = false
          end
        end
      end
    rescue => error
      UI.messagebox("STL Manifold Check failed:\n#{error.message}\n#{error.backtrace[0]}")
    end

    def check_then_export
      return if @check_export_pending
      if Sketchup.active_model.selection.empty?
        UI.messagebox('Select the objects or geometry you want to check first.')
        return
      end
      issues = find_issues
      unless defined?(CommunityExtensions::STL::Exporter)
        UI.messagebox("The STL Import & Export extension is not loaded. Use File > Export STL after enabling it.")
        return
      end
      if issues.empty?
        open_export_dialog(issues)
      else
        @check_export_pending = true
        highlight(issues)
        # Yield back to SketchUp so HighlightTool#draw gets a paint cycle
        # before the modal confirmation covers the model view.
        timer_id = nil
        timer_id = UI.start_timer(0.2, false) do
          # A modal prompt otherwise blocks this timer and may cause it to
          # fire repeatedly until the user dismisses the prompt.
          UI.stop_timer(timer_id)
          begin
            choice = UI.messagebox(report(issues) + "\n\nContinue to STL export anyway?", MB_YESNO)
            @check_export_pending = false
            open_export_dialog(issues) if choice == IDYES
          rescue => error
            @check_export_pending = false
            UI.messagebox("STL preflight/export failed:\n#{error.message}")
          ensure
            @check_export_pending = false
          end
        end
      end
    rescue => error
      UI.messagebox("STL preflight/export failed:\n#{error.message}")
    end

    def open_export_dialog(issues)
      if @export_dialog && @export_dialog.visible?
        @export_dialog.bring_to_front
        return
      end
      exporter = CommunityExtensions::STL::Exporter
      dialog = @export_dialog = UI::HtmlDialog.new(
        :dialog_title => 'STL Export',
        :preferences_key => 'N0JCG_STL_Compact_Export',
        :scrollable => false,
        :resizable => false,
        :width => 320,
        :height => 190,
        :style => UI::HtmlDialog::STYLE_DIALOG
      )
      dialog.set_file(File.join(ASSET_ROOT, 'export_dialog.html'))
      dialog.add_action_callback('export_stl') do |_context, params|
        begin
          chosen = JSON.parse(params)
          exporter::OPTIONS['selection_only'] = (chosen['selection'] == true)
          exporter::OPTIONS['export_units'] = chosen['unit']
          exporter::OPTIONS['stl_format'] = chosen['format']
          exporter.write_setting('selection_only', exporter::OPTIONS['selection_only'])
          exporter.write_setting('export_units', exporter::OPTIONS['export_units'])
          exporter.write_setting('stl_format', exporter::OPTIONS['stl_format'])
          entities = exporter.get_export_entities
          next unless entities
          path = exporter.select_export_file
          next unless path
          exporter.export(path, entities, exporter::OPTIONS)
          dialog.close
        rescue => error
          UI.messagebox("STL export failed:\n#{error.message}")
        end
      end
      dialog.add_action_callback('cancel_export') { |_context, _params| dialog.close }
      dialog.show
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions')
      menu.add_item('Check Selected Geometry for STL Manifold Issues') { check }
      menu.add_item('Check then Export STL (Compact)...') { check_then_export }
      file_loaded(__FILE__)
    end
  end
end
