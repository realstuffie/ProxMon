#include "vncframeview.h"

#include <QPainter>
#include <QMutexLocker>

VncFrameView::VncFrameView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    // Image render target instead of FramebufferObject. FBO mode caches the
    // rendered output and during a fast drag-resize Qt briefly scales the
    // stale FBO into the new geometry before the next paint catches up,
    // which manifests as a momentary stretch/zoom artifact. Image-render
    // costs slightly more CPU per paint but recreates cleanly on every
    // geometry change.
    setRenderTarget(QQuickPaintedItem::Image);
    setAcceptedMouseButtons(Qt::AllButtons);
    setFlag(QQuickItem::ItemAcceptsInputMethod);
    setFocus(true);
    setActiveFocusOnTab(true);
    setFlag(QQuickItem::ItemIsFocusScope);
}

// Compute the largest sub-rect of (0,0,width,height) that preserves the
// framebuffer aspect ratio. Used by both paint() and partial-update mapping
// so the two stay in sync.
static QRectF fitRect(qreal viewW, qreal viewH, qreal imgW, qreal imgH)
{
    if (viewW <= 0 || viewH <= 0 || imgW <= 0 || imgH <= 0)
        return QRectF();
    const qreal scale = qMin(viewW / imgW, viewH / imgH);
    const qreal fitW = imgW * scale;
    const qreal fitH = imgH * scale;
    return QRectF((viewW - fitW) / 2.0, (viewH - fitH) / 2.0, fitW, fitH);
}

void VncFrameView::paint(QPainter *painter)
{
    QMutexLocker lock(&m_mutex);
    if (m_frame.isNull()) return;
    const QRectF target = fitRect(width(), height(),
                                  m_frame.width(), m_frame.height());
    if (target.isEmpty()) return;

    // Letterbox/pillarbox the unused area so the guest never appears
    // stretched when window aspect ≠ framebuffer aspect.
    if (target.width() < width() || target.height() < height()) {
        painter->fillRect(QRectF(0, 0, width(), height()), Qt::black);
    }
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(target, m_frame);
}

void VncFrameView::updateFrame(const QImage &image, int x, int y, int w, int h)
{
    bool sizeChanged = false;
    {
        QMutexLocker lock(&m_mutex);
        sizeChanged = (m_frame.size() != image.size());
        m_frame = image;
    }
    // When the framebuffer's pixel dimensions change, the fit-rect math and
    // the letterbox/pillarbox region change too. A partial update would leave
    // stale pixels from the previous layout. Force a full repaint instead.
    if (sizeChanged
        || width() <= 0 || height() <= 0
        || image.width() <= 0 || image.height() <= 0) {
        update();
        return;
    }
    const QRectF target = fitRect(width(), height(),
                                  image.width(), image.height());
    if (target.isEmpty()) {
        update();
        return;
    }
    const qreal scale = target.width() / image.width();   // == target.height/image.height
    update(QRect(int(target.x() + x * scale),
                 int(target.y() + y * scale),
                 int(w * scale) + 2,
                 int(h * scale) + 2));
}
