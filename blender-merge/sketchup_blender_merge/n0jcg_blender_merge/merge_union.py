"""Headless Blender helper used by the SketchUp Make 2017 merge extension."""
import os
import sys
import bpy
import bmesh


def import_meshes(filepath, label):
    before = set(obj.as_pointer() for obj in bpy.data.objects)
    bpy.ops.wm.stl_import(
        filepath=filepath,
        global_scale=1.0,
        use_scene_unit=False,
        use_mesh_validate=True,
    )
    imported = [
        obj for obj in bpy.data.objects
        if obj.as_pointer() not in before and obj.type == 'MESH'
    ]
    if not imported:
        raise RuntimeError("No mesh objects were imported from " + filepath)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in imported:
        obj.select_set(True)
    active = imported[0]
    bpy.context.view_layer.objects.active = active
    if len(imported) > 1:
        bpy.ops.object.join()
        active = bpy.context.view_layer.objects.active
    active.name = label
    return active


def mesh_health(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    boundary = sum(1 for edge in bm.edges if edge.is_boundary)
    wire = sum(1 for edge in bm.edges if edge.is_wire)
    overused = sum(1 for edge in bm.edges if len(edge.link_faces) > 2)
    invalid = sum(1 for edge in bm.edges if not edge.is_manifold)
    bm.free()
    return {'invalid': invalid, 'boundary': boundary, 'wire': wire, 'overused': overused}


def check_manifold(obj, label):
    health = mesh_health(obj)
    invalid = health['invalid']
    if invalid:
        raise RuntimeError(
            label + " has " + str(invalid) + " non-manifold edges "
            "(open boundaries: " + str(health['boundary']) +
            ", loose edges: " + str(health['wire']) +
            ", edges with more than 2 faces: " + str(health['overused']) + ")."
        )


def boundary_components(bm):
    remaining = set(edge for edge in bm.edges if edge.is_boundary)
    components = []
    while remaining:
        seed = remaining.pop()
        component = [seed]
        stack = [seed]
        while stack:
            edge = stack.pop()
            for vert in edge.verts:
                for linked in vert.link_edges:
                    if linked in remaining and linked.is_boundary:
                        remaining.remove(linked)
                        component.append(linked)
                        stack.append(linked)
        components.append(component)
    return components


def repair_boolean_result(obj):
    """Preserve coordinates while repairing tiny defects and boundary loops."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if not bm.verts:
        bm.free()
        raise RuntimeError("Blender produced an empty union mesh.")

    xs = [vert.co.x for vert in bm.verts]
    ys = [vert.co.y for vert in bm.verts]
    zs = [vert.co.z for vert in bm.verts]
    span = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    tolerance = max(span * 1e-7, 1e-9)

    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=tolerance)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=tolerance)

    # The input meshes were manifold. Any boundary loop created by the Boolean
    # is therefore a result defect. Fill disconnected loops independently.
    for _attempt in range(3):
        components = boundary_components(bm)
        if not components:
            break
        before = sum(len(component) for component in components)
        for component in components:
            live_edges = [edge for edge in component if edge.is_valid and edge.is_boundary]
            if live_edges:
                bmesh.ops.holes_fill(bm, edges=live_edges, sides=0)
        after = sum(1 for edge in bm.edges if edge.is_boundary)
        if after >= before:
            break

    faces = list(bm.faces)
    if faces:
        bmesh.ops.recalc_face_normals(bm, faces=faces)
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return tolerance


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    if len(args) != 3:
        raise RuntimeError("Expected input A, input B, and output STL paths.")
    input_a, input_b, output = args

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    a = import_meshes(input_a, 'Merge A')
    b = import_meshes(input_b, 'Merge B')
    check_manifold(a, 'Object A')
    check_manifold(b, 'Object B')

    modifier = a.modifiers.new(name='N0JCG Union', type='BOOLEAN')
    modifier.operation = 'UNION'
    modifier.solver = 'EXACT'
    modifier.object = b
    if hasattr(modifier, 'use_hole_tolerant'):
        modifier.use_hole_tolerant = False
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = a.evaluated_get(depsgraph)
    result_mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    if result_mesh is None or len(result_mesh.polygons) == 0:
        raise RuntimeError("Blender produced an empty union result.")
    result_mesh.name = 'Merged Objects'
    a.modifiers.remove(modifier)
    old_mesh = a.data
    a.data = result_mesh
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    bpy.data.objects.remove(b, do_unlink=True)
    tolerance = repair_boolean_result(a)
    bpy.ops.object.select_all(action='DESELECT')
    a.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.wm.stl_export(
        filepath=output,
        export_selected_objects=True,
        # Use ASCII as a compatibility check for SketchUp's STL handoff.
        ascii_format=True,
        global_scale=1.0,
        use_scene_unit=False,
        apply_modifiers=True,
    )
    if not os.path.isfile(output) or os.path.getsize(output) <= 84:
        raise RuntimeError("Blender did not write a valid output STL.")

    # Validate through an actual STL round trip, repair any loops introduced by
    # serialization/import, then write the repaired mesh as the final result.
    roundtrip = import_meshes(output, 'Union STL Round Trip')
    roundtrip_tolerance = repair_boolean_result(roundtrip)
    health = mesh_health(roundtrip)
    print("N0JCG_REPAIR_TOLERANCE: " + str(max(tolerance, roundtrip_tolerance)))
    bpy.ops.object.select_all(action='DESELECT')
    roundtrip.select_set(True)
    bpy.context.view_layer.objects.active = roundtrip
    bpy.ops.wm.stl_export(
        filepath=output,
        export_selected_objects=True,
        ascii_format=True,
        global_scale=1.0,
        use_scene_unit=False,
        apply_modifiers=True,
    )
    if not os.path.isfile(output) or os.path.getsize(output) <= 84:
        raise RuntimeError("Blender did not write the final union STL.")
    final_check = import_meshes(output, 'Final STL Validation')
    final_health = mesh_health(final_check)
    print(
        "N0JCG_RESULT: invalid={invalid} boundary={boundary} wire={wire} overused={overused}".format(**final_health)
    )
    if final_health['invalid']:
        print(
            "N0JCG_WARNING: Saved STL candidate still has " + str(final_health['invalid']) +
            " non-manifold edges after Blender repair."
        )


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print("N0JCG Blender Merge error: " + str(error))
        raise
