# Copyright 2026 N0JCG. Released under the MIT License.
require 'sketchup'

module N0JCG
  module STLImportCleanUp3
    module ImportHook
      def load_file(path, status)
        model = Sketchup.active_model
        before_ids = model.entities.map { |entity| entity.entityID }
        result = super
        return result unless result == CommunityExtensions::STL::Importer::IMPORT_SUCCESS

        imported = model.entities.to_a.reject { |entity| before_ids.include?(entity.entityID) }
        return result if imported.empty?

        selection = model.selection
        selection.clear
        imported.each { |entity| selection.add(entity) }

        if defined?(TT::Plugins::CleanUp) && TT::Plugins::CleanUp.respond_to?(:cleanup_last)
          TT::Plugins::CleanUp.cleanup_last
        else
          Sketchup.status_text = 'STL imported and selected. CleanUp³ is not loaded.'
        end
        result
      rescue => error
        # Preserve the import result if cleanup fails; the imported geometry
        # remains selected so CleanUp³ can still be run manually.
        puts "STL Import CleanUp³: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        result
      end
    end

    unless file_loaded?(__FILE__)
      if defined?(CommunityExtensions::STL::Importer)
        importer = CommunityExtensions::STL::Importer
        importer.prepend(ImportHook) unless importer.ancestors.include?(ImportHook)
      else
        UI.messagebox('STL Import CleanUp³ could not find the STL Import & Export extension. Enable it and restart SketchUp.')
      end
      file_loaded(__FILE__)
    end
  end
end
