#include "vncframeview.h"
#include "vncclient.h"

#include <QPainter>
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

void VncFrameView::setClient(VncClient *client)
{
    if (m_client == client) return;
    if (m_client) {
        QObject::disconnect(m_client, nullptr, this, nullptr);
    }
    m_client = client;
    if (m_client) {
        connect(m_client, &VncClient::frameUpdated,
                this, &VncFrameView::updateFrame);
        connect(m_client, &VncClient::frameSizeChanged, this, [this, client]() {
            prepareFrame(client->frameWidth(), client->frameHeight());
        });
        // A size may already be known (property set after connect started).
        prepareFrame(m_client->frameWidth(), m_client->frameHeight());
    }
    emit clientChanged();
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

void VncFrameView::prepareFrame(int w, int h)
{
    if (w <= 0 || h <= 0) return;
    if (m_frame.size() == QSize(w, h)) return;  // reconnect at same size keeps canvas
    m_frame = QImage(w, h, QImage::Format_ARGB32_Premultiplied);
    m_frame.fill(Qt::black);
    m_dirty = true;
    update();
}

void VncFrameView::updateFrame(const QImage &image, int x, int y, int w, int h)
{
    Q_UNUSED(w) Q_UNUSED(h)
    // No canvas yet: drop the rect. prepareFrame always precedes frames of a
    // given size (server init/resize emits frameSizeChanged first), so this
    // only skips data a later full update repaints anyway.
    if (m_frame.isNull() || image.isNull()) return;

    // The texture created in updatePaintNode still references m_frame, so the
    // first paint after each texture upload detaches (one full-frame memcpy).
    // Cheaper than converting/shipping full frames per update; goes away
    // entirely if the texture path moves to QRhi partial uploads.
    QPainter painter(&m_frame);
    painter.setCompositionMode(QPainter::CompositionMode_Source);
    painter.drawImage(x, y, image);
    painter.end();
    m_dirty = true;
    update();
}
