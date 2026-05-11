#pragma once

#include <QQuickItem>
#include <QImage>

class VncFrameView : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VncFrameView(QQuickItem *parent = nullptr);

public slots:
    void updateFrame(const QImage &image, int x, int y, int w, int h);

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void releaseResources() override;

private:
    QImage m_frame;  // written in updateFrame (main thread),
                     // read in updatePaintNode (render thread sync — main blocked)
    bool   m_dirty = false;
};
