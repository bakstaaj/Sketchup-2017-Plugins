# Named-Layer DXF Exporter for SketchUp 2017

This companion duplicates the installed **Export to DXF or STL** script without editing or replacing it. It adds **File > Export DXF with Named Layers** and **Tools > Export DXF with Named Layers**.

Version 1.0.1 identifies SketchUp entities by their API `typename` and reports the scanned entity types if a selected set contains no exportable faces or edges. Version 1.0.2 automatically switches an edge-only selection to DXF line output. Version 1.1.0 switches edge-only selections to **circles and polylines**: full SketchUp circle curves become DXF `CIRCLE` entities, and connected straight or segmented edges are joined into 3D `POLYLINE` entities. Version 1.1.1 detects a full circle by checking that its curve edges form a closed loop. Version 1.2.0 chooses **circles and polylines** by default for edge-only selections and **polyface mesh** when faces are present. Version 1.3.0 also fits closed 12-or-more-vertex loops to a circle and exports a native DXF `CIRCLE` when the points are planar and within 0.1% of a common radius. Version 1.4.0 adds an **Export origin** choice: keep the model origin or click a model point to make it DXF `0,0,0`. Version 1.4.1 guards the origin click and export launch so one click starts at most one save dialog. Version 1.4.2 ignores the `Fusion Workplane Grid` reference group during model-wide DXF export. Version 1.4.3 defaults the geometry choice to **polylines** and the export origin to **Select point**. Other loops remain polylines. Exporting does not move SketchUp geometry. Circles under non-uniform scaling are written as polylines because the transformed geometry is no longer circular.

## Layer mapping

- SketchUp layers (called Tags in newer SketchUp versions) are written to DXF's LAYER table, and each exported entity is assigned to the corresponding DXF layer.
- A tagged group or component passes its layer to its untagged contents. A tag explicitly assigned to nested geometry takes precedence. Untagged top-level geometry uses DXF layer `0`.
- Unsupported DXF layer-name characters are replaced with underscores. If two SketchUp layer names sanitize to the same DXF name, a numeric suffix distinguishes them.
- Groups and component instances are flattened into the DXF entity section using their transformed coordinates.

## Use

1. Select geometry to export, or leave the selection empty and choose to export the whole model.
2. Choose the output units, geometry representation, and export origin. Defaults are **polylines** and **Select point**; edge-only selections are automatically exported as circles and polylines when appropriate. Choose **Select point** to click the point that should become the DXF origin.
3. Choose the DXF file path.
4. In the receiving CAD application, open the DXF layer manager to verify the named layers.

The exporter uses SketchUp's internal inch coordinates and converts them to the unit selected during export. It does not transfer materials, colors, components as blocks, or exact analytic surfaces. The receiving CAD/CAM program should be checked with a small sample before using a full production export.

## Install

The source script can be copied to `%AppData%\SketchUp\SketchUp 2017\SketchUp\Plugins` and loaded after restarting SketchUp. The `.rbz` archive contains the same standalone script for Extension Manager installation.
