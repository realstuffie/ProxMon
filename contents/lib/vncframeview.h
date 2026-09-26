#pragma once

#include <QQuickItem>
#include <QImage>
#include <QBitArray>

class VncClient;

class VncFrameView : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT

    // Frame delivery is wired C++-to-C++ when this is set, skipping the QML/JS
    // signal-handler trampoline (one JS call + QVariant boxing per frame).
    Q_PROPERTY(VncClient *client READ client WRITE setClient NOTIFY clientChanged)

public:
    explicit VncFrameView(QQuickItem *parent = nullptr);

    VncClient *client() const { return m_client; }
    void setClient(VncClient *client);

public slots:
    // Allocate the persistent canvas for a new framebuffer size. Must run
    // before updateFrame delivers rects of that size (wired to the client's
    // frameSizeChanged, which is emitted before any frame of the new size).
    void prepareFrame(int w, int h);
    void updateFrame(const QImage &image, int x, int y, int w, int h);

signals:
    void clientChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void releaseResources() override;

private:
    // The view draws the canvas as a grid of tiles, each with its own
    // texture, and an update re-uploads only the tiles it touched. This only
    // affects GPU uploads. The requests sent to the VNC server stay the same.
    static constexpr int TileSize = 256;
    QRect tileRect(int index) const;

    VncClient *m_client = nullptr;  // connections auto-break if it's destroyed
    QImage m_frame;  // written in updateFrame (main thread),
                     // read in updatePaintNode (render thread sync - main blocked)
    // Same threading as m_frame. One bit per tile, row-major.
    QBitArray m_tileDirty;
    int  m_tileCols = 0;
    // Set when the frame size changes or the scene graph is new. Either one
    // means updatePaintNode has to recreate the tile nodes.
    bool m_rebuildTiles = true;
};
