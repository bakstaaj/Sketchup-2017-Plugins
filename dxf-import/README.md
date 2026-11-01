# DXF Import for SketchUp 2017

This extension adds **File > Import DXF with Layers...** and **Tools > Import DXF with Layers...**. It is designed for SketchUp Make 2017 and works alongside the named-layer DXF exporter.

The importer reads ASCII DXF entities for lines, circles, arcs, lightweight and 3D polylines, 3D faces, and polyface meshes. It converts each DXF layer into a SketchUp tag and places that layer's imported geometry in a named group. Circles and arcs remain native SketchUp curves. DXF units are chosen during import; the initial choice is millimeters and the last choice is remembered.

The importer does not support binary DXF, blocks/inserts, splines, text, dimensions, hatches, or arbitrary CAD proxy objects. Unsupported entity types are skipped and counted in the completion message. Geometry is added to the current model in one undoable operation; imported layer groups remain selected afterward.

## Install

Install `N0JCG_DXF_Import_0.1.0.rbz` through **Window > Extension Manager > Install Extension**. Restart SketchUp if the extension was already open when installed.
