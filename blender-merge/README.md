# N0JCG Blender Merge for SketchUp Make 2017

Version 1.2.3 automatically imports the Blender union into SketchUp through the installed STL Import & Export extension. It uses the saved STL import units and options, then runs CleanUp³ with its saved settings and reports remaining edge issues. Small geometry is enlarged internally during import and the group is scaled back to its original visible size; no separate import command or scaling choice is shown.

This SketchUp extension adds a one-command **Union** for two selected groups or component instances. It exports each selected object through the installed SketchUp STL Import & Export extension, runs Blender headlessly with the Exact Boolean solver, saves the merged STL and Blender diagnostic log in the Downloads folder, and imports the union into the current SketchUp model automatically. The original selected objects remain unchanged, and the imported union group is selected.

SketchUp Make 2017 does not expose the native Solid Tools `union` API. This extension uses the Blender installation as its Boolean engine, so Blender and the signed **STL Import & Export** extension must be installed and enabled. The SketchUp STL extension is open source: <https://github.com/SketchUp/sketchup-stl>.

## Install

1. In SketchUp 2017, open **Window → Extension Manager → Install Extension**.
2. Select `N0JCG_Blender_Merge_1.2.3.rbz`.
3. Restart SketchUp if requested. The command appears under **Extensions → N0JCG Blender Merge** and in the selection context menu.

## Use

1. Make sure both parts are groups or component instances at the top level of the model. Close any group/component editing context.
2. Select exactly two top-level groups or components. Both selected objects should show a blue outline.
3. Choose **Extensions → N0JCG Blender Merge → Merge Two Selected Objects (Union)**, or use the selection context menu.
4. The first successful run may ask you to locate `blender.exe` if Blender is not installed under Program Files. The path is saved for future runs.
5. The union imports into the current model automatically. A timestamped `N0JCG_Merged_*.stl` and matching Blender log are also saved in `%USERPROFILE%\Downloads`. The import automatically compensates for SketchUp's small-edge tolerance and restores the group's visible size. The original SketchUp source objects remain unchanged; the imported union group is selected.

The operation requires each input to be a closed manifold solid. After the Boolean, Blender performs a small-tolerance cleanup and fills generated boundary loops, then imports the written STL back into Blender and checks it. Automatic SketchUp import honors the saved STL units and repair/merge settings, and runs CleanUp³ on the imported result if that extension is loaded. The STL and diagnostic log are saved under `%USERPROFILE%\Downloads`; the source SketchUp objects remain unchanged.

The selected Blender executable is saved in SketchUp preferences. Automatically discovered installations are saved too.

STL has no unit metadata. The extension exports using the last units selected in the installed STL importer settings, so the imported result uses the same scale as the input parts. It preserves the original objects' combined bounding-box placement if the STL importer is configured to reposition imports.
