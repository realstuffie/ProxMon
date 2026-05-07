QSGNode with a QSGImageNode would let you upload the frame directly to the GPU as a texture, skipping the CPU-side double buffer that QQuickPaintedItem uses. For a 1920x1080 VNC session at 60fps that's a meaningful difference.

The implementation would be:

Subclass QQuickItem instead of QQuickPaintedItem
Override updatePaintNode() to create/update a QSGImageNode
Call setTexture() with a QSGTexture created from the QImage frame
Call update() to schedule a repaint.
