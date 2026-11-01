# N0JCG Boolean Tools for SketchUp 2017

Choose a Boolean operation from **Extensions > N0JCG Boolean Tools**, then click solid A followed by solid B:

- **Subtract B from A (A - B):** keeps only A's volume outside B.
- **Subtract A from B (B - A):** keeps only B's volume outside A.
- **Keep Overlapping Space (A intersection B):** keeps only the shared volume.
- **Keep Non-Overlapping Space (A XOR B):** keeps A−B and B−A as separate groups and discards the shared volume.

The extension makes temporary copies before the Boolean operation, so the original solids stay in the model. It selects the resulting groups when complete. Press **Esc** while picking to cancel.

Inputs must be groups or component instances at the same editing level and must be closed manifold solids. These operations use SketchUp Pro's Solid Tools API; it is not available in SketchUp Make 2017. If an operation fails, the extension aborts the model operation and reports the failure.

## Install

Install `N0JCG_Boolean_Tools_1.1.0.rbz` through SketchUp's Extension Manager.
