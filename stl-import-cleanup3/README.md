# STL Import + CleanUp³ integration

This SketchUp 2017 companion extension hooks the installed **STL Import & Export** importer. After a successful import it finds the newly created top-level entities, selects them, then calls CleanUp³'s `cleanup_last` method. CleanUp³ therefore uses its saved options and the selected-import scope.

The signed STL importer and CleanUp³ source files are left unchanged.

## Requirements

- SketchUp 2017
- The SketchUp **STL Import & Export** extension enabled
- **CleanUp³** (installed in this SketchUp profile as `tt_cleanup`) enabled

## Install

Copy `zz_stl_cleanup3.rb` and the `zz_stl_cleanup3` folder to:

`%AppData%\SketchUp\SketchUp 2017\SketchUp\Plugins`

Restart SketchUp. The `zz_` loader name makes it load after the STL and CleanUp³ plugin loaders.

Cleanup3 settings such as purging apply as configured in CleanUp³ and may affect model-wide unused resources even when the selected geometry scope is used. Change CleanUp³'s saved options first if that is not desired.
