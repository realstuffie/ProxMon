#include "vncframeview.h"

#include <QSGImageNode>
#include <QQuickWindow>

VncFrameView::VncFrameView(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(QQuickItem::ItemHasContents, true);
    setAcceptedMouseButtons(Qt::AllButtons);
    setFlag(QQuickItem::ItemAcceptsInputMethod);
    setFocus(true);
    setActiveFocusOnTab(true);
    setFlag(QQuickItem::ItemIsFocusScope);
}

// Returns the largest sub-rect of (0,0,viewW,viewH) that fits imgW×imgH
// with the aspect ratio preserved (letterbox / pillarbox).
static QRectF fitRect(qreal viewW, qreal viewH, qreal imgW, qreal imgH)
{
    if (viewW <= 0 || viewH <= 0 || imgW <= 0 || imgH <= 0)
        return QRectF();
    const qreal scale = qMin(viewW / imgW, viewH / imgH);
    return QRectF((viewW - imgW * scale) / 2.0,
                  (viewH - imgH * scale) / 2.0,
                  imgW * scale,
                  imgH * scale);
}

// Called on the render thread during the sync phase (main thread blocked).
QSGNode *VncFrameView::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (m_frame.isNull()) {
        delete oldNode;
        return nullptr;
    }

    // createImageNode() returns the backend-native node (OpenGL/Vulkan/Metal).
    // setOwnsTexture(true): setTexture() automatically frees the previous
    // texture — do not delete it manually.
    auto *node = static_cast<QSGImageNode *>(oldNode);
    if (!node) {
        node = window()->createImageNode();
        node->setFiltering(QSGTexture::Linear);
        node->setOwnsTexture(true);
    }

    if (m_dirty) {
        node->setTexture(window()->createTextureFromImage(m_frame));
        m_dirty = false;
    }

    node->setRect(fitRect(width(), height(), m_frame.width(), m_frame.height()));
    return node;
}

void VncFrameView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!m_frame.isNull())
        update();
}

void VncFrameView::releaseResources()
{
    QQuickItem::releaseResources();
}

void VncFrameView::updateFrame(const QImage &image, int x, int y, int w, int h)
{
    Q_UNUSED(x) Q_UNUSED(y) Q_UNUSED(w) Q_UNUSED(h)
    m_frame = image;
    m_dirty = true;
    update();
}
