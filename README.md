# SketchUp 2017 Plugins

A collection of extensions and workflow helpers for SketchUp Make/Pro 2017. Each plugin folder contains its source and plugin-specific instructions. Installable `.rbz` packages are attached to the corresponding GitHub Releases.

## Plugins

| Plugin | Current release | Description |
|---|---:|---|
| [STL Manifold Check](stl-manifold-check/) | [0.1.6](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/stl-manifold-check-v0.1.6/STL_Manifold_Check_0.1.6.rbz) | Check selected model geometry for open and non-manifold edges and highlight problem edges. |
| [STL Import + CleanUp³](stl-import-cleanup3/) | [1.0.0](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/stl-import-cleanup3-v1.0.0/STL_Import_CleanUp3_1.0.0.rbz) | Select newly imported STL geometry and run CleanUp³ using its remembered settings. |
| [Blender Merge](blender-merge/) | [1.2.3](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/blender-merge-v1.2.3/N0JCG_Blender_Merge_1.2.3.rbz) | Run a Blender Boolean union on two selected SketchUp groups or components. |
| [STEP Import](step-import/) | [0.3.3](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/step-import-v0.3.3/N0JCG_STEP_Import_0.3.3.rbz) | Convert STEP files through Blender and import the resulting mesh. |
| [Boolean Tools](boolean-tools/) | [1.1.0](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/boolean-tools-v1.1.0/N0JCG_Boolean_Tools_1.1.0.rbz) | Subtract, intersect, or keep non-overlapping portions using SketchUp Pro Solid Tools. |
| [Fusion-style Grid Template](fusion-grid-template/) | [1.0.8](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/fusion-grid-template-v1.0.8/N0JCG_Fusion_Grid_Template_1.0.8.rbz) | Prepare a dark, four-quadrant grid workspace, apply visible construction-line colors, and zoom to drawing objects without the reference grid. |
| [Named-Layer DXF Exporter](named-layer-dxf-exporter/) | [1.4.2](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/named-layer-dxf-exporter-v1.4.2/Named_Layer_DXF_Exporter_1.4.2.rbz) | Export geometry to DXF with SketchUp tags as named layers, circle/polyline support, and origin selection. |
| [DXF Import](dxf-import/) | [0.1.0](https://github.com/bakstaaj/Sketchup-2017-Plugins/releases/download/dxf-import-v0.1.0/N0JCG_DXF_Import_0.1.0.rbz) | Import supported ASCII DXF geometry and preserve DXF layers as SketchUp tags. |

## Install

Download the `.rbz` from the plugin's release link, then in SketchUp 2017 choose **Window > Extension Manager > Install Extension** and select the downloaded file. Restart SketchUp if prompted. Check each plugin README for requirements and known limitations.

## Compatibility notes

- These extensions target SketchUp 2017 and Ruby 2.2 unless the plugin README says otherwise.
- Blender Merge and STEP Import require Blender; STEP Import also requires Blender's STEP Importer add-on.
- Boolean Tools uses the SketchUp Pro Solid Tools API and does not provide Boolean operations in SketchUp Make 2017.
- The DXF importer supports a subset of ASCII DXF entities; see its README for details.
