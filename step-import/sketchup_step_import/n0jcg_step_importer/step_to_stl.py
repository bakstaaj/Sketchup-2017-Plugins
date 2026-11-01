# Copyright 2026 N0JCG. Released under the MIT License.
# Run by Blender in background mode using the separate STEP Importer extension.
import os
import traceback

import addon_utils
import bpy

source_path = os.environ['N0JCG_STEP_INPUT']
output_path = os.environ['N0JCG_STEP_OUTPUT']
report_path = os.environ.get('N0JCG_STEP_REPORT', '')
export_scale = float(os.environ.get('N0JCG_STEP_EXPORT_SCALE', '1000'))

try:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # The add-on is installed separately. Blender 5.x extensions use this
    # repository-qualified module name and need a preferences entry.
    addon_utils.enable('bl_ext.blender_org.step_importer', default_set=True)
    if not hasattr(bpy.ops.import_scene, 'step'):
        raise RuntimeError(
            'The Blender STEP Importer add-on is not enabled. Install and enable '
            'STEP Importer from Blender Preferences > Get Extensions, then retry.'
        )
    result = bpy.ops.import_scene.step(
        filepath=source_path,
        up_axis='Y',
        rotation_deg='0',
        placement='ORIGIN',
        origin_offset='KEEP',
        scale=1.0,
        merge_objects=True,
        use_assembly_collections=False,
    )
    if 'FINISHED' not in result:
        raise RuntimeError('Blender STEP Importer did not finish the STEP import.')

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not meshes:
        raise RuntimeError('The STEP importer did not create any mesh objects.')

    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    # Cascadio outputs STEP geometry through glTF, whose coordinate unit is
    # metres. STL has no unit metadata; export as millimetre coordinates for
    # the SketchUp STL importer.
    result = bpy.ops.wm.stl_export(
        filepath=output_path,
        export_selected_objects=True,
        global_scale=export_scale,
        use_scene_unit=False,
        apply_modifiers=True,
        ascii_format=False,
    )
    if 'FINISHED' not in result or not os.path.isfile(output_path) or os.path.getsize(output_path) <= 84:
        raise RuntimeError('Blender did not write a usable STL file.')

    if report_path:
        with open(report_path, 'w') as report:
            report.write('OK\n')
except Exception:
    if report_path:
        try:
            with open(report_path, 'w') as report:
                report.write(traceback.format_exc())
        except Exception:
            pass
    raise
