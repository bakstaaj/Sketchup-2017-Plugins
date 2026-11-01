# N0JCG STEP Import for SketchUp Make 2017

Version 0.3.3 uses Blender to convert STEP files through the separate Blender **STEP Importer** extension, then imports the generated mesh through SketchUp's installed **STL Import & Export** extension. STL files are imported directly through SketchUp's STL importer.

## Requirements

- SketchUp Make 2017 with the signed **STL Import & Export** extension enabled.
- Blender 5.1 or newer. The extension searches common Windows install folders or prompts for `blender.exe`.
- Blender's **STEP Importer** extension installed and enabled. In Blender, open **Edit → Preferences → Get Extensions**, search for `STEP Importer`, and install/enable it. Its add-on page is <https://extensions.blender.org/add-ons/step-importer/>.

The STEP Importer extension is required for STEP files. STL files are handled directly by SketchUp and do not pass through Blender.

The STEP add-on uses Cascadio to create a mesh from the CAD geometry inside Blender; it does not require FreeCAD. The bridge exports STL coordinates in millimeters. SketchUp receives triangulated faces and edges, not exact CAD surfaces. This first version merges imported bodies into one mesh, so it does not retain STEP assembly hierarchy or material colors.

## Install

In SketchUp 2017, choose **Window → Extension Manager → Install Extension** and select `N0JCG_STEP_Import_0.3.3.rbz`. Restart SketchUp if asked.

## Use

Choose **Extensions → N0JCG STEP Import → Import STEP Model...**, select a `.step` or `.stp` file, and let Blender convert it. The bridge imports the resulting millimeter mesh through SketchUp's STL importer using your saved repair/merge settings.

## Status

The user confirmed Blender 5.2 with STEP Importer 1.2.1 enabled. STEP import was confirmed working end-to-end. STL imports use SketchUp directly. The bridge leaves the saved SketchUp repair and merge settings in control.
