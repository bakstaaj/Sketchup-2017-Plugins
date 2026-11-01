# Fusion-style Grid Template Helper for SketchUp 2017

This helper prepares a blank SketchUp model for use as a Fusion-inspired workspace template. Version 1.0.2 centers a 500 × 500 mm grid on the origin, covering all four quadrants from -250 to +250 mm on X and Y. Version 1.0.3 reduces both grid line contrasts against the background by 50%, while keeping 50 mm major lines brighter than 10 mm minor lines. Version 1.0.7 adds **Tools > Apply Fusion Grid Appearance** to set construction lines and points to light yellow in any active model, and **Edit > Select All Except Fusion Grid** to select the active model context while skipping the reference grid. The built-in Select All command remains unchanged. The template command sets millimeter units, a dark solid background, and keeps the SketchUp axes visible.

The grid is grouped as `Fusion Workplane Grid` on the `FUSION_GRID_REFERENCE` tag. It is edge-only reference geometry, not a dynamically zooming viewport grid. Toggle the tag in SketchUp's Layers tray to hide or show it. The named-layer DXF exporter skips this named reference group so it does not appear in its DXF output. Use **Edit > Select All Except Fusion Grid** to select model geometry without the reference grid.

## Create and use the template

1. Install `N0JCG_Fusion_Grid_Template_1.0.7.rbz` through **Window > Preferences > Extensions > Install Extension** and restart SketchUp.
2. Open the template model you already created, or choose **File > New** for a blank model.
3. Choose **Tools > Prepare Fusion-style Grid Template**. It can update a blank model or a model containing only the existing grid.
4. Choose **File > Save As Template**, name it `Fusion-style Grid (mm)`, and check **Set as default template** if you want it for future blank models.
5. If you did not set it as the default during save, choose **Window > Preferences > Template** and select it.

The helper refuses to modify models containing other geometry, so it does not erase or alter an existing design.
