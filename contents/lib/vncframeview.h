#pragma once

#include <QQuickItem>
#include <QImage>

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
    VncClient *m_client = nullptr;  // connections auto-break if it's destroyed
    QImage m_frame;  // written in updateFrame (main thread),
                     // read in updatePaintNode (render thread sync — main blocked)
    bool   m_dirty = false;
};
